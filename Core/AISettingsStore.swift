import Foundation
import Combine

final class AISettingsStore: ObservableObject {
    enum ProviderPreference: String, CaseIterable, Identifiable {
        case automatic
        case openAI = "openai"
        case ollama

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .openAI: return "OpenAI"
            case .ollama: return "Ollama"
            }
        }
    }

    struct Snapshot {
        let providerPreference: ProviderPreference
        let openAIAPIKey: String
        let openAIModel: String
        let ollamaModel: String
        let ollamaEndpoint: String

        var resolvedProvider: ProviderPreference {
            switch providerPreference {
            case .automatic:
                return openAIAPIKey.isEmpty ? .ollama : .openAI
            case .openAI, .ollama:
                return providerPreference
            }
        }

        var effectiveModel: String {
            resolvedProvider == .openAI ? openAIModel : ollamaModel
        }
    }

    static let shared = AISettingsStore()

    @Published var providerPreference: ProviderPreference {
        didSet { defaults.set(providerPreference.rawValue, forKey: Keys.providerPreference) }
    }

    @Published var openAIAPIKey: String {
        didSet {
            let value = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                KeychainService.delete(account: Keys.openAIAPIKey)
            } else {
                KeychainService.save(value: value, account: Keys.openAIAPIKey)
            }
        }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
    }

    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var ollamaEndpoint: String {
        didSet { defaults.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let snapshot = Self.currentSnapshot()
        providerPreference = snapshot.providerPreference
        openAIAPIKey = snapshot.openAIAPIKey
        openAIModel = snapshot.openAIModel
        ollamaModel = snapshot.ollamaModel
        ollamaEndpoint = snapshot.ollamaEndpoint
    }

    var resolvedProviderTitle: String {
        Self.currentSnapshot().resolvedProvider.title
    }

    var effectiveModel: String {
        Self.currentSnapshot().effectiveModel
    }

    func resetToDefaults() {
        providerPreference = .automatic
        openAIAPIKey = ""
        openAIModel = Self.defaultOpenAIModel
        ollamaModel = Self.defaultOllamaModel
        ollamaEndpoint = Self.defaultOllamaEndpoint
    }

    static func currentSnapshot() -> Snapshot {
        let defaults = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment

        let providerRaw = (defaults.string(forKey: Keys.providerPreference)
            ?? env["LAMA_AI_PROVIDER"]
            ?? ProviderPreference.automatic.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let providerPreference = ProviderPreference(rawValue: providerRaw) ?? .automatic
        let keychainKey = KeychainService.load(account: Keys.openAIAPIKey) ?? ""
        let envKey = env["OPENAI_API_KEY"] ?? ""
        let openAIAPIKey = keychainKey.isEmpty ? envKey : keychainKey

        let openAIModel = nonEmpty(
            defaults.string(forKey: Keys.openAIModel),
            env["OPENAI_MODEL"],
            defaultOpenAIModel
        )

        let ollamaModel = nonEmpty(
            defaults.string(forKey: Keys.ollamaModel),
            env["OLLAMA_MODEL"],
            defaultOllamaModel
        )

        let ollamaEndpoint = nonEmpty(
            defaults.string(forKey: Keys.ollamaEndpoint),
            env["OLLAMA_ENDPOINT"],
            defaultOllamaEndpoint
        )

        return Snapshot(
            providerPreference: providerPreference,
            openAIAPIKey: openAIAPIKey,
            openAIModel: openAIModel,
            ollamaModel: ollamaModel,
            ollamaEndpoint: ollamaEndpoint
        )
    }

    private static func nonEmpty(_ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    static let defaultOpenAIModel = "gpt-5.4"
    static let defaultOllamaModel = "phi3"
    static let defaultOllamaEndpoint = "http://localhost:11434/api/chat"

    private enum Keys {
        static let providerPreference = "lama.ai.providerPreference"
        static let openAIAPIKey = "lama.ai.openai.apiKey"
        static let openAIModel = "lama.ai.openai.model"
        static let ollamaModel = "lama.ai.ollama.model"
        static let ollamaEndpoint = "lama.ai.ollama.endpoint"
    }
}
