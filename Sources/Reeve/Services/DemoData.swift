import Foundation

/// Synthetic data source for demo mode (`--demo` / `REEVE_DEMO=1`).
///
/// Holds a believable, mutable model of PM2 environments and processes so the
/// entire app can be driven — sparklines, crash-loop detection, restart/stop/
/// delete, daemon recovery, log streaming, notifications — without a single
/// real PM2 process running. All side-effecting `PM2Service` methods route here
/// in demo mode and mutate this in-memory model instead of touching the system.
///
/// The seed deliberately includes the same app (`sidetrack`) running in three
/// separate workspaces on different branches — mirroring multiple Conductor
/// worktrees of one repo, where reeve's per-workspace grouping earns its keep.
@MainActor
final class DemoData {

    /// One synthetic process. Mutable so jitter and controls can evolve it in place.
    struct Proc {
        let pid: Int
        let name: String
        let pmId: Int
        var status: String
        var cpu: Double
        var memMB: Double
        let cpuBase: Double
        let memBase: Double
        var startedAt: Int64   // pm_uptime, ms — uptime ticks up naturally from here
        let createdAt: Int64   // ms
        var restartCount: Int
        let ports: [Int]
        let cwd: String
        let crashLoop: Bool     // keep this process perpetually crash-looping
        var lastLog: Date?

        func snapshot() -> PM2Process {
            let online = status == "online"
            return PM2Process(
                pid: online ? pid : 0,
                name: name,
                pmId: pmId,
                memoryBytes: online ? Int(memMB * 1_048_576) : 0,
                cpuPercent: online ? cpu : 0,
                status: status,
                namespace: "default",
                execPath: "/usr/local/bin/node",
                cwd: cwd,
                execMode: "fork_mode",
                uptime: online ? startedAt : 0,
                restartCount: restartCount,
                createdAt: createdAt,
                outLogPath: "",
                errLogPath: "",
                ports: ports,
                lastLogModified: lastLog
            )
        }
    }

    /// One synthetic environment (PM2 workspace).
    struct Env {
        let path: String
        var isActive: Bool
        var gitInfo: GitInfo?
        var error: String?
        var procs: [Proc]
    }

    private(set) var envs: [Env]
    private var tickCount = 0

    init() {
        envs = DemoData.seed()
    }

    // MARK: - Snapshots (consumed by PM2Service's @Published state)

    var environmentsSnapshot: [PM2Environment] {
        envs.map { e in
            var env = PM2Environment(path: e.path, isActive: e.isActive)
            env.gitInfo = e.gitInfo
            return env
        }
    }

    func processesSnapshot() -> [String: [PM2Process]] {
        var out: [String: [PM2Process]] = [:]
        for e in envs where e.isActive {
            out[e.path] = e.procs.map { $0.snapshot() }
        }
        return out
    }

    func errorsSnapshot() -> [String: String] {
        var out: [String: String] = [:]
        for e in envs where e.isActive {
            if let err = e.error { out[e.path] = err }
        }
        return out
    }

    // MARK: - Per-poll evolution

    /// Advance one poll: jitter live CPU/memory so sparklines move and "last
    /// activity" stays fresh; keep crash-loopers perpetually restarting so the
    /// crash-loop UI stays visible for as long as the demo runs.
    func tick() {
        tickCount += 1
        let now = Date()
        let nowMs = DemoData.nowMs()
        for i in envs.indices {
            for j in envs[i].procs.indices where envs[i].procs[j].status == "online" {
                var p = envs[i].procs[j]
                p.cpu = clamp(p.cpu + Double.random(in: -3...3), 0.2, p.cpuBase * 1.8 + 4)
                p.memMB = clamp(p.memMB + Double.random(in: -6...6), p.memBase * 0.8, p.memBase * 1.2)
                p.lastLog = now
                if p.crashLoop {
                    // Keep uptime under the 30s crash-loop threshold, and bump the
                    // restart count occasionally (fires a "restarted" notification).
                    p.startedAt = nowMs - Int64.random(in: 4000...12000)
                    if tickCount % 4 == 0 { p.restartCount += 1 }
                }
                envs[i].procs[j] = p
            }
        }
    }

