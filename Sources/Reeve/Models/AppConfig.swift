import Foundation

struct AppConfig: Codable {
    var pollIntervalSeconds: Double = 3.0
    var collapsedEnvironments: Set<String> = []
    var hiddenEnvironments: Set<String> = []
}
