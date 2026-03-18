import SwiftUI
import AppKit
import ReeveLib

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
            HStack(spacing: 4) {
                Image(systemName: "person.and.background.striped.horizontal")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .primary)
                    .font(.system(size: 22))
                Text(pm2Service.hasCompletedFirstScan ? "\(count)" : "\u{2014}")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
