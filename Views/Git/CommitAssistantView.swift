import SwiftUI

/// Sheet that analyzes staged changes and suggests commit messages.
struct CommitAssistantView: View {
    @ObservedObject var repoManager: RepoStateManager
    let actionEngine: GitActionEngine
    let ai: AIService
    @Binding var isPresented: Bool

    @State private var suggestion: CommitSuggestion? = nil
    @State private var editedMessage: String = ""
    @State private var useConventional = true
    @State private var isLoading = false
    @State private var commitResult: String? = nil

    private var state: RepoState { repoManager.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Commit Assistant", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }

            // Staged files summary
            if !state.staged.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staged files (\(state.staged.count))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    ForEach(state.staged) { file in
                        HStack(spacing: 6) {
                            Image(systemName: file.status.icon).font(.caption2)
                                .foregroundColor(.green)
                            Text(file.path).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // AI suggestion area
            if isLoading {
                HStack { ProgressView().scaleEffect(0.7); Text("Analyzing changes…").font(.caption) }
            } else if let s = suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use conventional commit format", isOn: $useConventional)
                        .font(.caption)
                        .onChange(of: useConventional) { _, newValue in
                            editedMessage = newValue ? s.conventional : s.short
                        }

                    TextEditor(text: $editedMessage)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let body = s.body {
                        Text(body)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                // Initial state — prompt to generate
                Text("Click \"Generate\" to get an AI-suggested commit message based on your staged changes.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Or type your message manually…", text: $editedMessage)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            // Result feedback
            if let result = commitResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.hasPrefix("✅") ? .green : .red)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Generate") { generateSuggestion() }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || state.staged.isEmpty)

                if suggestion != nil {
                    Button("Regenerate") { generateSuggestion() }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Spacer()

                Button("Commit") { performCommit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .glassBackground(material: .hudWindow, cornerRadius: 16)
        .onAppear { generateSuggestion() }
    }

    // MARK: - Actions

    private func generateSuggestion() {
        isLoading = true
        Task {
            // Collect diff for all staged files
            var combinedDiff = ""
            for file in state.staged.prefix(5) {
                let d = await repoManager.diff(for: file)
                combinedDiff += d + "\n"
            }
            let s = await ai.suggestCommitMessage(
                diff: combinedDiff,
                stagedFiles: state.staged.map(\.path)
            )
            await MainActor.run {
                suggestion = s
                editedMessage = useConventional ? s.conventional : s.short
                isLoading = false
            }
        }
    }

    private func performCommit() {
        let message = editedMessage.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        Task {
            let success = await actionEngine.commit(message: message)
            await MainActor.run {
                if success {
                    commitResult = "✅ Committed successfully"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isPresented = false
                    }
                } else {
                    commitResult = "❌ Commit failed — check terminal for details"
                }
            }
        }
    }
}
