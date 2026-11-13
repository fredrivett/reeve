import AppKit
import SwiftUI

/// Where a menu bar panel's window should sit so it wraps its content exactly.
enum WindowFit {
    /// The frame for a window of `size` that keeps `current`'s top edge, so the
    /// panel stays pinned under its menu bar icon as it grows or shrinks. The
    /// top and sides are kept inside `visibleFrame`; a panel taller than the
    /// screen runs off the bottom rather than hiding its header.
    static func frame(current: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let top = min(current.maxY, visibleFrame.maxY)
        let x = max(min(current.minX, visibleFrame.maxX - size.width), visibleFrame.minX)
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

/// Sizes its window to `contentSize` and keeps it on screen.
///
/// `MenuBarExtra` (`.window` style) resizes its window when SwiftUI reports a
/// new root size. If it misses that update, nothing shrinks the window again:
/// its only fallback clamps the window between the content's min and max sizes,
/// and only on a later window layout pass. The window then keeps its old
/// height with the content centred inside it. It also lets the window grow up
/// past the menu bar, and drift off screen when the menu bar auto-hides in
/// fullscreen. So reeve sets the frame itself whenever the content's size, the
/// window's frame or the screen changes.
private final class WindowFitView: NSView {
    var contentSize: CGSize = .zero {
        didSet { if contentSize != oldValue { fit() } }
    }

    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }

        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                self?.fit()
            },
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.fit()
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.fit()
            }
        ]
        fit()
    }

    /// Idempotent: the move and resize notifications its own `setFrame` posts
    /// find the window already fitted.
    private func fit() {
        guard let window, contentSize.height > 0, let screen = window.screen ?? NSScreen.main else { return }
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let frame = WindowFit.frame(current: window.frame, size: size, visibleFrame: screen.visibleFrame)
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

private struct WindowFitRepresentable: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> WindowFitView {
        WindowFitView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowFitView, context: Context) {
        nsView.contentSize = contentSize
    }
}

private struct WindowFitModifier: ViewModifier {
    @State private var contentSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { contentSize = $0 }
            .background(WindowFitRepresentable(contentSize: contentSize))
    }
}

extension View {
    /// Keeps the hosting `MenuBarExtra` window exactly this view's size,
    /// pinned under the menu bar and on screen. Apply to the window's root
    /// view, and only where that view's size is the window's size: in a window
    /// with a title bar, the bar's safe area makes the window taller.
    public func fitWindowToContent() -> some View {
        modifier(WindowFitModifier())
    }
}