    // MARK: - Mutations (mirror PM2Service controls)

    func restart(name: String, envPath: String) {
        mutate(name: name, envPath: envPath) { p in
            p.status = "online"
            p.restartCount += 1
            p.startedAt = DemoData.nowMs()
            p.cpu = p.cpuBase
            p.memMB = p.memBase
            p.lastLog = Date()
        }
    }

    func stop(name: String, envPath: String) {
        mutate(name: name, envPath: envPath) { $0.status = "stopped" }
    }

    func delete(name: String, envPath: String) {
        guard let i = envs.firstIndex(where: { $0.path == envPath }) else { return }
        envs[i].procs.removeAll { $0.name == name }
    }

    /// Simulate killing the daemon: the workspace goes inactive and empties.
    func killDaemon(envPath: String) {
        guard let i = envs.firstIndex(where: { $0.path == envPath }) else { return }
        envs[i].isActive = false
        envs[i].error = nil
        envs[i].procs = []
    }

    func clearEnvironment(envPath: String) {
        envs.removeAll { $0.path == envPath }
    }

    func clearInactive() {
        envs.removeAll { !$0.isActive }
    }

    private func mutate(name: String, envPath: String, _ body: (inout Proc) -> Void) {
        guard let i = envs.firstIndex(where: { $0.path == envPath }),
              let j = envs[i].procs.firstIndex(where: { $0.name == name }) else { return }
        body(&envs[i].procs[j])
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    // MARK: - Seed

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func seed() -> [Env] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let now = Date().timeIntervalSince1970
        func ms(_ ago: TimeInterval) -> Int64 { Int64((now - ago) * 1000) }
        func recent() -> Date { Date(timeIntervalSince1970: now - 2) }

        // Proc factory. Only `name` and `pmId` are required — every other field
        // has a default, keeping the call sites terse and readable.
        func proc(_ name: String, _ pmId: Int,
                  cpu: Double = 0, mem: Double = 0,
                  status: String = "online", ports: [Int] = [],
                  age: TimeInterval = 2 * 86_400, started: TimeInterval? = nil,
                  restarts: Int = 0, crash: Bool = false,
                  cwd: String = "", lastLog: Date? = nil) -> Proc {
            let online = status == "online"
            return Proc(
                pid: online ? 4000 + pmId * 7 + 13 : 0,
                name: name,
                pmId: pmId,
                status: status,
                cpu: cpu,
                memMB: mem,
                cpuBase: cpu,
                memBase: mem,
                startedAt: online ? ms(started ?? age) : 0,
                createdAt: ms(age),
                restartCount: restarts,
                ports: ports,
                cwd: cwd,
                crashLoop: crash,
                lastLog: lastLog ?? (online ? recent() : Date(timeIntervalSince1970: now - 600))
            )
        }

        func sidetrack(_ branch: String) -> GitInfo { GitInfo(repoName: "sidetrack", branch: branch) }

        // The same app (`sidetrack`) running in three workspaces — like three
        // Conductor worktrees of one repo, each on its own branch and port.
        let main = "\(home)/code/sidetrack"
        let rateLimit = "\(home)/conductor/workspaces/sidetrack/rate-limiting"
        let darkMode = "\(home)/conductor/workspaces/sidetrack/dark-mode"

        let mainEnv = Env(
            path: "\(home)/.pm2",
            isActive: true,
            gitInfo: sidetrack("main"),
            error: nil,
            procs: [
                proc("web", 0, cpu: 12, mem: 184, ports: [3000], cwd: main),
                proc("worker", 1, cpu: 4, mem: 96, cwd: main),
                proc("scheduler", 2, status: "stopped", lastLog: Date(timeIntervalSince1970: now - 3600))
            ]
        )

        let rateLimitEnv = Env(
            path: "\(home)/.pm2-rate-limiting",
            isActive: true,
            gitInfo: sidetrack("fredrivett/eng-3338-rate-limiting"),
            error: nil,
            procs: [
                proc("web", 0, cpu: 18, mem: 206, ports: [3010], age: 6 * 3600, cwd: rateLimit),
                proc("worker", 1, cpu: 6, mem: 112, age: 6 * 3600, cwd: rateLimit),
                proc("migrations", 2, status: "errored", age: 6 * 3600, restarts: 1, cwd: rateLimit)
            ]
        )

        // Third worktree: its worker is crash-looping (broken work-in-progress).
        let darkModeEnv = Env(
            path: "\(home)/.pm2-dark-mode",
            isActive: true,
            gitInfo: sidetrack("fredrivett/eng-3401-dark-mode"),
            error: nil,
            procs: [
                proc("web", 0, cpu: 25, mem: 232, ports: [3020], age: 90 * 60, cwd: darkMode),
                proc("worker", 1, cpu: 16, mem: 88, age: 3 * 3600, started: 8, restarts: 7, crash: true, cwd: darkMode)
            ]
        )

        // A different app, for contrast against the duplicated sidetrack workspaces.
        let marketing = "\(home)/code/marketing-site"
        let marketingEnv = Env(
            path: "\(home)/.pm2-marketing",
            isActive: true,
            gitInfo: GitInfo(repoName: "marketing-site", branch: "main"),
            error: nil,
            procs: [
                proc("next-dev", 0, cpu: 28, mem: 418, ports: [4000], age: 4 * 3600, cwd: marketing)
            ]
        )

        // Broken daemon — surfaces the inline error + "Kill daemon" recovery.
        let workerPool = Env(
            path: "\(home)/.pm2-worker-pool",
            isActive: true,
            gitInfo: nil,
            error: "connect EINVAL /var/folders/pm2/rpc.sock - daemon not responding",
            procs: []
        )

        // Inactive workspace — shows in the collapsed "Inactive" group.
        let staging = Env(
            path: "\(home)/.pm2-staging",
            isActive: false,
            gitInfo: nil,
            error: nil,
            procs: []
        )

        return [mainEnv, rateLimitEnv, darkModeEnv, marketingEnv, workerPool, staging]
    }

