import Foundation

/// High-level git workflow automation.
/// Sits above GitService — handles full multi-step flows.
/// All methods return a list of human-readable status lines for terminal display.
@MainActor
final class GitWorkflowEngine {

    private let git = GitService()

    // MARK: - Init + First Commit

    /// git init → git add . → git commit "Initial commit"
    /// Call this right after project structure is created.
    func initProject(in directory: String, projectName: String) async -> [String] {
        var log: [String] = []

        let init_ = await git.run(["init"], in: directory)
        guard init_.succeeded else {
            return ["✗ git init failed: \(init_.stderr.trimmed)"]
        }
        log.append("✓ git init")

        // Configure a local identity if none is set globally (avoids commit failure)
        _ = await git.run(["config", "user.email", "dev@lamaterminal.local"], in: directory)
        _ = await git.run(["config", "user.name", "Lama Terminal"], in: directory)

        let add = await git.run(["add", "-A"], in: directory)
        guard add.succeeded else {
            return log + ["✗ git add failed: \(add.stderr.trimmed)"]
        }
        log.append("✓ git add .")

        let commit = await git.run(["commit", "-m", "Initial commit: \(projectName)"], in: directory)
        if commit.succeeded {
            log.append("✓ git commit \"Initial commit: \(projectName)\"")
        } else {
            log.append("⚠ commit skipped (nothing to commit)")
        }

        return log
    }

    // MARK: - Snapshot (Save Game)

    /// git add . → git commit "Checkpoint: <timestamp>"
    func snapshot(in directory: String) async -> [String] {
        _ = await git.run(["add", "-A"], in: directory)

        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let result = await git.run(["commit", "-m", "Checkpoint \(ts)"], in: directory)

        if result.succeeded {
            return ["✓ Snapshot saved — Checkpoint \(ts)"]
        } else if result.stdout.contains("nothing to commit") || result.stderr.contains("nothing to commit") {
            return ["ℹ Nothing to snapshot — working tree is clean"]
        } else {
            return ["✗ Snapshot failed: \(result.stderr.trimmed)"]
        }
    }

    // MARK: - Auto Commit

    /// git add . → git commit -m <message>
    func autoCommit(in directory: String, message: String) async -> [String] {
        _ = await git.run(["add", "-A"], in: directory)
        let result = await git.run(["commit", "-m", message], in: directory)

        if result.succeeded {
            return ["✓ Committed: \"\(message)\""]
        } else if result.stdout.contains("nothing to commit") || result.stderr.contains("nothing to commit") {
            return ["ℹ Nothing to commit — working tree is clean"]
        } else {
            return ["✗ Commit failed: \(result.stderr.trimmed)"]
        }
    }

    // MARK: - Feature Branch

    /// git checkout -b feature/<name>
    func createFeatureBranch(named name: String, in directory: String) async -> [String] {
        let branch = "feature/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        let result = await git.run(["checkout", "-b", branch], in: directory)

        if result.succeeded {
            return ["✓ Switched to new branch '\(branch)'"]
        } else {
            return ["✗ Branch failed: \(result.stderr.trimmed)"]
        }
    }

    // MARK: - Undo Last Commit (soft — keeps changes staged)

    func undoLastCommit(in directory: String) async -> [String] {
        let result = await git.run(["reset", "--soft", "HEAD~1"], in: directory)
        if result.succeeded {
            return ["✓ Last commit undone — changes are still staged"]
        } else {
            return ["✗ Undo failed: \(result.stderr.trimmed)"]
        }
    }

    // MARK: - Push

    /// Push current branch. If no upstream is set, sets it automatically.
    func push(in directory: String) async -> [String] {
        // Try normal push first
        let result = await git.run(["push"], in: directory)
        if result.succeeded {
            return ["✓ Pushed to remote"]
        }

        // If no upstream, set it
        if result.stderr.contains("no upstream") || result.stderr.contains("--set-upstream") {
            let branchResult = await git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
            let branch = branchResult.stdout.trimmed
            let retry = await git.run(["push", "--set-upstream", "origin", branch], in: directory)
            if retry.succeeded {
                return ["✓ Pushed and set upstream: origin/\(branch)"]
            } else {
                return ["✗ Push failed: \(retry.stderr.trimmed)"]
            }
        }

        return ["✗ Push failed: \(result.stderr.trimmed)"]
    }

    // MARK: - Full Project Workflow
    // Intent → Structure → git init → commit
    // Returns git log lines to display after structure commands run.

    func fullProjectSetup(in directory: String, projectName: String) async -> [String] {
        await initProject(in: directory, projectName: projectName)
    }
}

// MARK: - Helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
