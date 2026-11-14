import Foundation

/// The worst state across every PM2 environment, shown by the lantern in the
/// menu bar icon.
public enum ProcessHealth: Sendable {
    /// The first scan hasn't finished.
    case scanning
    /// Everything is online or deliberately stopped.
    case healthy
    /// A process is crash-looping, launching or stopping.
    case warning
    /// A process has errored or a PM2 daemon isn't responding.
    case failing

    public init(processes: [PM2Process], hasDaemonErrors: Bool) {
        if hasDaemonErrors || processes.contains(where: \.isErrored) {
            self = .failing
        } else if processes.contains(where: { $0.isCrashLooping || ["launching", "stopping"].contains($0.status) }) {
            self = .warning
        } else {
            self = .healthy
        }
    }
}
