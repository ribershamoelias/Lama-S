import Foundation

// MARK: - Terminal

/// A single segment within a terminal line — either plain text or a detected file path.
enum ParsedSegment {
    case text(String)
    case path(String, isDirectory: Bool)  // full path string + type
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let content: String
    let type: LineType
    let metadata: String?          // used by .directory lines (full path)
    let segments: [ParsedSegment]

    init(content: String, type: LineType, metadata: String? = nil) {
        self.content = content
        self.type = type
        self.metadata = metadata
        self.segments = (type == .output || type == .error)
            ? LineParser.parse(content)
            : [.text(content)]
    }

    enum LineType {
        case input, output, error, system, directory, file, ai
    }
}

// MARK: - Safety

enum RiskLevel: String {
    case low, medium, high

    var emoji: String {
        switch self {
        case .low: return "✅"
        case .medium: return "⚠️"
        case .high: return "🚨"
        }
    }

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}

struct SafetyWarning {
    let command: String
    let risk: RiskLevel
    let reason: String
}

// MARK: - AI

struct AIResponse {
    let explanation: String
    let suggestion: String?
    let risk: RiskLevel?
    let agentPlan: AgentPlan?
}

struct AgentPlan: Codable {
    let explanation: String
    let steps: [AgentStep]
    let risk: String
}

struct AgentStep: Codable, Identifiable {
    let id = UUID()
    let type: String
    let run: String

    enum CodingKeys: String, CodingKey {
        case type, run
    }
}

// MARK: - AI Chat Response

struct AIChatResponse: Equatable {
    let prose: String
    let commands: [String]
}

// MARK: - AI Panel State

enum AIPanelState {
    case idle
    case loading
    case streaming(String)          // live token accumulation
    case explanation(AIResponse)
    case chat(AIChatResponse)
    case warning(SafetyWarning)
    case agentPlan(AgentPlan)
    case error(String)
}
