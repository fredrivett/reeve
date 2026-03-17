import Foundation

struct EnvironmentScanner {
    func scan() -> [PM2Environment] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: home) else {
            return []
        }

        return contents
            .filter { $0 == ".pm2" || $0.hasPrefix(".pm2-") }
            .sorted()
            .map { dirName in
                let fullPath = (home as NSString).appendingPathComponent(dirName)
                let isActive = isDaemonAlive(at: fullPath)
                return PM2Environment(path: fullPath, isActive: isActive)
            }
    }

    private func isDaemonAlive(at pm2Home: String) -> Bool {
        let pidPath = (pm2Home as NSString).appendingPathComponent("pm2.pid")
        guard let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8) else {
            return false
        }
        guard let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        // kill with signal 0 checks if process exists without sending a signal
        return kill(pid, 0) == 0
    }
}
