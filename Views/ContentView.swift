import SwiftUI

struct ContentView: View {
    @ObservedObject var aiSettings: AISettingsStore
    @StateObject private var engine = TerminalEngine()
    @StateObject private var repoManager = RepoStateManager()
    @State private var ai = AIService()
    @State private var actionEngine: GitActionEngine? = nil

    @State private var inputText = ""
    @State private var lastCommand = ""
    @State private var aiState: AIPanelState = .idle
    @State private var isPanelExpanded = true
    @State private var activePanel: ActivePanel = .ai
    @State private var showIntro = true
    @State private var introOpacity: Double = 1

    private enum ActivePanel { case ai, git }

    private var appearance: TerminalAppearance { engine.appearance }

    var body: some View {
        ZStack {
            appearance.backgroundGradient
                .ignoresSafeArea()

            ambientBackground

            terminalLayer
                .padding(.horizontal, 6)
                .padding(.vertical, 6)

            if showIntro {
                IntroView(appearance: appearance)
                    .opacity(introOpacity)
                    .allowsHitTesting(false)
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            engine.start()
            actionEngine = GitActionEngine(repoManager: repoManager)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { dismissIntro() }
        }
        .onDisappear { engine.stop() }
        .onChange(of: engine.hasReceivedOutput) { _, hasOutput in
            if hasOutput { dismissIntro() }
        }
        .onChange(of: inputText) { _, _ in
            if showIntro { dismissIntro() }
        }
        .onChange(of: engine.introToken) { _, _ in
            introOpacity = 1
            showIntro = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { dismissIntro() }
        }
        .onChange(of: engine.lastError) { _, errorText in
            guard let errorText, !errorText.isEmpty else { return }
            guard !engine.isNLMode else { return }
            aiState = .loading
            activePanel = .ai
            isPanelExpanded = true
            Task {
                let response = await ai.analyzeError(command: lastCommand, output: errorText)
                await MainActor.run { aiState = .explanation(response) }
            }
        }
        .onChange(of: engine.lastAIChat) { _, chat in
            guard let chat else { return }
            aiState = .chat(chat)
            activePanel = .ai
            isPanelExpanded = true
        }
        .onChange(of: engine.currentDirectory) { _, dir in
            repoManager.setDirectory(dir)
        }
    }

    private var terminalLayer: some View {
        VStack(spacing: 0) {
            TerminalView(
                engine: engine,
                aiSettings: aiSettings,
                inputText: $inputText,
                lastCommand: $lastCommand,
                onSubmit: handleSubmit,
                onExplain: handleExplain,
                onNLConvert: handleNLConvert
            )

            panelToggleBar

            if isPanelExpanded {
                bottomPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            appearance.chromeBackground.opacity(0.82),
                            appearance.background.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var bottomPanel: some View {
        switch activePanel {
        case .ai:
            AIPanelView(
                state: aiState,
                onRunSuggested: { cmd in executeCommand(cmd) },
                onConfirmDangerous: { cmd in executeCommand(cmd) },
                onApproveAgent: executeAgentPlan
            )
        case .git:
            if repoManager.isGitRepo, let ae = actionEngine {
                GitStatusView(repoManager: repoManager, actionEngine: ae, ai: ai)
                    .frame(maxHeight: 300)
            } else {
                Text("Not a git repository")
                    .font(TerminalTheme.ui(12))
                    .foregroundColor(appearance.textSecondary)
                    .padding(12)
            }
        }
    }

    private var panelToggleBar: some View {
        HStack(spacing: 0) {
            panelTab(label: "AI Assistant", icon: "sparkles",
                     panel: .ai, badge: aiState == .loading ? "..." : nil)

            if repoManager.isGitRepo {
                panelTab(label: "Git", icon: "arrow.triangle.branch",
                         panel: .git, badge: gitBadge)
            }

            Spacer()

            Button(isPanelExpanded ? "Hide" : "Show") {
                withAnimation(.easeInOut(duration: 0.2)) { isPanelExpanded.toggle() }
            }
            .font(TerminalTheme.ui(11))
            .buttonStyle(.plain)
            .foregroundColor(appearance.textSecondary)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 3)
        .background(appearance.secondaryBackground.opacity(0.24))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.08)), alignment: .top)
    }

    private func panelTab(label: String, icon: String,
                          panel: ActivePanel, badge: String?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if activePanel == panel { isPanelExpanded.toggle() }
                else { activePanel = panel; isPanelExpanded = true }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(TerminalTheme.ui(11, weight: .semibold))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(appearance.textAccent.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(activePanel == panel && isPanelExpanded
                             ? appearance.textAccent : appearance.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var gitBadge: String? {
        let n = repoManager.state.staged.count + repoManager.state.unstaged.count
        return n > 0 ? "\(n)" : nil
    }

    private func dismissIntro() {
        guard showIntro else { return }
        withAnimation(.easeInOut(duration: 0.4)) { introOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { showIntro = false }
    }

    private var ambientBackground: some View {
        ZStack {
            Circle()
                .fill(appearance.textAccent.opacity(0.05))
                .frame(width: 540, height: 540)
                .blur(radius: 150)
                .offset(x: -340, y: -260)

            Circle()
                .fill(Color.white.opacity(0.02))
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .offset(x: 380, y: 260)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.02), .clear, Color.black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func handleSubmit() {
        let cmd = inputText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        if cmd.hasPrefix("explain ") {
            let target = String(cmd.dropFirst(8))
            inputText = ""
            aiState = .loading
            activePanel = .ai
            isPanelExpanded = true
            Task {
                let response = await ai.explain(command: target)
                await MainActor.run { aiState = .explanation(response) }
            }
            return
        }

        if let warning = SafetyEngine.analyze(cmd),
           CommandParser.parseBuiltin(cmd) == nil {
            aiState = .warning(warning)
            activePanel = .ai
            isPanelExpanded = true
            inputText = ""
            return
        }

        executeCommand(cmd)
    }

    private func executeCommand(_ cmd: String) {
        lastCommand = cmd
        inputText = ""
        engine.send(cmd)
        aiState = .idle

        if cmd.hasPrefix("git ") || cmd == "git" {
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                repoManager.refresh()
                let response = await ai.explainGitCommand(cmd, repoState: repoManager.state)
                await MainActor.run {
                    aiState = .explanation(response)
                    activePanel = .ai
                    isPanelExpanded = true
                }
            }
        }
    }

    private func handleExplain() {
        let cmd = inputText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        aiState = .loading
        activePanel = .ai
        isPanelExpanded = true
        Task {
            let response = cmd.hasPrefix("git ")
                ? await ai.explainGitCommand(cmd, repoState: repoManager.state)
                : await ai.explain(command: cmd)
            await MainActor.run { aiState = .explanation(response) }
        }
    }

    private func handleNLConvert() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        activePanel = .ai
        isPanelExpanded = true
        inputText = ""
        streamChat(text)
    }

    private func streamChat(_ text: String) {
        aiState = .streaming("")
        Task {
            var accumulated = ""
            for await token in ai.chatStream(text) {
                accumulated += token
                await MainActor.run { aiState = .streaming(accumulated) }
            }
            let result = AIChatResponse(
                prose: CommandParser.stripCommandBlocks(from: accumulated),
                commands: CommandParser.filterCommands(CommandParser.extractCommands(from: accumulated))
            )
            await MainActor.run { aiState = .chat(result) }
        }
    }

    private func executeAgentPlan(_ plan: AgentPlan) {
        Task {
            for step in plan.steps where step.type == "command" {
                await MainActor.run { engine.send(step.run) }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            await MainActor.run { aiState = .idle }
        }
    }
}

extension AIPanelState: Equatable {
    static func == (lhs: AIPanelState, rhs: AIPanelState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.streaming(let a), .streaming(let b)): return a == b
        default: return false
        }
    }
}
