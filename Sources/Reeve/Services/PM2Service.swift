import Foundation
import Combine
import SwiftUI

@MainActor
public class PM2Service: ObservableObject {
    @Published public var environments: [PM2Environment] = []
    @Published public var processesByEnvironment: [String: [PM2Process]] = [:]
    @Published public var error: String?
    @Published public var isLoading = false
    @Published public var hasCompletedFirstScan = false

    public var totalOnlineCount: Int {
        processesByEnvironment.values.flatMap { $0 }.filter(\.isOnline).count
    }

    private let resolver = PM2BinaryResolver()
    private let scanner = EnvironmentScanner()
    private let notificationService = NotificationService()
    private var timer: Timer?
    private var cachedResolution: PM2BinaryResolver.Resolution?

    public let metricsHistory = MetricsHistory()
    public var isPolling = false

    public init() {
        notificationService.requestPermission()
        // Start polling immediately on creation
        startPolling()
    }

    public func startPolling(interval: TimeInterval = 3.0) {
        guard !isPolling else { return }
        isPolling = true
        // Initial fetch
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() async {
        let resolution: PM2BinaryResolver.Resolution
        do {
            resolution = try await resolver.resolve()
            cachedResolution = resolution
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }

        let scanned = scanner.scan()
        let activeEnvironments = scanned.filter(\.isActive)
        environments = scanned

        // Fetch processes from all active environments concurrently off the main actor
        let fetchedResults = await Task.detached { () -> [String: [PM2Process]] in
            let lock = NSLock()
            var results: [String: [PM2Process]] = [:]

            DispatchQueue.concurrentPerform(iterations: activeEnvironments.count) { index in
                let env = activeEnvironments[index]
                let processes = PM2Service.fetchProcessesSync(for: env, using: resolution)
                lock.lock()
                results[env.path] = processes
                lock.unlock()
            }

            return results
        }.value

        processesByEnvironment = fetchedResults

        // Record metrics history
        for env in activeEnvironments {
            if let processes = fetchedResults[env.path] {
                for process in processes where process.isOnline {
                    metricsHistory.record(process: process, environmentPath: env.path)
                }
                metricsHistory.recordEnvironment(path: env.path, processes: processes)
            }
        }

        // Check for crash/restart notifications
        for env in activeEnvironments {
            if let processes = fetchedResults[env.path] {
                notificationService.checkForChanges(environment: env, processes: processes)
            }
        }

        hasCompletedFirstScan = true
    }

    public func restart(process: PM2Process, environment: PM2Environment) async {
        await runControl(["restart", process.name], environment: environment)
    }

    public func stop(process: PM2Process, environment: PM2Environment) async {
        await runControl(["stop", process.name], environment: environment)
    }

    public func delete(process: PM2Process, environment: PM2Environment) async {
        await runControl(["delete", process.name], environment: environment)
    }

    public func killDaemon(environment: PM2Environment) async {
        await runControl(["kill"], environment: environment)
    }

    public func clearEnvironment(_ environment: PM2Environment) {
        try? FileManager.default.removeItem(atPath: environment.path)
        environments.removeAll { $0.path == environment.path }
    }

    public func clearInactiveEnvironments() {
        let inactive = environments.filter { !$0.isActive }
        for env in inactive {
            try? FileManager.default.removeItem(atPath: env.path)
        }
        environments.removeAll { !$0.isActive }
    }

    // MARK: - Log Streaming

    public func startLogStream(
        process: PM2Process,
        environment: PM2Environment,
        onLine: @escaping @Sendable (String) -> Void
    ) -> Process? {
        guard let resolution = cachedResolution else { return nil }

        let proc = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: resolution.binary)
        proc.arguments = ["logs", process.name, "--lines", "50", "--timestamp"]
        proc.environment = PM2Service.buildEnvDict(resolution: resolution, pm2Home: environment.path)
        proc.standardOutput = pipe
        proc.standardError = errPipe

        // Read stdout
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            onLine(line)
        }

        // Read stderr — pm2 logs routes error logs here
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            onLine(line)
        }

        do {
            try proc.run()
            return proc
        } catch {
            return nil
        }
    }

    public func stopLogStream(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    // MARK: - Private

    // Synchronous process fetch — runs off main actor via Task.detached
    private nonisolated static func fetchProcessesSync(
        for environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) -> [PM2Process] {
        do {
            let data = try runPM2Sync(["jlist"], environment: environment, using: resolution)
            var processes = try JSONDecoder().decode([PM2Process].self, from: data)
            // Stat log files to determine last activity time
            let fm = FileManager.default
            for i in processes.indices {
                var newest: Date?
                for logPath in [processes[i].outLogPath, processes[i].errLogPath] where !logPath.isEmpty {
                    if let attrs = try? fm.attributesOfItem(atPath: logPath),
                       let modified = attrs[.modificationDate] as? Date {
                        if newest == nil || modified > newest! {
                            newest = modified
                        }
                    }
                }
                processes[i].lastLogModified = newest
            }
            return processes
        } catch {
            // Silently return empty for environments with no processes or errors
            return []
        }
    }

    private nonisolated static func runPM2Sync(
        _ args: [String],
        environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) throws -> Data {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolution.binary)
        process.arguments = args
        process.environment = buildEnvDict(resolution: resolution, pm2Home: environment.path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private nonisolated static func buildEnvDict(resolution: PM2BinaryResolver.Resolution, pm2Home: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PM2_HOME"] = pm2Home
        env["PATH"] = resolution.path
        return env
    }

    private func runControl(_ args: [String], environment: PM2Environment) async {
        guard let resolution = try? await resolver.resolve() else { return }
        _ = await Task.detached {
            try? PM2Service.runPM2Sync(args, environment: environment, using: resolution)
        }.value
        await refresh()
    }
}
