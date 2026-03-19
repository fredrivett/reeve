import Foundation

public struct AppConfig: Codable {
    public var panelWidth: Double = 600
    public var pollIntervalSeconds: Double = 3.0
    public var collapsedEnvironments: Set<String> = []
    public var hiddenEnvironments: Set<String> = []
    public var showRepoName: Bool = true
    public var showWorkspaceName: Bool = true
    public var stripBranchPrefix: Bool = true
    public var stripTicketPrefix: Bool = true
    public var showMenuBarCount: Bool = true

    // Not persisted — inactive environments always start collapsed
    public var expandedInactiveEnvironments: Set<String> = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case panelWidth, pollIntervalSeconds, collapsedEnvironments, hiddenEnvironments, showRepoName, showWorkspaceName, stripBranchPrefix, stripTicketPrefix, showMenuBarCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 600
        pollIntervalSeconds = try container.decode(Double.self, forKey: .pollIntervalSeconds)
        collapsedEnvironments = try container.decode(Set<String>.self, forKey: .collapsedEnvironments)
        hiddenEnvironments = try container.decode(Set<String>.self, forKey: .hiddenEnvironments)
        showRepoName = try container.decodeIfPresent(Bool.self, forKey: .showRepoName) ?? true
        showWorkspaceName = try container.decodeIfPresent(Bool.self, forKey: .showWorkspaceName) ?? true
        stripBranchPrefix = try container.decodeIfPresent(Bool.self, forKey: .stripBranchPrefix) ?? true
        stripTicketPrefix = try container.decodeIfPresent(Bool.self, forKey: .stripTicketPrefix) ?? true
        showMenuBarCount = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarCount) ?? true
    }
}
