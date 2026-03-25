import Foundation

/// Executes git commands as child processes and returns their output.
/// All methods are async and non-blocking.
final class GitService {

    // MARK: - Result

    struct CommandResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    // MARK: - Public API

    /// Run any git command in the given directory.
    /// Example: run(["status", "--porcelain=v2"], in: "/Users/me/project")
    func run(_ args: [String], in directory: String) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.execute(args, directory: directory)
                continuation.resume(returning: result)
            }
        }
    }

    /// Detect the git repository root for a given path.
    /// Returns nil if the path is not inside a git repo.
    func repoRoot(for path: String) async -> String? {
        let result = await run(["rev-parse", "--show-toplevel"], in: path)
        guard result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if the given directory is inside a git repository.
    func isGitRepo(_ path: String) async -> Bool {
        await repoRoot(for: path) != nil
    }

    // MARK: - Private

    private func execute(_ args: [String], directory: String) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        // Inherit a clean environment with PATH so git can find helpers
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"   // never prompt for credentials
        env["LANG"] = "en_US.UTF-8"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        return CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
