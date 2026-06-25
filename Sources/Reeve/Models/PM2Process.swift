import Foundation

/// Decodes a value that may be a JSON string or number into an Int.
private enum StringOrInt: Decodable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else {
            throw DecodingError.typeMismatch(StringOrInt.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Int"))
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .string(let v): return Int(v)
        }
    }
}

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
    public let port: Int?

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

// Custom decoding from pm2 jlist JSON — only extracts fields we need.
// pm2_env contains the full process environment, which can include secrets.
// We enumerate its key *names* to find port variables but only decode the
// values of port-shaped keys, so secret values never enter memory.
extension PM2Process: Decodable {
    /// Coding key that accepts any string, used to enumerate `pm2_env` keys
    /// without modelling the whole (secret-bearing) environment.
    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

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

        // Extract port: prefer an explicit `--port`/`-p` arg, then fall back to
        // any `PORT` or `*_PORT` environment variable.
        let args = try env.decodeIfPresent([String].self, forKey: .args) ?? []
        if let argPort = PM2Process.port(fromArgs: args) {
            port = argPort
        } else {
            let envContainer = try top.nestedContainer(keyedBy: DynamicKey.self, forKey: .pm2Env)
            port = PM2Process.port(fromEnv: envContainer)
        }
    }

    /// Parse a port from process args, e.g. `--port 3000` or `-p 8080`.
    private static func port(fromArgs args: [String]) -> Int? {
        let joined = args.joined(separator: " ")
        guard let pattern = try? NSRegularExpression(pattern: #"(?:--port|-p)\s+(\d+)"#),
              let match = pattern.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
              let range = Range(match.range(at: 1), in: joined) else {
            return nil
        }
        return Int(joined[range])
    }

    /// Find a port among the `pm2_env` keys: the bare `PORT`, or a specific
    /// suffix like `SERVER_PORT`. A specific `*_PORT` wins over the generic
    /// `PORT`, with ties broken alphabetically so the result is deterministic
    /// regardless of JSON key order.
    private static func port(fromEnv container: KeyedDecodingContainer<DynamicKey>) -> Int? {
        let portKeys = container.allKeys.filter { key in
            let upper = key.stringValue.uppercased()
            return upper == "PORT" || upper.hasSuffix("_PORT")
        }
        let ordered = portKeys.sorted { lhs, rhs in
            let lhsSpecific = lhs.stringValue.uppercased() != "PORT"
            let rhsSpecific = rhs.stringValue.uppercased() != "PORT"
            if lhsSpecific != rhsSpecific { return lhsSpecific }
            return lhs.stringValue < rhs.stringValue
        }
        for key in ordered {
            if let parsed = try? container.decode(StringOrInt.self, forKey: key), let value = parsed.intValue {
                return value
            }
        }
        return nil
    }
}
