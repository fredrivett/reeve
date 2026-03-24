import Foundation
import Combine
import SwiftUI

@MainActor
public class PM2Service: ObservableObject {
    @Published public var environments: [PM2Environment] = []
    @Published public var processesByEnvironment: [String: [PM2Process]] = [:]
    @Published public var errorsByEnvironment: [String: String] = [:]
    @Published public var error: String?
    @Published public var isLoading = false
    @Published public var hasCompletedFirstScan = false

    /// Tracks consecutive fetch failures per environment for backoff
    private var consecutiveFailures: [String: Int] = [:]
    private var pollCount: Int = 0

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

        var scanned = scanner.scan()
        // Carry forward existing git info to avoid flashing during refresh
        let existingGitInfo = Dictionary(uniqueKeysWithValues: environments.compactMap { env in
            env.gitInfo.map { (env.path, $0) }
        })
        for i in scanned.indices {
            scanned[i].gitInfo = existingGitInfo[scanned[i].path]
        }
        let activeEnvironments = scanned.filter(\.isActive)
        environments = scanned

        pollCount += 1

        // Filter out environments that should be skipped due to backoff
        let environmentsToFetch = activeEnvironments.filter { env in
            let failures = consecutiveFailures[env.path] ?? 0
            guard failures > 0 else { return true }
            // Exponential backoff: skip every 2^(failures-1) polls, capped at 32 (~96s)
            let interval = min(1 << (failures - 1), 32)
            return pollCount % interval == 0
        }

        // Fetch processes and resolve git info from all active environments concurrently off the main actor
        let (fetchedResults, gitInfoResults, errorResults) = await Task.detached { () -> ([String: [PM2Process]], [String: GitInfo], [String: String]) in
            let lock = NSLock()
            var results: [String: [PM2Process]] = [:]
            var gitResults: [String: GitInfo] = [:]
            var errors: [String: String] = [:]

            DispatchQueue.concurrentPerform(iterations: environmentsToFetch.count) { index in
                let env = environmentsToFetch[index]
                let fetchResult = PM2Service.fetchProcessesSync(for: env, using: resolution)

                var processes: [PM2Process] = []
                var errorMessage: String?

                switch fetchResult {
                case .success(let procs):
                    processes = procs
                case .failure(let msg):
                    errorMessage = msg
                }

                // Resolve git info from the first process with a cwd
                var gitInfo: GitInfo?
                if let firstCwd = processes.first(where: { !$0.cwd.isEmpty })?.cwd {
                    gitInfo = PM2Environment.resolveGitInfo(from: firstCwd)
                }

                lock.lock()
                results[env.path] = processes
                if let gi = gitInfo {
                    gitResults[env.path] = gi
                }
                if let err = errorMessage {
                    errors[env.path] = err
                }
                lock.unlock()
            }

            return (results, gitResults, errors)
        }.value

        // Merge fetched results with existing (for environments skipped by backoff)
        for (path, processes) in fetchedResults {
            processesByEnvironment[path] = processes
        }
        // Clear processes for environments that are no longer active
        let activePaths = Set(activeEnvironments.map(\.path))
        for path in processesByEnvironment.keys where !activePaths.contains(path) {
            processesByEnvironment.removeValue(forKey: path)
        }

        // Update error tracking and backoff counters
        for env in environmentsToFetch {
            if let errMsg = errorResults[env.path] {
                errorsByEnvironment[env.path] = errMsg
                consecutiveFailures[env.path] = (consecutiveFailures[env.path] ?? 0) + 1
            } else {
                errorsByEnvironment.removeValue(forKey: env.path)
                consecutiveFailures.removeValue(forKey: env.path)
            }
        }

        // Apply resolved git info to environments
        for i in environments.indices {
            if let gi = gitInfoResults[environments[i].path] {
                environments[i].gitInfo = gi
            }
        }

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
        // Force-kill all PM2 processes for this environment by finding them via PM2_HOME in their
        // command line args, then fall back to pm2 kill for good measure.
        await Task.detached {
            PM2Service.forceKillDaemon(for: environment)
        }.value

        // Reset backoff state so the next poll checks cleanly
        consecutiveFailures.removeValue(forKey: environment.path)
        errorsByEnvironment.removeValue(forKey: environment.path)
        await refresh()
    }

    /// Finds and kills all PM2 God Daemon processes associated with a PM2_HOME directory.
    private nonisolated static func forceKillDaemon(for environment: PM2Environment) {
        let pm2Home = environment.path

        // 1. Kill via pid file (most reliable for the "current" daemon)
        let pidPath = (pm2Home as NSString).appendingPathComponent("pm2.pid")
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = pid_t(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGKILL)
        }

        // 2. Find all PIDs matching this PM2_HOME path and kill them directly.
        //    pgrep -f matches the full command line; PM2 God Daemons include the PM2_HOME path.
        let pgrep = Process()
        let pipe = Pipe()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", pm2Home]
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        try? pgrep.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        if let output = String(data: data, encoding: .utf8) {
            for line in output.split(separator: "\n") {
                if let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) {
                    kill(pid, SIGKILL)
                }
            }
        }

        // 3. Clean up stale pid/lock files
        try? FileManager.default.removeItem(atPath: pidPath)
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

    enum FetchResult: Sendable {
        case success([PM2Process])
        case failure(String)
    }

    // Synchronous process fetch — runs off main actor via Task.detached
    /// Check if a PM2 daemon is currently running for this environment by reading its pid file.
    /// This avoids running any pm2 CLI command (which would auto-spawn a new daemon).
    private nonisolated static func isDaemonRunning(for environment: PM2Environment) -> Bool {
        let pidPath = (environment.path as NSString).appendingPathComponent("pm2.pid")
        guard let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = pid_t(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        // kill(pid, 0) checks if the process exists without sending a signal
        return kill(pid, 0) == 0
    }

    private nonisolated static func fetchProcessesSync(
        for environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) -> FetchResult {
        // If no daemon is running, return empty — don't call pm2 which would spawn one
        guard isDaemonRunning(for: environment) else {
            return .success([])
        }
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
            return .success(processes)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private nonisolated static func runPM2Sync(
        _ args: [String],
        environment: PM2Environment,
        using resolution: PM2BinaryResolver.Resolution
    ) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolution.binary)
        process.arguments = args
        process.environment = buildEnvDict(resolution: resolution, pm2Home: environment.path)
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PM2Error.commandFailed(status: process.terminationStatus, message: stderr)
        }
        return data
    }

    enum PM2Error: LocalizedError {
        case commandFailed(status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(_, let message):
                return message.isEmpty ? "pm2 command failed" : message
            }
        }
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
