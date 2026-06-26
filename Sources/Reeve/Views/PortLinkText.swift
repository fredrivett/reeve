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

/// Displays the ports a process is listening on: up to two as clickable links,
/// collapsing any extras into a `+N` badge whose tooltip lists every port.
/// Renders nothing when the process has no listening ports.
struct ProcessPortsView: View {
    let ports: [Int]
    private let maxShown = 2

    var body: some View {
        if !ports.isEmpty {
            HStack(spacing: 4) {
                ForEach(ports.prefix(maxShown), id: \.self) { port in
                    PortLinkText(text: ":\(String(port))", port: port)
                }
                if ports.count > maxShown {
                    Text("+\(ports.count - maxShown)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .hoverTooltip(ports.map { ":\($0)" }.joined(separator: " "))
                }
            }
        }
    }
}
