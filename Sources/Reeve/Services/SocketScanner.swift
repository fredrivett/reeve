import Foundation

/// Resolves the TCP ports a process is actually listening on by inspecting the
/// OS, rather than guessing from environment variables or CLI args. This is the
/// ground truth: it reflects what a process bound to regardless of how the port
/// was configured (`PORT`, `--port`, a custom var, or hard-coded), and it
/// correctly attributes ports opened by child processes (e.g. `pm2 start npm --
/// run dev`, where the real server is a grandchild of the pm2-managed pid).
///
/// One `lsof` and one `ps` call snapshot the whole machine per refresh; each
/// process then resolves its ports with a cheap dictionary lookup over its own
/// pid plus descendants.
struct SocketScanner {
    /// Listening ports we treat as noise and never surface. Node's V8 inspector
    /// defaults to 9229 and increments for additional inspectors / cluster
    /// workers, so it shows up alongside the real app port under `--inspect`.
    static let ignoredPorts: Set<Int> = [9229, 9230, 9231]

    /// Immutable snapshot of the machine's listening sockets and process tree.
    struct Snapshot: Sendable {
        /// pid → ports that pid is directly listening on.
        let portsByPID: [Int: Set<Int>]
        /// ppid → its direct child pids.
        let childrenByPID: [Int: [Int]]

        static let empty = Snapshot(portsByPID: [:], childrenByPID: [:])
    }

    /// Take a fresh snapshot of all listening TCP sockets and the process tree.
    static func scan() -> Snapshot {
        let lsofOutput = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"])
        let psOutput = run("/bin/ps", ["-axo", "pid=,ppid="])
        return Snapshot(
            portsByPID: parseLsof(lsofOutput),
            childrenByPID: parsePS(psOutput)
        )
    }

    /// All listening ports for the process tree rooted at `pid` (the process
    /// itself plus every descendant), sorted ascending with noise filtered out.
    static func ports(forRoot pid: Int, in snapshot: Snapshot) -> [Int] {
        guard pid > 0 else { return [] }
        var found = Set<Int>()
        var visited = Set<Int>()
        var stack = [pid]
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            if let direct = snapshot.portsByPID[current] { found.formUnion(direct) }
            if let kids = snapshot.childrenByPID[current] { stack.append(contentsOf: kids) }
        }
        return found.subtracting(ignoredPorts).sorted()
    }

    /// True when any process on the machine is currently listening on `port`.
    /// Used to confirm a bind conflict is live (someone is holding the port)
    /// before surfacing it — so the banner clears itself once the squatter goes.
    static func isPortListening(_ port: Int, in snapshot: Snapshot) -> Bool {
        snapshot.portsByPID.values.contains { $0.contains(port) }
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Parse `lsof -FpnL`-style field output into a pid → listening-ports map.
    /// Output is a stream of records: a `p<pid>` line starts a process, and each
    /// following `n<addr>:<port>` line is one of its listening sockets. IPv4 and
    /// IPv6 bindings of the same port collapse naturally into the Set.
    static func parseLsof(_ output: String) -> [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        var currentPID: Int?
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                currentPID = Int(value)
            case "n":
                guard let pid = currentPID,
                      let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                result[pid, default: []].insert(port)
            default:
                continue
            }
        }
        return result
    }

    /// Parse `ps -axo pid=,ppid=` output (two whitespace-separated columns per
    /// line) into a parent → children map.
    static func parsePS(_ output: String) -> [Int: [Int]] {
        var children: [Int: [Int]] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard cols.count >= 2, let pid = Int(cols[0]), let ppid = Int(cols[1]) else { continue }
            children[ppid, default: []].append(pid)
        }
        return children
    }

    // MARK: - Process execution

    private static func run(_ launchPath: String, _ args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
