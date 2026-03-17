import Foundation

actor PM2BinaryResolver {
    private var cachedBinary: String?
    private var cachedPATH: String?

    struct Resolution {
        let binary: String
        let path: String
    }

    enum ResolverError: LocalizedError {
        case notFound

        var errorDescription: String? {
            "Could not find pm2 binary. Make sure pm2 is installed (npm install -g pm2) and your shell profile loads nvm/node."
        }
    }

    func resolve() async throws -> Resolution {
        if let binary = cachedBinary, let path = cachedPATH {
            return Resolution(binary: binary, path: path)
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"

        // Resolve PATH from login shell
        let pathResult = try await runShell(shell, args: ["-l", "-c", "echo $PATH"])
        let resolvedPATH = pathResult.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve pm2 binary location
        let whichResult = try await runShell(shell, args: ["-l", "-c", "which pm2"])
        let binary = whichResult.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !binary.isEmpty, FileManager.default.fileExists(atPath: binary) else {
            throw ResolverError.notFound
        }

        cachedBinary = binary
        cachedPATH = resolvedPATH
        return Resolution(binary: binary, path: resolvedPATH)
    }

    func invalidateCache() {
        cachedBinary = nil
        cachedPATH = nil
    }

    private func runShell(_ shell: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: output)
        }
    }
}
