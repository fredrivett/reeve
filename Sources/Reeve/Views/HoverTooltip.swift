import SwiftUI

/// A view modifier that shows a popover tooltip on hover, since `.help()` doesn't work in MenuBarExtra windows.
struct HoverTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .interactiveDismissDisabled()
            }
    }
}

extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltip(text: text))
    }
}
