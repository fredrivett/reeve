import AppKit
import SwiftUI

/// Ensures the hosting window stays fully visible on screen.
/// Works around a macOS bug where MenuBarExtra windows drift off-screen
/// when the menu bar auto-hides in fullscreen mode.
private final class WindowClampView: NSView {
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var isAdjusting = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window = window else { return }

        clampToScreen(window)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self = self, let window = window, !self.isAdjusting else { return }
            self.isAdjusting = true
            self.clampToScreen(window)
            self.isAdjusting = false
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            self.isAdjusting = true
            self.clampToScreen(window)
            self.isAdjusting = false
        }
    }

    private func clampToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var frame = window.frame

        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.origin.y < visibleFrame.origin.y {
            frame.origin.y = visibleFrame.origin.y
        }
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

    private func removeObservers() {
        if let moveObserver = moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let screenObserver = screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    deinit {
        removeObservers()
    }
}

private struct WindowClampRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowClampView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func clampToScreen() -> some View {
        background(WindowClampRepresentable())
    }
}
