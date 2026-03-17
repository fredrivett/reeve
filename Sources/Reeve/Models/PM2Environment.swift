import Foundation

struct PM2Environment: Identifiable, Hashable {
    let path: String
    let name: String
    var isActive: Bool

    var id: String { path }

    init(path: String, isActive: Bool = false) {
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