    // MARK: - Log streaming

    /// A shell command that echoes realistic, colorizable log lines with small
    /// delays, then idles — so `PM2Service`'s real streaming/termination path
    /// drives demo logs with no special handling.
    static func logScript(for name: String, crashing: Bool) -> String {
        var parts: [String] = []
        for line in logLines(for: name, crashing: crashing) {
            let safe = line.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("echo '\(safe)'")
            parts.append("sleep 0.35")
        }
        parts.append("sleep 3600")
        return parts.joined(separator: "; ")
    }

    private static func logLines(for name: String, crashing: Bool) -> [String] {
        let p = "0|\(name) |"
        if crashing {
            return [
                "[TAILING] Tailing last 50 lines for [\(name)] process (out + err)",
                "\(p) Connecting to redis 127.0.0.1:6379",
                "\(p) ERROR ECONNREFUSED 127.0.0.1:6379",
                "\(p) Error: Redis connection lost",
                "\(p)     at TCPConnectWrap.afterConnect (node:net:1595:16)",
                "\(p) App crashed - waiting for file changes before restart",
                "\(p) Process restarting (attempt 7)"
            ]
        }
        if name.contains("migrat") {
            return [
                "[TAILING] Tailing last 50 lines for [\(name)] process (out + err)",
                "\(p) Running pending migrations...",
                "\(p) ERROR relation \"rate_limits\" already exists",
                "\(p) FATAL migration 20260618_add_rate_limits failed",
                "\(p)     at Migrator.run (/app/node_modules/knex/lib/migrate.js:142:9)",
                "\(p) Process exited with code 1"
            ]
        }
        return [
            "[TAILING] Tailing last 50 lines for [\(name)] process (out + err)",
            "\(p) GET /                200 6ms",
            "\(p) GET /api/session     200 11ms",
            "\(p) GET /api/projects    200 23ms",
            "\(p) POST /api/projects   201 48ms",
            "\(p) WARN slow query users.findAll took 812ms",
            "\(p) GET /api/projects    200 9ms",
            "\(p) GET /healthz         200 1ms",
            "\(p) POST /api/events     202 15ms"
        ]
    }
}
