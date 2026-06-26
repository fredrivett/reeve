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

    /// Ports this process (and its child processes) are actively listening on,
    /// resolved from the OS via `SocketScanner` after decoding. Empty when the
    /// process isn't serving anything (e.g. a worker, or still booting).
    public var ports: [Int] = []

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
        case status, namespace
        case pmExecPath = "pm_exec_path"
        case pmCwd = "pm_cwd"
        case execMode = "exec_mode"
        case pmUptime = "pm_uptime"
        case restartTime = "restart_time"
        case createdAt = "created_at"
        case pmOutLogPath = "pm_out_log_path"
        case pmErrLogPath = "pm_err_log_path"
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
        // `ports` is resolved from the OS after decoding (see SocketScanner).
    }
}
