import SwiftUI
import AppKit

@main
struct ReeveApp: App {
    @StateObject private var pm2Service = PM2Service()
    @StateObject private var configService = ConfigService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
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
            Label(count > 0 ? "\(count)" : "–", systemImage: "cpu")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
