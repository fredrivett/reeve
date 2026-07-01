import Foundation

public struct PM2Process: Identifiable, Sendable {
    public let pid: Int
    public let name: String
    public let pmId: Int
    public let memoryBytes: Int
    public let cpuPercent: Double
    public let status: String
    public let namespace: String
    public let execPath: String
    public let cwd: String
    public let execMode: String
    public let uptime: Int64
    public let restartCount: Int
    public let createdAt: Int64
    public let outLogPath: String
    public let errLogPath: String

    /// The port this process is configured to bind, parsed from its pm2 args
    /// (or a `PORT` env var). Best-effort: nil when we can't determine it. Used
    /// only to diagnose bind conflicts — the ports actually served come from the
    /// OS via `ports`, never from here.
    public let desiredPort: Int?

    /// Ports this process (and its child processes) are actively listening on,
    /// resolved from the OS via `SocketScanner` after decoding. Empty when the
    /// process isn't serving anything (e.g. a worker, or still booting).
    public var ports: [Int] = []

    /// Set after decoding when the process is failing to bind `desiredPort`
    /// because another process is holding it ("Address already in use"). The
    /// value is the contended port. `nil` when there's no conflict.
    public var portConflict: Int?

    /// Most recent modification time of the process's log files (set after decoding).
    public var lastLogModified: Date?

    public var id: String { "\(pmId)" }

    public var isOnline: Bool { status == "online" }
    public var isStopped: Bool { status == "stopped" }
    public var isErrored: Bool { status == "errored" }

    /// Process is crash-looping: restarted multiple times and uptime under 30s
    public var isCrashLooping: Bool {
        guard isOnline, restartCount >= 3, uptime > 0 else { return false }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = max(0, now - uptime)
        return uptimeMs < 30_000
    }

    public var memoryMB: Double {
        Double(memoryBytes) / 1_048_576.0
    }

    public var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1fGB", memoryMB / 1024.0)
        }
        return String(format: "%.0fMB", memoryMB)
    }

    public var formattedCPU: String {
        String(format: "%.0f%%", cpuPercent)
    }

    public var formattedLastActivity: String {
        guard let date = lastLogModified else { return "–" }
        let elapsed = max(0, Int64(Date().timeIntervalSince1970 - date.timeIntervalSince1970))
        let minutes = elapsed / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(elapsed)s"
    }

    public var formattedUptime: String {
        guard uptime > 0 else { return "–" }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsed = max(0, now - uptime)
        let seconds = elapsed / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}

// Custom decoding from pm2 jlist JSON — only extracts the fields we need.
// pm2_env contains the full process environment, which can include secrets,
// so we never enumerate it; ports are resolved separately from the OS via
// `SocketScanner`.
extension PM2Process: Decodable {
    private enum TopKeys: String, CodingKey {
        case pid, name, monit
        case pmId = "pm_id"
        case pm2Env = "pm2_env"
    }

    private enum MonitKeys: String, CodingKey {
        case memory, cpu
    }

    private enum EnvKeys: String, CodingKey {
        case status, namespace, args
        case pmExecPath = "pm_exec_path"
        case pmCwd = "pm_cwd"
        case execMode = "exec_mode"
        case pmUptime = "pm_uptime"
        case restartTime = "restart_time"
        case createdAt = "created_at"
        case pmOutLogPath = "pm_out_log_path"
        case pmErrLogPath = "pm_err_log_path"
        case port = "PORT"
    }

    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        pid = try top.decode(Int.self, forKey: .pid)
        name = try top.decode(String.self, forKey: .name)
        pmId = try top.decode(Int.self, forKey: .pmId)

        let monit = try top.nestedContainer(keyedBy: MonitKeys.self, forKey: .monit)
        memoryBytes = try monit.decode(Int.self, forKey: .memory)
        cpuPercent = try monit.decode(Double.self, forKey: .cpu)

        let env = try top.nestedContainer(keyedBy: EnvKeys.self, forKey: .pm2Env)
        status = try env.decode(String.self, forKey: .status)
        namespace = try env.decodeIfPresent(String.self, forKey: .namespace) ?? "default"
        execPath = try env.decodeIfPresent(String.self, forKey: .pmExecPath) ?? ""
        cwd = try env.decodeIfPresent(String.self, forKey: .pmCwd) ?? ""
        execMode = try env.decodeIfPresent(String.self, forKey: .execMode) ?? "fork_mode"
        uptime = try env.decodeIfPresent(Int64.self, forKey: .pmUptime) ?? 0
        restartCount = try env.decodeIfPresent(Int.self, forKey: .restartTime) ?? 0
        createdAt = try env.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        outLogPath = try env.decodeIfPresent(String.self, forKey: .pmOutLogPath) ?? ""
        errLogPath = try env.decodeIfPresent(String.self, forKey: .pmErrLogPath) ?? ""

        // Best-effort bind port: prefer the CLI args (uvicorn/gunicorn/hypercorn/
        // node all pass it there), falling back to a PORT env var. Only a single,
        // named env key is read — never the full environment (secrets).
        let args = try env.decodeIfPresent([String].self, forKey: .args) ?? []
        // PORT may be encoded as a string or a number depending on the launcher.
        var portEnv = (try? env.decodeIfPresent(String.self, forKey: .port)).flatMap { $0 }
        if portEnv == nil, let portInt = try? env.decodeIfPresent(Int.self, forKey: .port) {
            portEnv = String(portInt)
        }
        desiredPort = PM2Process.parsePort(fromArgs: args, portEnv: portEnv)
    }

    /// Extract a bind port from pm2 launch args, falling back to a `PORT` env
    /// value. Handles the common forms: `--port N`, `--port=N`, `-p N`,
    /// `--bind host:N`, `-b host:N` (and their `=` variants). Returns the first
    /// port found, or nil.
    static func parsePort(fromArgs args: [String], portEnv: String? = nil) -> Int? {
        func validPort(_ value: Substring) -> Int? {
            guard let n = Int(value), (1...65535).contains(n) else { return nil }
            return n
        }
        var index = 0
        while index < args.count {
            let arg = args[index]
            let next: String? = index + 1 < args.count ? args[index + 1] : nil

            if arg == "--port" || arg == "-p", let next, let port = validPort(next[...]) {
                return port
            }
            if let eq = arg.firstIndex(of: "="), arg.hasPrefix("--port") {
                if let port = validPort(arg[arg.index(after: eq)...]) { return port }
            }
            // Bind targets look like `host:port`, `:port`, or `[::1]:port` — the
            // port is always after the final colon.
            if arg == "--bind" || arg == "-b", let next, let colon = next.lastIndex(of: ":"),
               let port = validPort(next[next.index(after: colon)...]) {
                return port
            }
            if arg.hasPrefix("--bind=") || arg.hasPrefix("-b="),
               let eq = arg.firstIndex(of: "=") {
                let value = arg[arg.index(after: eq)...]
                if let colon = value.lastIndex(of: ":"), let port = validPort(value[value.index(after: colon)...]) {
                    return port
                }
            }
            index += 1
        }
        if let portEnv, let port = validPort(portEnv[...]) { return port }
        return nil
    }
}
