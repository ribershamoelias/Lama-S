import Foundation
import Combine

/// Continuously tracks the state of the git repository in the terminal's
/// current working directory. Refreshes after every git command.
@MainActor
final class RepoStateManager: ObservableObject {

    @Published var state: RepoState = RepoState()
    @Published var isGitRepo: Bool = false
    @Published var isLoading: Bool = false

    private let git = GitService()
    private var currentDirectory: String = NSHomeDirectory()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Public

    /// Call this whenever the terminal's working directory changes.
    func setDirectory(_ path: String) {
        guard path != currentDirectory else { return }
        currentDirectory = path
        refresh()
    }

    /// Call this after any git command is executed in the terminal.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await performRefresh()
        }
    }

    // MARK: - Private

    private func performRefresh() async {
        isLoading = true
        defer { isLoading = false }

        // Check if we're in a git repo
        guard let root = await git.repoRoot(for: currentDirectory) else {
            isGitRepo = false
            state = RepoState()
            return
        }

        isGitRepo = true

        // Run status with branch info
        let statusResult = await git.run(
            ["status", "--porcelain=v2", "--branch"],
            in: root
        )

        var newState = RepoState()
        newState.repoRoot = root

        let (branch, changes) = GitParser.parseStatus(statusResult.stdout)
        newState.branch = branch
        newState.isDetachedHEAD = branch.isDetached

        // Resolve full paths for each change
        newState.staged    = changes.filter { $0.area == .staged }
            .map { fullPath($0, root: root) }
        newState.unstaged  = changes.filter { $0.area == .unstaged }
            .map { fullPath($0, root: root) }
        newState.untracked = changes.filter { $0.area == .untracked }
            .map { fullPath($0, root: root) }

        // Detect merge / rebase state via sentinel files
        let fm = FileManager.default
        newState.isInMerge  = fm.fileExists(atPath: root + "/.git/MERGE_HEAD")
        newState.isInRebase = fm.fileExists(atPath: root + "/.git/rebase-merge") ||
                              fm.fileExists(atPath: root + "/.git/rebase-apply")

        state = newState
    }

    private func fullPath(_ change: FileChange, root: String) -> FileChange {
        var c = change
        c.fullPath = root + "/" + change.path
        return c
    }

    // MARK: - Diff

    /// Returns the diff for a specific file (staged or unstaged).
    func diff(for file: FileChange) async -> String {
        let args: [String] = file.area == .staged
            ? ["diff", "--cached", "--", file.path]
            : ["diff", "--", file.path]
        let result = await git.run(args, in: state.repoRoot)
        return result.stdout
    }

    // MARK: - Log

    func recentLog(limit: Int = 10) async -> [GitParser.LogEntry] {
        let result = await git.run(
            ["log", "--pretty=format:%H|%h|%an|%ar|%s", "-\(limit)"],
            in: state.repoRoot
        )
        return GitParser.parseLog(result.stdout)
    }

    // MARK: - Branches

    func branches() async -> [GitParser.BranchEntry] {
        let result = await git.run(
            ["branch", "-a", "--format=%(refname:short)|%(HEAD)"],
            in: state.repoRoot
        )
        return GitParser.parseBranches(result.stdout)
    }
}
