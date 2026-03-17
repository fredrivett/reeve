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
    private let maxConcurrency = 8

    init() {
        notificationService.requestPermission()
    }

    func startPolling(interval: TimeInterval = 3.0) {
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
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }

        let scanned = scanner.scan()
        let activeEnvironments = scanned.filter(\.isActive)
        environments = scanned

        // Fetch processes from all active environments concurrently, capped
        var results: [String: [PM2Process]] = [:]

        await withTaskGroup(of: (String, [PM2Process]).self) { group in
            var launched = 0
            for env in activeEnvironments {
                if launched >= maxConcurrency {
                    if let result = await group.next() {
                        results[result.0] = result.1
                    }
                }
                group.addTask { [weak self] in
                    guard let self else { return (env.path, []) }
                    let processes = await self.fetchProcesses(for: env, using: resolution)
                    return (env.path, processes)
                }
                launched += 1
            }
            for await result in group {
                results[result.0] = result.1
            }
        }

        processesByEnvironment = results

        // Check for crash/restart notifications
        for env in activeEnvironments {
            if let processes = results[env.path] {
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
        guard let resolution = try? _syncResolve() else { return nil }

        let proc = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: resolution.binary)
        proc.arguments = ["logs", process.name, "--lines", "50"]
        proc.environment = buildEnv(resolution: resolution, pm2Home: environment.path)
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

    private nonisolated func fetchProcesses(
        for environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) async -> [PM2Process] {
        do {
            let data = try await runPM2(["jlist"], environment: environment, using: resolution)
            return (try? JSONDecoder().decode([PM2Process].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    private nonisolated func runPM2(
        _ args: [String],
        environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: resolution.binary)
            process.arguments = args
            process.environment = buildEnv(resolution: resolution, pm2Home: environment.path)
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: data)
        }
    }

    private func runControl(_ args: [String], environment: PM2Environment) async {
        guard let resolution = try? await resolver.resolve() else { return }
        _ = try? await runPM2(args, environment: environment, using: resolution)
        // Refresh immediately after control action
        await refresh()
    }

    private nonisolated func buildEnv(resolution: PM2BinaryResolver.Resolution, pm2Home: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PM2_HOME"] = pm2Home
        env["PATH"] = resolution.path
        return env
    }

    // Synchronous resolve for log streaming (uses cached value)
    private nonisolated func _syncResolve() throws -> PM2BinaryResolver.Resolution {
        // We need a synchronous path here — use a semaphore for the rare case cache is empty
        let semaphore = DispatchSemaphore(value: 0)
        var result: PM2BinaryResolver.Resolution?
        var resolveError: Error?

        Task {
            do {
                result = try await resolver.resolve()
            } catch {
                resolveError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let error = resolveError { throw error }
        guard let resolution = result else {
            throw PM2BinaryResolver.ResolverError.notFound
        }
        return resolution
    }
}
