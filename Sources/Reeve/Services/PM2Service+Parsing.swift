import Foundation

// Pure, off-actor parsing helpers for pm2 output and log files. Kept out of
// `PM2Service` itself so the service file stays focused on state and control.
extension PM2Service {
    /// Extract the JSON payload from raw pm2 stdout.
    ///
    /// pm2 prepends human-readable notices to stdout — most notably a colored
    /// "In-memory PM2 is out-of-date" banner when a daemon's in-memory version
    /// differs from the local CLI. That preamble makes the buffer invalid JSON
    /// and breaks decoding, so we trim to the first JSON bracket before handing
    /// it to `JSONDecoder`. The banner is ANSI-colored, so its own '[' bytes are
    /// preceded by the ESC (0x1B) byte of a CSI escape — we skip those and stop
    /// at the first real JSON bracket. Returns the input unchanged if none is
    /// found, so decode errors stay meaningful.
    nonisolated static func extractJSON(from data: Data) -> Data {
        let esc: UInt8 = 0x1B          // ESC — starts an ANSI escape sequence
        let openBracket: UInt8 = 0x5B  // [
        let openBrace: UInt8 = 0x7B    // {
        let bytes = [UInt8](data)
        for i in bytes.indices where bytes[i] == openBracket || bytes[i] == openBrace {
            // A '[' immediately after ESC belongs to an ANSI color code, not JSON.
            if bytes[i] == openBracket && i > 0 && bytes[i - 1] == esc { continue }
            return Data(bytes[i...])
        }
        return data
    }

    /// Whether `text` (a chunk of an error log) reports a port bind failure.
    /// Covers the common phrasings across Node (EADDRINUSE), Python/errno
    /// (Errno 48), and the shared "address already in use" message.
    nonisolated static func logReportsAddressInUse(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("address already in use")
            || lower.contains("eaddrinuse")
            || lower.contains("errno 48")
    }

    /// Read the tail of an error-log file and check for a bind-conflict message.
    /// Only the last few KB are read, so this stays cheap on the poll loop.
    nonisolated static func errorLogReportsAddressInUse(atPath path: String) -> Bool {
        guard !path.isEmpty, let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let tailBytes: UInt64 = 8192
        if let size = try? handle.seekToEnd(), size > tailBytes {
            try? handle.seek(toOffset: size - tailBytes)
        } else {
            try? handle.seek(toOffset: 0)
        }
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return logReportsAddressInUse(text)
    }
}
