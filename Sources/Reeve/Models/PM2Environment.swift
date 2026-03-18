import Foundation

public struct GitInfo: Hashable, Sendable {
    public let repoName: String
    public let branch: String

    /// Format the branch name for display, applying optional stripping rules.
    public func displayBranch(stripPrefix: Bool, stripTicket: Bool) -> String {
        var result = branch
        // Strip everything before and including the last slash: "fredrivett/my-branch" → "my-branch"
        if stripPrefix, let slashIndex = result.lastIndex(of: "/") {
            result = String(result[result.index(after: slashIndex)...])
        }
        // Strip ticket prefix like "eng-1234-": "eng-3338-next-button-fix" → "next-button-fix"
        if stripTicket {
            result = result.replacingOccurrences(
                of: #"^.*?eng-\d+-"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }
}

public struct PM2Environment: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public var isActive: Bool
    public var gitInfo: GitInfo?

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

    /// Resolve git info from a process cwd. Call after processes are fetched.
    public static func resolveGitInfo(from cwd: String) -> GitInfo? {
        guard !cwd.isEmpty else { return nil }

        guard let repoRoot = runGit(["-C", cwd, "rev-parse", "--show-toplevel"]),
              let branch = runGit(["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]) else {
            return nil
        }

        let repoName = (repoRoot as NSString).lastPathComponent
        return GitInfo(repoName: repoName, branch: branch)
    }

    private static func runGit(_ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
