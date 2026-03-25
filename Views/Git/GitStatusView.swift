import SwiftUI
import AppKit

// MARK: - GitStatusView

/// The main git status panel — shows branch info, file sections, and workflow hints.
struct GitStatusView: View {
    @ObservedObject var repoManager: RepoStateManager
    let actionEngine: GitActionEngine
    let ai: AIService

    @State private var expandedSections: Set<String> = ["staged", "unstaged", "untracked"]
    @State private var diffFile: FileChange? = nil
    @State private var diffContent: String = ""
    @State private var showCommitAssistant = false
    @State private var aiExplanation: String? = nil

    private var state: RepoState { repoManager.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if repoManager.isLoading {
                HStack { ProgressView().scaleEffect(0.6); Text("Refreshing…").font(.caption) }
                    .padding(10)
            } else if state.isEmpty {
                Text("Nothing to commit — working tree clean")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Workflow hint banner
                        if let hint = state.workflowHint {
                            hintBanner(hint)
                        }

                        fileSection(title: "Staged", icon: "checkmark.circle.fill",
                                    color: .green, files: state.staged, key: "staged")
                        fileSection(title: "Unstaged", icon: "circle.dashed",
                                    color: .orange, files: state.unstaged, key: "unstaged")
                        fileSection(title: "Untracked", icon: "questionmark.circle",
                                    color: .secondary, files: state.untracked, key: "untracked")
                    }
                    .padding(.vertical, 6)
                }
            }

            // Diff preview sheet
            if let file = diffFile {
                Divider()
                DiffPreviewView(file: file, content: diffContent) {
                    diffFile = nil
                }
            }
        }
        .glassBackground(material: .sidebar, cornerRadius: 0)
        .sheet(isPresented: $showCommitAssistant) {
            CommitAssistantView(
                repoManager: repoManager,
                actionEngine: actionEngine,
                ai: ai,
                isPresented: $showCommitAssistant
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Branch indicator
            Image(systemName: state.isDetachedHEAD ? "exclamationmark.triangle.fill" : "arrow.triangle.branch")
                .foregroundColor(state.isDetachedHEAD ? .orange : .accentColor)
                .font(.caption)

            Text(state.branch.name)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(.primary)

            // Ahead/behind badges
            if state.branch.ahead > 0 {
                badge("↑\(state.branch.ahead)", color: .blue)
            }
            if state.branch.behind > 0 {
                badge("↓\(state.branch.behind)", color: .orange)
            }

            Spacer()

            // Commit button — only when staged files exist
            if !state.staged.isEmpty {
                Button("Commit…") { showCommitAssistant = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
            }

            Button { repoManager.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File Section

    private func fileSection(title: String, icon: String, color: Color,
                              files: [FileChange], key: String) -> some View {
        Group {
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    // Section header — tap to collapse
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedSections.contains(key) {
                                expandedSections.remove(key)
                            } else {
                                expandedSections.insert(key)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: expandedSections.contains(key)
                                  ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Image(systemName: icon).foregroundColor(color).font(.caption)
                            Text(title).font(.caption.bold()).foregroundColor(.secondary)
                            Text("(\(files.count))").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    if expandedSections.contains(key) {
                        ForEach(files) { file in
                            FileChangeRow(
                                file: file,
                                actionEngine: actionEngine,
                                onShowDiff: { showDiff(for: file) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hint Banner

    private func hintBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.caption)
            Text(text).font(.caption).foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.08))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Diff

    private func showDiff(for file: FileChange) {
        Task {
            let content = await repoManager.diff(for: file)
            await MainActor.run {
                diffContent = content
                diffFile = file
            }
        }
    }
}

// MARK: - FileChangeRow

struct FileChangeRow: View {
    let file: FileChange
    let actionEngine: GitActionEngine
    let onShowDiff: () -> Void

    @State private var isHovered = false
    @State private var confirmDiscard = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.status.icon)
                .font(.caption)
                .foregroundColor(statusColor)
                .frame(width: 14)

            Text(file.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(file.status.label)
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            if isHovered {
                actionButtons
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture { onShowDiff() }
        .help("\(file.path) — click to view diff")
        .contextMenu { contextMenuItems }
        .confirmationDialog("Discard changes to \(file.name)?",
                            isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                Task { await actionEngine.discardChanges(in: file) }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch file.area {
        case .unstaged:
            Button("Stage") { Task { await actionEngine.stage(file) } }
                .buttonStyle(.bordered).controlSize(.mini).tint(.green)
        case .staged:
            Button("Unstage") { Task { await actionEngine.unstage(file) } }
                .buttonStyle(.bordered).controlSize(.mini).tint(.orange)
        case .untracked:
            Button("Stage") { Task { await actionEngine.stage(file) } }
                .buttonStyle(.bordered).controlSize(.mini).tint(.green)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch file.area {
        case .unstaged:
            Button("Stage File")   { Task { await actionEngine.stage(file) } }
            Button("Discard Changes", role: .destructive) { confirmDiscard = true }
        case .staged:
            Button("Unstage File") { Task { await actionEngine.unstage(file) } }
        case .untracked:
            Button("Stage File")   { Task { await actionEngine.stage(file) } }
            Button("Delete File", role: .destructive) {
                Task { await actionEngine.deleteUntracked(file) }
            }
        }
        Divider()
        Button("Show Diff") { onShowDiff() }
        Button("Open in Editor") {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.fullPath))
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .added:      return .green
        case .modified:   return .orange
        case .deleted:    return .red
        case .conflicted: return .red
        case .renamed:    return .blue
        default:          return .secondary
        }
    }
}

// MARK: - DiffPreviewView

struct DiffPreviewView: View {
    let file: FileChange
    let content: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Diff: \(file.name)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Close") { onClose() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 200)
        }
        .glassBackground(material: .hudWindow, cornerRadius: 0)
    }
}

private struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(lineColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lineBg)
    }

    private var lineColor: Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return .secondary
    }

    private var lineBg: Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        return .clear
    }
}
