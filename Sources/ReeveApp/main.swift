import SwiftUI
import AppKit
import ReeveLib

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
}

/// Launch-time options parsed from process arguments.
enum LaunchOptions {
    /// Mount the panel in a standalone, persistent window (instead of only the
    /// menu bar popover) — handy for recording demos. Pair with `--demo`.
    static let standaloneWindow = ProcessInfo.processInfo.arguments.contains("--window")
}

@main
struct ReeveApp: App {
    @StateObject private var pm2Service = PM2Service()
    @StateObject private var configService = ConfigService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden window provides SwiftUI context for openSettings
        Window("Hidden", id: "HiddenWindow") {
            SettingsOpenerView()
                .modifier(StandaloneWindowOpener())
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        MenuBarExtra {
            ContentView()
                .environmentObject(pm2Service)
                .environmentObject(configService)
                .onAppear {
                    // Start polling on first popover open if not already started
                    if !pm2Service.isPolling {
                        pm2Service.startPolling(interval: configService.config.pollIntervalSeconds)
                    }
                }
        } label: {
            let count = pm2Service.totalOnlineCount
            HStack(spacing: 4) {
                Image(systemName: "person.and.background.striped.horizontal")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .primary)
                    .font(.system(size: 22))
                if configService.config.showMenuBarCount {
                    Text(pm2Service.hasCompletedFirstScan ? "\(count)" : "\u{2014}")
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Always-present window; only rendered for real in `--window` mode (a
        // SceneBuilder can't take a runtime `if`, so the toggle lives in the
        // View content and the window is hidden otherwise — see AppDelegate).
        Window("reeve", id: "ReevePanel") {
            if LaunchOptions.standaloneWindow {
                StandalonePanelView()
                    .environmentObject(pm2Service)
                    .environmentObject(configService)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(configService)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}

/// Opens the standalone panel window at launch in `--window` mode (secondary
/// `Window` scenes don't auto-open, so we trigger it explicitly).
private struct StandaloneWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            if LaunchOptions.standaloneWindow {
                openWindow(id: "ReevePanel")
            }
        }
    }
}

/// Hosts the panel in a standalone window for demo recording, mirroring the
/// menu bar popover's content and polling startup.
private struct StandalonePanelView: View {
    @EnvironmentObject var pm2Service: PM2Service
    @EnvironmentObject var configService: ConfigService

    var body: some View {
        ContentView()
            .fixedSize()
            .onAppear {
                if !pm2Service.isPolling {
                    pm2Service.startPolling(interval: configService.config.pollIntervalSeconds)
                }
            }
    }
}

/// Invisible view that listens for settings open requests and uses the openSettings environment action.
@available(macOS 14.0, *)
private struct SettingsOpenerView14: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    try? await Task.sleep(for: .milliseconds(100))
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    try? await Task.sleep(for: .milliseconds(200))
                    if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || $0.title.localizedCaseInsensitiveContains("settings") }) {
                        w.makeKeyAndOrderFront(nil)
                        w.orderFrontRegardless()
                    }
                }
            }
    }
}

private struct SettingsOpenerView13: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    try? await Task.sleep(for: .milliseconds(100))
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    try? await Task.sleep(for: .milliseconds(200))
                    if let w = NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("settings") || $0.title.localizedCaseInsensitiveContains("preferences") }) {
                        w.makeKeyAndOrderFront(nil)
                        w.orderFrontRegardless()
                    }
                }
            }
    }
}

private struct SettingsOpenerView: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsOpenerView14()
        } else {
            SettingsOpenerView13()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // In standalone-window mode run as a regular app so the window is
        // focusable and clickable; otherwise stay a menu-bar-only accessory.
        NSApplication.shared.setActivationPolicy(LaunchOptions.standaloneWindow ? .regular : .accessory)
        // Hide the hidden window immediately. In standalone-window mode bring the
        // panel to the front (an accessory app won't surface it on its own);
        // otherwise hide that window too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows where window.title == "Hidden" {
                window.orderOut(nil)
            }
            if LaunchOptions.standaloneWindow {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "reeve" {
                    // Strip all window chrome for a clean, popover-like panel.
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.isMovableByWindowBackground = true
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            } else {
                for window in NSApp.windows where window.title == "reeve" {
                    window.orderOut(nil)
                }
            }
        }

        // Intercept ⌘, so it goes through the same bring-to-front flow as clicking "Settings..."
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                return nil // swallow the event
            }
            return event
        }
    }
}
