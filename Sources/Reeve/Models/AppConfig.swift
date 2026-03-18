import Foundation

struct AppConfig: Codable {
    var pollIntervalSeconds: Double = 3.0
    var collapsedEnvironments: Set<String> = []
    var hiddenEnvironments: Set<String> = []

    // Not persisted — inactive environments always start collapsed
    var expandedInactiveEnvironments: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds, collapsedEnvironments, hiddenEnvironments
    }
}
