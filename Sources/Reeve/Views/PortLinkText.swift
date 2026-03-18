import SwiftUI

struct PortLinkText: View {
    let text: String
    let port: Int?

    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(port != nil ? Color.accentColor : .secondary)
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
