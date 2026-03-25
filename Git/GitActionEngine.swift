import Foundation

/// Executes git actions on behalf of the user.
/// All actions refresh RepoStateManager on completion.
/// NEVER auto-executes — always called from explicit user interaction.
@MainActor
final class GitActionEngine {

    private let git = GitService()
    private let repoManager: RepoStateManager

    init(repoManager: RepoStateManager) {
        self.repoManager = repoManager
    }

    private var root: String { repoManager.state.repoRoot }

    // MARK: - Staging

    func stage(_ file: FileChange) async {
        _ = await git.run(["add", "--", file.path], in: root)
        repoManager.refresh()
    }

    func stageAll() async {
        _ = await git.run(["add", "-A"], in: root)
        repoManager.refresh()
    }

    func unstage(_ file: FileChange) async {
        _ = await git.run(["restore", "--staged", "--", file.path], in: root)
        repoManager.refresh()
    }

    func unstageAll() async {
        _ = await git.run(["restore", "--staged", "."], in: root)
        repoManager.refresh()
    }

    // MARK: - Discard (destructive — caller must confirm)

    func discardChanges(in file: FileChange) async {
        _ = await git.run(["restore", "--", file.path], in: root)
        repoManager.refresh()
    }

    func deleteUntracked(_ file: FileChange) async {
        let fullPath = root + "/" + file.path
        try? FileManager.default.removeItem(atPath: fullPath)
        repoManager.refresh()
    }

    // MARK: - Commit

    /// Commit staged changes with the given message.
    @discardableResult
    func commit(message: String) async -> Bool {
        let result = await git.run(["commit", "-m", message], in: root)
        repoManager.refresh()
        return result.succeeded
    }

    // MARK: - Branch

    func switchBranch(_ name: String) async -> Bool {
        let result = await git.run(["checkout", name], in: root)
        repoManager.refresh()
        return result.succeeded
    }

    func createBranch(_ name: String, checkout: Bool = true) async -> Bool {
        let args = checkout ? ["checkout", "-b", name] : ["branch", name]
        let result = await git.run(args, in: root)
        repoManager.refresh()
        return result.succeeded
    }

    func deleteBranch(_ name: String, force: Bool = false) async -> Bool {
        let flag = force ? "-D" : "-d"
        let result = await git.run(["branch", flag, name], in: root)
        repoManager.refresh()
        return result.succeeded
    }

    // MARK: - Push with upstream fallback

    func pushWithUpstream() async -> GitService.CommandResult {
        let result = await git.run(["push"], in: root)
        if result.succeeded { return result }

        if result.stderr.contains("no upstream") || result.stderr.contains("--set-upstream") {
            let branchResult = await git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
            let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return await git.run(["push", "--set-upstream", "origin", branch], in: root)
        }
        return result
    }

    // MARK: - Remote

    func pull() async -> GitService.CommandResult {
        let result = await git.run(["pull"], in: root)
        repoManager.refresh()
        return result
    }

    func push(force: Bool = false) async -> GitService.CommandResult {
        var args = ["push"]
        if force { args.append("--force") }
        let result = await git.run(args, in: root)
        repoManager.refresh()
        return result
    }
}
