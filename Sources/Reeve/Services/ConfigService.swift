import Foundation
import Combine

class ConfigService: ObservableObject {
    @Published var config: AppConfig

    private let configURL: URL

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/reeve", isDirectory: true)
        configURL = configDir.appendingPathComponent("config.json")

        // Load existing config or use defaults
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        } else {
            config = AppConfig()
        }
    }

    func save() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    func toggleCollapsed(_ environmentPath: String) {
        if config.collapsedEnvironments.contains(environmentPath) {
            config.collapsedEnvironments.remove(environmentPath)
        } else {
            config.collapsedEnvironments.insert(environmentPath)
        }
        save()
    }

    func isCollapsed(_ environmentPath: String) -> Bool {
        config.collapsedEnvironments.contains(environmentPath)
    }
}
