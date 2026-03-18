import SwiftUI

struct LogPanelView: View {
    let process: PM2Process
    let environment: PM2Environment
    @EnvironmentObject var pm2Service: PM2Service

    @State private var logLines: [String] = []
    @State private var streamProcess: Foundation.Process?
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            colorizedLogLine(line)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: logLines.count) { _ in
                    if let last = logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logLines.joined(separator: "\n"), forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copied = false
                }
            } label: {
                HStack(spacing: 3) {
                    if copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Text(copied ? "Copied" : "Copy logs")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .padding(6)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .frame(height: 150)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .onAppear { startStreaming() }
        .onDisappear { stopStreaming() }
    }

    private func startStreaming() {
        streamProcess = pm2Service.startLogStream(
            process: process,
            environment: environment
        ) { text in
            let lines = text.components(separatedBy: .newlines)
                .map { stripAnsiCodes($0) }
                .filter { line in
                    guard !line.isEmpty else { return false }
                    // Filter out lines that are just the PM2 prefix with no content
                    if let range = line.range(of: #"^\d+\|\S+ \| "#, options: .regularExpression) {
                        return !line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    return true
                }
            DispatchQueue.main.async {
                logLines.append(contentsOf: lines)
                // Cap buffer at 500 lines
                if logLines.count > 500 {
                    logLines.removeFirst(logLines.count - 500)
                }
            }
        }
    }

    private func colorizedLogLine(_ line: String) -> Text {
        // Strip the PM2 prefix (e.g. "3|node_ser | ") to get the actual log content
        let content: String
        if let range = line.range(of: #"^\d+\|\S+ \| "#, options: .regularExpression) {
            content = String(line[range.upperBound...])
        } else {
            content = line
        }
        let lower = content.lowercased()

        // PM2 system lines (TAILING, log paths)
        if lower.contains("[tailing]") || lower.contains("last 50 lines") || lower.contains("last 100 lines")
            || line.hasSuffix("-error.log last 50 lines:") || line.hasSuffix("-out.log last 50 lines:") {
            return Text(line).foregroundColor(.secondary.opacity(0.5))
        }

        // Error lines — match word boundaries, not substrings in paths
        if lower.range(of: #"\berror\b|\bexception\b|\bfatal\b|\bfailed\b|\benoent\b|\bstack trace\b"#, options: .regularExpression) != nil {
            return Text(line).foregroundColor(.red.opacity(0.8))
        }

        // Warning lines
        if lower.range(of: #"\bwarn\b|\bwarning\b|\bdeprecated\b|\bdeprecation\b"#, options: .regularExpression) != nil {
            return Text(line).foregroundColor(.orange.opacity(0.8))
        }

        // Default
        return Text(line).foregroundColor(.secondary)
    }

    private func stopStreaming() {
        pm2Service.stopLogStream(streamProcess)
        streamProcess = nil
    }
}

public func stripAnsiCodes(_ string: String) -> String {
    string.replacingOccurrences(
        of: "\\x1B\\[[0-9;]*[a-zA-Z]|\\x1B\\([a-zA-Z]",
        with: "",
        options: .regularExpression
    )
}

/// Returns true if the log line should be displayed (not an empty PM2 prefix line).
public func shouldDisplayLogLine(_ line: String) -> Bool {
    guard !line.isEmpty else { return false }
    if let range = line.range(of: #"^\d+\|\S+ \| "#, options: .regularExpression) {
        return !line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
    }
    return true
}
