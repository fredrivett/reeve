import Foundation

public struct AppConfig: Codable {
    public var pollIntervalSeconds: Double = 3.0
    public var collapsedEnvironments: Set<String> = []
    public var hiddenEnvironments: Set<String> = []

    // Not persisted — inactive environments always start collapsed
    public var expandedInactiveEnvironments: Set<String> = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds, collapsedEnvironments, hiddenEnvironments
    }
}
