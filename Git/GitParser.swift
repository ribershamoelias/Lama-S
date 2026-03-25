import Foundation

/// Parses raw git CLI output into structured domain models.
struct GitParser {

    // MARK: - Status (porcelain v2)

    /// Parse `git status --porcelain=v2 --branch` output into file changes and branch info.
    static func parseStatus(_ raw: String) -> (branch: BranchInfo, changes: [FileChange]) {
        var staged: [FileChange] = []
        var unstaged: [FileChange] = []
        var untracked: [FileChange] = []

        var branchName = "unknown"
        var upstream: String? = nil
        var ahead = 0
        var behind = 0
        var isDetached = false

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("# branch.head") {
                let val = line.components(separatedBy: " ").last ?? ""
                if val == "(detached)" { isDetached = true } else { branchName = val }

            } else if line.hasPrefix("# branch.upstream") {
                upstream = line.components(separatedBy: " ").last

            } else if line.hasPrefix("# branch.ab") {
                // Format: # branch.ab +2 -1
                let parts = line.components(separatedBy: " ")
                for part in parts {
                    if part.hasPrefix("+"), let n = Int(part.dropFirst()) { ahead = n }
                    if part.hasPrefix("-"), let n = Int(part.dropFirst()) { behind = n }
                }

            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                // Ordinary / renamed changed entry
                // Format: 1 XY sub mH mI mW hH hI path
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]   // two-char status code: index + worktree
                let path = parts[8]

                let indexChar  = String(xy.prefix(1))
                let worktreeChar = String(xy.suffix(1))

                if indexChar != "." && indexChar != "?" {
                    if let s = FileChange.ChangeStatus(rawValue: indexChar) {
                        staged.append(FileChange(path: path, status: s, area: .staged))
                    }
                }
                if worktreeChar != "." && worktreeChar != "?" {
                    let s: FileChange.ChangeStatus = worktreeChar == "U" ? .conflicted
                        : FileChange.ChangeStatus(rawValue: worktreeChar) ?? .modified
                    unstaged.append(FileChange(path: path, status: s, area: .unstaged))
                }

            } else if line.hasPrefix("? ") {
                // Untracked file
                let path = String(line.dropFirst(2))
                untracked.append(FileChange(path: path, status: .untracked, area: .untracked))

            } else if line.hasPrefix("u ") {
                // Unmerged (conflict) entry
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 11 else { continue }
                let path = parts[10]
                staged.append(FileChange(path: path, status: .conflicted, area: .staged))
            }
        }

        let branch = BranchInfo(name: branchName, isDetached: isDetached,
                                ahead: ahead, behind: behind, upstream: upstream)
        return (branch, staged + unstaged + untracked)
    }

    // MARK: - Diff stat

    /// Parse `git diff --stat` or `git diff --cached --stat` into a readable summary.
    static func parseDiffStat(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Log

    struct LogEntry: Identifiable {
        let id: String   // commit hash
        let shortHash: String
        let author: String
        let date: String
        let message: String
    }

    /// Parse `git log --pretty=format:"%H|%h|%an|%ar|%s"` output.
    static func parseLog(_ raw: String) -> [LogEntry] {
        raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> LogEntry? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 5 else { return nil }
                return LogEntry(id: parts[0], shortHash: parts[1],
                                author: parts[2], date: parts[3],
                                message: parts[4...].joined(separator: "|"))
            }
    }

    // MARK: - Branch list

    struct BranchEntry: Identifiable {
        let id = UUID()
        let name: String
        let isCurrent: Bool
        let isRemote: Bool
    }

    /// Parse `git branch -a --format=%(refname:short)|%(HEAD)` output.
    static func parseBranches(_ raw: String) -> [BranchEntry] {
        raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { line -> BranchEntry in
                let parts = line.components(separatedBy: "|")
                let name = parts.first ?? line
                let isCurrent = parts.count > 1 && parts[1] == "*"
                let isRemote = name.hasPrefix("origin/") || name.hasPrefix("remotes/")
                return BranchEntry(name: name, isCurrent: isCurrent, isRemote: isRemote)
            }
    }
}
