import SwiftUI

struct AIPanelView: View {
    let state: AIPanelState
    let onRunSuggested: (String) -> Void
    let onConfirmDangerous: (String) -> Void
    let onApproveAgent: (AgentPlan) -> Void

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()

            case .loading:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…").foregroundColor(.secondary)
                }
                .padding(12)

            case .streaming(let text):
                StreamingCard(text: text)

            case .explanation(let response):
                ExplanationCard(response: response, onRun: onRunSuggested)

            case .chat(let response):
                ChatResponseCard(response: response, onRun: onRunSuggested)

            case .warning(let warning):
                WarningCard(warning: warning, onProceed: { onConfirmDangerous(warning.command) })

            case .agentPlan(let plan):
                AgentPlanCard(plan: plan, onApprove: { onApproveAgent(plan) })

            case .error(let msg):
                Text("⚠️ \(msg)")
                    .foregroundColor(.orange)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(material: .hudWindow, cornerRadius: 0)
    }
}

// MARK: - Streaming Card

private struct StreamingCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Assistant", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundColor(.accentColor)
            Text(text + "▌")  // blinking cursor feel
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chat Response Card (clickable commands)

private struct ChatResponseCard: View {
    let response: AIChatResponse
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Assistant", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundColor(.accentColor)

            if !response.prose.isEmpty {
                Text(response.prose)
                    .font(.callout)
                    .foregroundColor(.primary)
            }

            if !response.commands.isEmpty {
                Divider()
                ForEach(response.commands, id: \.self) { cmd in
                    CommandChip(command: cmd, onRun: onRun)
                }
            }
        }
        .padding(12)
    }
}

private struct CommandChip: View {
    let command: String
    let onRun: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: { onRun(command) }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
                Spacer()
                Text("Run")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.green.opacity(0.15) : Color.black.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.green.opacity(isHovered ? 0.5 : 0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Explanation Card

private struct ExplanationCard: View {
    let response: AIResponse
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Explanation", systemImage: "brain")
                .font(.caption.bold())
                .foregroundColor(.accentColor)

            Text(response.explanation)
                .font(.callout)
                .foregroundColor(.primary)

            if let suggestion = response.suggestion {
                Divider()
                Text("Suggestion").font(.caption.bold()).foregroundColor(.secondary)
                HStack {
                    Text(suggestion)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                    Spacer()
                    Button("Run") { onRun(suggestion) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Warning Card

private struct WarningCard: View {
    let warning: SafetyWarning
    let onProceed: () -> Void
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(warning.risk.emoji) \(warning.risk.rawValue.uppercased()) RISK",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundColor(riskColor)

            Text(warning.reason).font(.callout)

            Text("Command: \(warning.command)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            if warning.risk == .high {
                Toggle("I understand the risk and want to proceed", isOn: $confirmed)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Run Anyway") { onProceed() }
                    .buttonStyle(.borderedProminent)
                    .tint(riskColor)
                    .controlSize(.small)
                    .disabled(warning.risk == .high && !confirmed)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(riskColor.opacity(0.4)))
        .padding(12)
    }

    private var riskColor: Color {
        switch warning.risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Agent Plan Card

private struct AgentPlanCard: View {
    let plan: AgentPlan
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agent Plan", systemImage: "list.bullet.rectangle")
                .font(.caption.bold())
                .foregroundColor(.accentColor)

            Text(plan.explanation).font(.callout)

            ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 6) {
                    Text("\(i + 1).")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(step.run)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            HStack {
                Text("Risk: \(plan.risk)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Approve & Run") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3)))
        .padding(12)
    }
}
