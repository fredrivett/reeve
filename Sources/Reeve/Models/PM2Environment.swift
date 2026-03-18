import Foundation

public struct PM2Environment: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public var isActive: Bool

    public var id: String { path }

    public init(path: String, isActive: Bool = false) {
        self.path = path
        self.isActive = isActive

        let dirName = (path as NSString).lastPathComponent
        if dirName == ".pm2" {
            name = "default"
        } else if dirName.hasPrefix(".pm2-") {
            name = String(dirName.dropFirst(5))
        } else {
            name = dirName
        }
    }
}
