import SwiftUI

struct AISettingsView: View {
    @ObservedObject var settings: AISettingsStore
    @State private var showAPIKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                providerSection
                openAISection
                ollamaSection
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Settings")
                .font(.system(size: 24, weight: .semibold))

            Text("Choose your AI provider, configure models, and store your OpenAI API key securely in the macOS Keychain.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                statusPill("Active: \(settings.resolvedProviderTitle)")
                statusPill("Model: \(settings.effectiveModel)")
            }
        }
    }

    private var providerSection: some View {
        settingsCard(title: "Provider") {
            Picker("AI Provider", selection: $settings.providerPreference) {
                ForEach(AISettingsStore.ProviderPreference.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Text("Automatic prefers OpenAI when an API key is available. Otherwise LAMA S falls back to Ollama.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var openAISection: some View {
        settingsCard(title: "OpenAI / ChatGPT API") {
            VStack(alignment: .leading, spacing: 12) {
                labeledField("Model") {
                    TextField("gpt-5.4", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("API Key") {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField("sk-...", text: $settings.openAIAPIKey)
                            } else {
                                SecureField("sk-...", text: $settings.openAIAPIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Toggle("Show API key", isOn: $showAPIKey)
                            .toggleStyle(.checkbox)

                        Text("Stored locally in your macOS Keychain. If left empty, LAMA S can still read OPENAI_API_KEY from the environment.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var ollamaSection: some View {
        settingsCard(title: "Ollama") {
            VStack(alignment: .leading, spacing: 12) {
                labeledField("Model") {
                    TextField("phi3", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Endpoint") {
                    TextField("http://localhost:11434/api/chat", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("Open via the app menu or the slider button in the terminal header.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}
