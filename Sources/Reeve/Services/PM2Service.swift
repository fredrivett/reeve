import Foundation
import Combine
import SwiftUI

@MainActor
class PM2Service: ObservableObject {
    @Published var environments: [PM2Environment] = []
    @Published var processesByEnvironment: [String: [PM2Process]] = [:]
    @Published var error: String?
    @Published var isLoading = false

    var totalOnlineCount: Int {
        processesByEnvironment.values.flatMap { $0 }.filter(\.isOnline).count
    }

    private let resolver = PM2BinaryResolver()
    private let scanner = EnvironmentScanner()
    private let notificationService = NotificationService()
    private var timer: Timer?
    private var cachedResolution: PM2BinaryResolver.Resolution?

    var isPolling = false

    init() {
        notificationService.requestPermission()
        // Start polling immediately on creation
        startPolling()
    }

    func startPolling(interval: TimeInterval = 3.0) {
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

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
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

        // Check for crash/restart notifications
        for env in activeEnvironments {
            if let processes = fetchedResults[env.path] {
                notificationService.checkForChanges(environment: env, processes: processes)
            }
        }
    }

    func restart(process: PM2Process, environment: PM2Environment) async {
        await runControl(["restart", process.name], environment: environment)
    }

    func stop(process: PM2Process, environment: PM2Environment) async {
        await runControl(["stop", process.name], environment: environment)
    }

    func delete(process: PM2Process, environment: PM2Environment) async {
        await runControl(["delete", process.name], environment: environment)
    }

    // MARK: - Log Streaming

    func startLogStream(
        process: PM2Process,
        environment: PM2Environment,
        onLine: @escaping @Sendable (String) -> Void
    ) -> Process? {
        guard let resolution = cachedResolution else { return nil }

        let proc = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: resolution.binary)
        proc.arguments = ["logs", process.name, "--lines", "50"]
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

    func stopLogStream(_ process: Process?) {
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
            let processes = try JSONDecoder().decode([PM2Process].self, from: data)
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
