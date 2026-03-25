import Foundation

// MARK: - File Change

/// Represents a single changed file in the working tree or index.
struct FileChange: Identifiable, Equatable {
    let id = UUID()
    let path: String           // relative path from repo root
    let status: ChangeStatus
    let area: ChangeArea

    var name: String { (path as NSString).lastPathComponent }
    var fullPath: String = ""  // set by RepoStateManager once repoRoot is known

    enum ChangeStatus: String, Equatable {
        case modified   = "M"
        case added      = "A"
        case deleted    = "D"
        case renamed    = "R"
        case copied     = "C"
        case untracked  = "?"
        case conflicted = "U"

        var icon: String {
            switch self {
            case .modified:   return "pencil.circle.fill"
            case .added:      return "plus.circle.fill"
            case .deleted:    return "minus.circle.fill"
            case .renamed:    return "arrow.triangle.2.circlepath.circle.fill"
            case .copied:     return "doc.on.doc.fill"
            case .untracked:  return "questionmark.circle.fill"
            case .conflicted: return "exclamationmark.triangle.fill"
            }
        }

        var label: String {
            switch self {
            case .modified:   return "Modified"
            case .added:      return "Added"
            case .deleted:    return "Deleted"
            case .renamed:    return "Renamed"
            case .copied:     return "Copied"
            case .untracked:  return "Untracked"
            case .conflicted: return "Conflict"
            }
        }
    }

    enum ChangeArea: Equatable {
        case staged
        case unstaged
        case untracked
    }
}

// MARK: - Branch Info

struct BranchInfo: Equatable {
    let name: String
    let isDetached: Bool
    let ahead: Int    // commits ahead of remote
    let behind: Int   // commits behind remote
    let upstream: String?

    static let unknown = BranchInfo(name: "unknown", isDetached: false,
                                    ahead: 0, behind: 0, upstream: nil)
}

// MARK: - Repo State

/// Complete snapshot of the repository at a point in time.
struct RepoState: Equatable {
    var branch: BranchInfo = .unknown
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
    var untracked: [FileChange] = []
    var isInMerge: Bool = false
    var isInRebase: Bool = false
    var isDetachedHEAD: Bool = false
    var repoRoot: String = ""

    var hasConflicts: Bool {
        staged.contains { $0.status == .conflicted } ||
        unstaged.contains { $0.status == .conflicted }
    }

    var isEmpty: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty
    }

    /// Human-readable workflow hint based on current state.
    var workflowHint: String? {
        if isInMerge    { return "You are in the middle of a merge. Resolve conflicts then run git commit." }
        if isInRebase   { return "Rebase in progress. Fix conflicts then run git rebase --continue." }
        if isDetachedHEAD { return "Detached HEAD — you are not on any branch. Create a branch to save work." }
        if !staged.isEmpty && branch.name != "unknown" {
            return "You have staged changes ready to commit."
        }
        if !unstaged.isEmpty {
            return "You have unstaged changes. Stage them with git add."
        }
        if branch.behind > 0 {
            return "Your branch is \(branch.behind) commit(s) behind origin. Consider pulling."
        }
        if branch.ahead > 0 {
            return "You have \(branch.ahead) unpushed commit(s). Push when ready."
        }
        return nil
    }
}

// MARK: - Commit Suggestion

struct CommitSuggestion {
    let short: String          // e.g. "fix: resolve login crash"
    let conventional: String   // e.g. "fix(auth): resolve null pointer in login flow"
    let body: String?          // optional longer description
}
