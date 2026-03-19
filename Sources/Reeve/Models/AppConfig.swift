import Foundation

public struct AppConfig: Codable {
    public var pollIntervalSeconds: Double = 3.0
    public var collapsedEnvironments: Set<String> = []
    public var hiddenEnvironments: Set<String> = []
    public var showRepoName: Bool = true
    public var showWorkspaceName: Bool = true
    public var stripBranchPrefix: Bool = true
    public var stripTicketPrefix: Bool = true

    // Not persisted — inactive environments always start collapsed
    public var expandedInactiveEnvironments: Set<String> = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds, collapsedEnvironments, hiddenEnvironments, showRepoName, showWorkspaceName, stripBranchPrefix, stripTicketPrefix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalSeconds = try container.decode(Double.self, forKey: .pollIntervalSeconds)
        collapsedEnvironments = try container.decode(Set<String>.self, forKey: .collapsedEnvironments)
        hiddenEnvironments = try container.decode(Set<String>.self, forKey: .hiddenEnvironments)
        showRepoName = try container.decodeIfPresent(Bool.self, forKey: .showRepoName) ?? true
        showWorkspaceName = try container.decodeIfPresent(Bool.self, forKey: .showWorkspaceName) ?? true
        stripBranchPrefix = try container.decodeIfPresent(Bool.self, forKey: .stripBranchPrefix) ?? true
        stripTicketPrefix = try container.decodeIfPresent(Bool.self, forKey: .stripTicketPrefix) ?? true
    }
}
