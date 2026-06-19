import Foundation

/// Synthetic data source for demo mode (`--demo` / `REEVE_DEMO=1`).
///
/// Holds a believable, mutable model of PM2 environments and processes so the
/// entire app can be driven — sparklines, crash-loop detection, restart/stop/
/// delete, daemon recovery, log streaming, notifications — without a single
/// real PM2 process running. All side-effecting `PM2Service` methods route here
/// in demo mode and mutate this in-memory model instead of touching the system.
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
        let port: Int?
        let cwd: String
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
                port: port,
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
    /// activity" stays fresh. Uptime advances on its own from `startedAt`.
    func tick() {
        let now = Date()
        for i in envs.indices {
            for j in envs[i].procs.indices where envs[i].procs[j].status == "online" {
                var p = envs[i].procs[j]
                p.cpu = clamp(p.cpu + Double.random(in: -3...3), 0.2, p.cpuBase * 1.8 + 4)
                p.memMB = clamp(p.memMB + Double.random(in: -6...6), p.memBase * 0.8, p.memBase * 1.2)
                p.lastLog = now
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

    // MARK: - Seed

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func seed() -> [Env] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let now = Date().timeIntervalSince1970
        func ms(agoSeconds: TimeInterval) -> Int64 { Int64((now - agoSeconds) * 1000) }
        func recent() -> Date { Date(timeIntervalSince1970: now - 2) }

        func online(_ name: String, _ pmId: Int, _ pid: Int, cpu: Double, mem: Double, port: Int?, age: TimeInterval, cwd: String) -> Proc {
            Proc(pid: pid, name: name, pmId: pmId, status: "online", cpu: cpu, memMB: mem,
                 cpuBase: cpu, memBase: mem, startedAt: ms(agoSeconds: age), createdAt: ms(agoSeconds: age),
                 restartCount: 0, port: port, cwd: cwd, lastLog: recent())
        }

        let day: TimeInterval = 86_400

        // 1. default workspace — healthy app on `main`
        let sidetrack = "\(home)/code/sidetrack"
        let defaultEnv = Env(
            path: "\(home)/.pm2",
            isActive: true,
            gitInfo: GitInfo(repoName: "sidetrack", branch: "main"),
            error: nil,
            procs: [
                online("web", 0, 4821, cpu: 12, mem: 184, port: 3000, age: 2 * day, cwd: sidetrack),
                online("worker", 1, 4822, cpu: 4, mem: 96, port: nil, age: 2 * day, cwd: sidetrack),
                Proc(pid: 0, name: "scheduler", pmId: 2, status: "stopped", cpu: 0, memMB: 0,
                     cpuBase: 3, memBase: 70, startedAt: 0, createdAt: ms(agoSeconds: 2 * day),
                     restartCount: 0, port: nil, cwd: sidetrack, lastLog: Date(timeIntervalSince1970: now - 3600)),
            ]
        )

        // 2. api workspace — feature branch, one errored migration
        let api = "\(home)/code/sidetrack-api"
        let apiEnv = Env(
            path: "\(home)/.pm2-api",
            isActive: true,
            gitInfo: GitInfo(repoName: "sidetrack-api", branch: "fredrivett/eng-3338-rate-limiting"),
            error: nil,
            procs: [
                online("api-server", 0, 5310, cpu: 22, mem: 312, port: 8080, age: 6 * 3600, cwd: api),
                online("queue-consumer", 1, 5311, cpu: 7, mem: 142, port: nil, age: 6 * 3600, cwd: api),
                Proc(pid: 0, name: "migrations", pmId: 2, status: "errored", cpu: 0, memMB: 0,
                     cpuBase: 5, memBase: 60, startedAt: 0, createdAt: ms(agoSeconds: 6 * 3600),
                     restartCount: 1, port: nil, cwd: api, lastLog: Date(timeIntervalSince1970: now - 300)),
            ]
        )

        // 3. marketing workspace — contains a crash-looping process
        let marketing = "\(home)/code/marketing-site"
        let marketingEnv = Env(
            path: "\(home)/.pm2-marketing",
            isActive: true,
            gitInfo: GitInfo(repoName: "marketing-site", branch: "main"),
            error: nil,
            procs: [
                online("next-dev", 0, 6201, cpu: 28, mem: 418, port: 4000, age: 4 * 3600, cwd: marketing),
                // crash-looping: 3+ restarts and uptime < 30s
                Proc(pid: 6202, name: "flaky-worker", pmId: 1, status: "online", cpu: 18, memMB: 88,
                     cpuBase: 16, memBase: 88, startedAt: ms(agoSeconds: 8), createdAt: ms(agoSeconds: 3 * 3600),
                     restartCount: 7, port: nil, cwd: marketing, lastLog: recent()),
            ]
        )

        // 4. broken daemon — surfaces the inline error + "Kill daemon" recovery
        let workerPool = Env(
            path: "\(home)/.pm2-worker-pool",
            isActive: true,
            gitInfo: nil,
            error: "connect EINVAL /var/folders/pm2/rpc.sock - daemon not responding",
            procs: []
        )

        // 5. inactive workspace — shows in the collapsed "Inactive" group
        let staging = Env(
            path: "\(home)/.pm2-staging",
            isActive: false,
            gitInfo: nil,
            error: nil,
            procs: []
        )

        return [defaultEnv, apiEnv, marketingEnv, workerPool, staging]
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    // MARK: - Log streaming

    /// A shell command that echoes realistic, colorizable log lines with small
    /// delays, then idles — so `PM2Service`'s real streaming/termination path
    /// drives demo logs with no special handling.
    static func logScript(for name: String) -> String {
        var parts: [String] = []
        for line in logLines(for: name) {
            let safe = line.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("echo '\(safe)'")
            parts.append("sleep 0.35")
        }
        parts.append("sleep 3600")
        return parts.joined(separator: "; ")
    }

    private static func logLines(for name: String) -> [String] {
        let p = "0|\(name) |"
        if name.contains("flaky") {
            return [
                "[TAILING] Tailing last 50 lines for [\(name)] process (out + err)",
                "\(p) Connecting to redis 127.0.0.1:6379",
                "\(p) ERROR ECONNREFUSED 127.0.0.1:6379",
                "\(p) Error: Redis connection lost",
                "\(p)     at TCPConnectWrap.afterConnect (node:net:1595:16)",
                "\(p) App crashed - waiting for file changes before restart",
                "\(p) Process restarting (attempt 7)",
            ]
        }
        if name.contains("migrat") {
            return [
                "[TAILING] Tailing last 50 lines for [\(name)] process (out + err)",
                "\(p) Running pending migrations...",
                "\(p) ERROR relation \"rate_limits\" already exists",
                "\(p) FATAL migration 20260618_add_rate_limits failed",
                "\(p)     at Migrator.run (/app/node_modules/knex/lib/migrate.js:142:9)",
                "\(p) Process exited with code 1",
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
            "\(p) POST /api/events     202 15ms",
        ]
    }
}
