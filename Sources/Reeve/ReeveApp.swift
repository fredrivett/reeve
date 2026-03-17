import SwiftUI
import AppKit

@main
struct ReeveApp: App {
    @StateObject private var pm2Service = PM2Service()
    @StateObject private var configService = ConfigService()

    init() {
        // Hide dock icon (equivalent to LSUIElement = YES in Info.plist)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(pm2Service)
                .environmentObject(configService)
        } label: {
            let count = pm2Service.totalOnlineCount
            Label(count > 0 ? "\(count)" : "–", systemImage: "cpu")
        }
        .menuBarExtraStyle(.window)
    }
}
