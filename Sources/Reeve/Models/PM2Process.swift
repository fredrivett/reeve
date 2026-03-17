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

struct PM2Process: Identifiable {
    let pid: Int
    let name: String
    let pmId: Int
    let memoryBytes: Int
    let cpuPercent: Double
    let status: String
    let namespace: String
    let execPath: String
    let cwd: String
    let execMode: String
    let uptime: Int64
    let restartCount: Int
    let createdAt: Int64
    let outLogPath: String
    let errLogPath: String
    let port: Int?

    var id: String { "\(pmId)" }

    var isOnline: Bool { status == "online" }
    var isStopped: Bool { status == "stopped" }
    var isErrored: Bool { status == "errored" }

    /// Process is crash-looping: restarted multiple times and uptime under 30s
    var isCrashLooping: Bool {
        guard isOnline, restartCount >= 3, uptime > 0 else { return false }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = max(0, now - uptime)
        return uptimeMs < 30_000
    }

    var memoryMB: Double {
        Double(memoryBytes) / 1_048_576.0
    }

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1fGB", memoryMB / 1024.0)
        }
        return String(format: "%.0fMB", memoryMB)
    }

    var formattedCPU: String {
        String(format: "%.0f%%", cpuPercent)
    }

    var formattedUptime: String {
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
// pm2_env contains the full process environment including secrets;
// we deliberately avoid decoding the entire object.
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
        // Common port env vars
        case envPORT = "PORT"
        case envGPTZeroPort = "GPTZERO_CUSTOM_PORT"
    }

    init(from decoder: Decoder) throws {
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

        // Extract port: first try args (--port N, -p N), then common env vars
        let args = try env.decodeIfPresent([String].self, forKey: .args) ?? []
        let argsJoined = args.joined(separator: " ")
        let portPattern = try? NSRegularExpression(pattern: #"(?:--port|-p)\s+(\d+)"#)
        if let match = portPattern?.firstMatch(in: argsJoined, range: NSRange(argsJoined.startIndex..., in: argsJoined)),
           let range = Range(match.range(at: 1), in: argsJoined),
           let parsed = Int(argsJoined[range]) {
            port = parsed
        } else if let envPort = try env.decodeIfPresent(StringOrInt.self, forKey: .envGPTZeroPort) {
            port = envPort.intValue
        } else if let envPort = try env.decodeIfPresent(StringOrInt.self, forKey: .envPORT) {
            port = envPort.intValue
        } else {
            port = nil
        }
    }
}
