import AppKit
import SwiftUI

/// Ensures the hosting window stays fully visible on screen.
/// Works around a macOS bug where MenuBarExtra windows drift off-screen
/// when the menu bar auto-hides in fullscreen mode.
struct WindowClampModifier: ViewModifier {
    @State private var moveObserver: NSObjectProtocol?
    @State private var screenObserver: NSObjectProtocol?
    @State private var isAdjusting = false

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { window in
                guard let window = window else { return }
                clampToScreen(window)

                moveObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { notification in
                    guard !isAdjusting,
                          let movedWindow = notification.object as? NSWindow else { return }
                    // Debounce to let menu bar hide animation finish
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAdjusting = true
                        clampToScreen(movedWindow)
                        isAdjusting = false
                    }
                }

                screenObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    isAdjusting = true
                    clampToScreen(window)
                    isAdjusting = false
                }
            })
            .onDisappear {
                if let moveObserver = moveObserver {
                    NotificationCenter.default.removeObserver(moveObserver)
                }
                if let screenObserver = screenObserver {
                    NotificationCenter.default.removeObserver(screenObserver)
                }
            }
    }

    private func clampToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var frame = window.frame

        // Clamp vertically: ensure the window doesn't go above the visible area
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.origin.y < visibleFrame.origin.y {
            frame.origin.y = visibleFrame.origin.y
        }

        // Clamp horizontally
        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.origin.x < visibleFrame.origin.x {
            frame.origin.x = visibleFrame.origin.x
        }

        if frame != window.frame {
            window.setFrame(frame, display: false)
        }
    }
}

/// Helper to get the hosting NSWindow from a SwiftUI view.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func clampToScreen() -> some View {
        modifier(WindowClampModifier())
    }
}
