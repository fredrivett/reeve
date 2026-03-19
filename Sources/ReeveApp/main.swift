import SwiftUI
import AppKit
import ReeveLib

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
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

        Settings {
            SettingsView()
                .environmentObject(configService)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
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
        NSApplication.shared.setActivationPolicy(.accessory)
        // Hide the hidden window immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows where window.title == "Hidden" {
                window.orderOut(nil)
            }
        }
    }
}
