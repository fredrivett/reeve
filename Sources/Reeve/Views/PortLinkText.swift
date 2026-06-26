import SwiftUI

struct PortLinkText: View {
    let text: String
    let port: Int?

    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(port != nil ? Color(.linkColor) : .secondary)
            .underline(isHovered && port != nil)
            .onHover { hovering in
                isHovered = hovering
                if hovering && port != nil { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                if let port, let url = URL(string: "http://localhost:\(port)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .help(port.map { "Open http://localhost:\(String($0))" } ?? "")
    }
}

/// Pure layout decision for how a process's ports are displayed, extracted from
/// the view so it can be unit-tested.
enum PortDisplay {
    struct Summary: Equatable {
        /// Ports rendered inline as links (at most `limit`).
        let shown: [Int]
        /// How many ports are hidden behind the `+N` badge.
        let overflow: Int
        /// Tooltip listing every port (shown + hidden).
        let tooltip: String
    }

    static func summarize(_ ports: [Int], limit: Int = 2) -> Summary {
        Summary(
            shown: Array(ports.prefix(limit)),
            overflow: Swift.max(0, ports.count - limit),
            tooltip: ports.map { ":\($0)" }.joined(separator: " ")
        )
    }
}

/// Displays the ports a process is listening on: up to two as clickable links,
/// collapsing any extras into a `+N` badge whose tooltip lists every port.
/// Renders nothing when the process has no listening ports.
struct ProcessPortsView: View {
    let ports: [Int]

    private var summary: PortDisplay.Summary { PortDisplay.summarize(ports) }

    var body: some View {
        if !ports.isEmpty {
            HStack(spacing: 4) {
                ForEach(summary.shown, id: \.self) { port in
                    PortLinkText(text: ":\(String(port))", port: port)
                }
                if summary.overflow > 0 {
                    Text("+\(summary.overflow)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .hoverTooltip(summary.tooltip)
                }
            }
        }
    }
}
