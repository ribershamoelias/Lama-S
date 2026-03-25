import Foundation

/// Sends prompts to AI and parses structured JSON responses.
/// Supports OpenAI Responses API and local Ollama with runtime provider selection.
final class AIService {

    // MARK: - Configuration

    enum Provider: String {
        case openAI = "openai"
        case ollama = "ollama"
    }

    struct Config {
        var provider: Provider
        var endpoint: URL
        var model: String
        var apiKey: String?

        static let openAI = Config(
            provider: .openAI,
            endpoint: URL(string: "https://api.openai.com/v1/responses")!,
            model: AISettingsStore.defaultOpenAIModel,
            apiKey: nil
        )

        static let ollama = Config(
            provider: .ollama,
            endpoint: URL(string: AISettingsStore.defaultOllamaEndpoint)!,
            model: AISettingsStore.defaultOllamaModel,
            apiKey: nil
        )
    }

    private let fixedConfig: Config?

    init(config: Config? = nil) {
        self.fixedConfig = config
    }

    // MARK: - Cache

    private var cache: [String: AIChatResponse] = [:]

    // MARK: - Public API

    func explain(command: String) async -> AIResponse {
        let raw = await send(CommandParser.explainPrompt(for: command))
        return parseExplanation(raw)
    }

    func analyzeError(command: String, output: String) async -> AIResponse {
        let raw = await send(CommandParser.errorPrompt(command: command, errorOutput: output))
        return parseError(raw)
    }

    func naturalLanguageToCommand(_ text: String) async -> AIResponse {
        let raw = await send(CommandParser.nlToCommandPrompt(text))
        return parseNLCommand(raw)
    }

    // MARK: - Master Chat (streaming + cached)

    func chat(_ userInput: String) async -> AIChatResponse {
        let key = userInput.lowercased().trimmingCharacters(in: .whitespaces)
        if let cached = cache[key] { return cached }
        let raw = await sendWithSystem(
            system: CommandParser.masterSystemPrompt,
            user: CommandParser.chatPrompt(userInput)
        )
        let result = AIChatResponse(
            prose: CommandParser.stripCommandBlocks(from: raw),
            commands: CommandParser.filterCommands(CommandParser.extractCommands(from: raw))
        )
        cache[key] = result
        return result
    }

    /// Streaming version — yields tokens live via AsyncStream.
    /// Caller receives partial text chunks as they arrive.
    func chatStream(_ userInput: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let key = userInput.lowercased().trimmingCharacters(in: .whitespaces)
                if let cached = cache[key] {
                    // Replay cache instantly
                    let full = cached.prose + cached.commands.map { "\n[COMMAND]\n\($0)\n[/COMMAND]" }.joined()
                    continuation.yield(full)
                    continuation.finish()
                    return
                }
                await streamWithSystem(
                    system: CommandParser.masterSystemPrompt,
                    user: userInput,
                    onToken: { continuation.yield($0) }
                )
                continuation.finish()
            }
        }
    }

    // MARK: - Structure Mode (AI fallback)

    /// Called only when IntentEngine.resolve() returns needsAI = true in structure mode.
    /// Returns only mkdir/touch commands — no prose, no code.
    func generateStructure(for intent: String) async -> [String] {
        let raw = await sendWithSystem(
            system: CommandParser.structureSystemPrompt,
            user: intent
        )
        let blocked = ["open ", "osascript", "nano", "vim", "vi ", "emacs", "<<", "EOF", "&&"]
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                // Must start with a known safe command
                let isCommand = line.hasPrefix("mkdir") || line.hasPrefix("cd ")
                    || line.hasPrefix("touch") || line.hasPrefix("cd ~")
                guard isCommand else { return false }
                // Must not contain blocked patterns
                return !blocked.contains { line.contains($0) }
            }
    }

    // MARK: - Git AI

    func explainGitCommand(_ command: String, repoState: RepoState) async -> AIResponse {
        let prompt = """
        You are a Git expert explaining commands to a developer.
        Current branch: \(repoState.branch.name)
        Staged files: \(repoState.staged.map(\.path).joined(separator: ", "))
        Unstaged files: \(repoState.unstaged.map(\.path).joined(separator: ", "))

        Explain this git command simply and clearly:
        Command: \(command)

        Respond in JSON:
        {
          "explanation": "what this command does in plain English",
          "what_changes": "what will change in the repo after running it",
          "risks": "any risks or things to be careful about, or null",
          "tip": "a helpful tip or alternative, or null"
        }
        """
        let raw = await send(prompt)
        return parseGitExplanation(raw)
    }

    func suggestCommitMessage(diff: String, stagedFiles: [String]) async -> CommitSuggestion {
        let prompt = """
        You are a senior developer writing a git commit message.
        Staged files: \(stagedFiles.joined(separator: ", "))

        Diff summary:
        \(String(diff.prefix(2000)))

        Generate a commit message. Respond in JSON:
        {
          "short": "one-line summary under 72 chars",
          "conventional": "conventional commit format e.g. feat(scope): description",
          "body": "optional 2-3 sentence explanation of why, or null"
        }
        """
        let raw = await send(prompt)
        return parseCommitSuggestion(raw)
    }

    func explainConflict(file: String, diff: String) async -> AIResponse {
        let prompt = """
        A merge conflict occurred in: \(file)

        Conflict diff:
        \(String(diff.prefix(1500)))

        Explain:
        1. What caused this conflict
        2. What each side (HEAD vs incoming) is trying to do
        3. How to resolve it

        Respond in JSON:
        {
          "explanation": "clear explanation of the conflict",
          "risks": "what could go wrong if resolved incorrectly",
          "suggested_command": "git command to help resolve, if applicable"
        }
        """
        let raw = await send(prompt)
        return parseError(raw)
    }

    // MARK: - Network

    private var config: Config {
        fixedConfig ?? Self.resolveDefaultConfig()
    }

    private static func resolveDefaultConfig() -> Config {
        let snapshot = AISettingsStore.currentSnapshot()

        if snapshot.resolvedProvider == .openAI {
            var config = Config.openAI
            config.model = snapshot.openAIModel
            config.apiKey = snapshot.openAIAPIKey
            return config
        }

        var config = Config.ollama
        config.model = snapshot.ollamaModel
        if let endpoint = URL(string: snapshot.ollamaEndpoint) {
            config.endpoint = endpoint
        }
        return config
    }

    private func send(_ prompt: String) async -> String {
        await sendWithSystem(system: nil, user: prompt)
    }

    private func sendWithSystem(system: String?, user: String) async -> String {
        var full = ""
        await streamWithSystem(system: system, user: user) { full += $0 }
        if !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return full
        }

        return defaultFailureMessage(for: config)
    }

    /// Core streaming method. Calls `onToken` for each chunk received.
    private func streamWithSystem(system: String?, user: String, onToken: @escaping (String) -> Void) async {
        let config = self.config
        let apiKey = config.apiKey ?? ""

        if config.provider == .openAI && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onToken("OpenAI is selected, but no OPENAI_API_KEY is configured.")
            return
        }

        let body = requestBody(config: config, system: system, user: user, stream: true)

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.provider == .openAI, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data

        guard let (stream, response) = try? await URLSession.shared.bytes(for: request) else {
            onToken(defaultFailureMessage(for: config))
            return
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorBody = ""
            do {
                for try await line in stream.lines {
                    errorBody += line
                }
            } catch {}

            onToken(parseHTTPError(from: errorBody, statusCode: http.statusCode))
            return
        }

        do {
            var sawOpenAIDelta = false
            for try await line in stream.lines {
                guard !line.isEmpty else { continue }
                let jsonStr = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
                guard jsonStr != "[DONE]",
                      let chunk = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any]
                else { continue }

                // Ollama /api/chat: { "message": { "content": "..." } }
                // OpenAI SSE:       { "choices": [{ "delta": { "content": "..." } }] }
                let token: String?
                if let msg = json["message"] as? [String: Any] {
                    token = msg["content"] as? String
                } else {
                    let type = json["type"] as? String
                    if type == "response.output_text.delta" {
                        sawOpenAIDelta = true
                        token = json["delta"] as? String
                    } else if !sawOpenAIDelta {
                        token = extractOpenAIOutputText(from: json)
                    } else {
                        token = nil
                    }
                }
                if let t = token, !t.isEmpty { onToken(t) }
            }
        } catch {
            if !Task.isCancelled {
                onToken(defaultFailureMessage(for: config))
            }
        }
    }

    private func requestBody(config: Config, system: String?, user: String, stream: Bool) -> [String: Any] {
        if config.provider == .ollama {
            var messages: [[String: Any]] = []
            if let system { messages.append(["role": "system", "content": system]) }
            messages.append(["role": "user", "content": user])

            return [
                "model": config.model,
                "messages": messages,
                "stream": stream,
                "options": ["temperature": 0.2, "num_predict": 300, "num_ctx": 2048]
            ]
        }

        var body: [String: Any] = [
            "model": config.model,
            "input": user,
            "stream": stream
        ]
        if let system, !system.isEmpty {
            body["instructions"] = system
        }
        return body
    }

    private func defaultFailureMessage(for config: Config) -> String {
        switch config.provider {
        case .openAI:
            return "OpenAI request failed. Check OPENAI_API_KEY, OPENAI_MODEL, network access, and billing."
        case .ollama:
            return "Ollama request failed. Check that Ollama is running locally and the selected model is installed."
        }
    }

    private func parseHTTPError(from body: String, statusCode: Int) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "\(providerDisplayName(for: config)) request failed with HTTP \(statusCode)."
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(providerDisplayName(for: config)) error (HTTP \(statusCode)): \(message)"
        }

        return "\(providerDisplayName(for: config)) request failed with HTTP \(statusCode)."
    }

    private func providerDisplayName(for config: Config) -> String {
        switch config.provider {
        case .openAI:
            return "OpenAI"
        case .ollama:
            return "Ollama"
        }
    }

    private func extractOpenAIOutputText(from json: [String: Any]) -> String? {
        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        if let response = json["response"] as? [String: Any] {
            return extractOpenAIText(fromResponse: response)
        }

        return nil
    }

    private func extractOpenAIText(fromResponse response: [String: Any]) -> String? {
        if let outputText = response["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        guard let output = response["output"] as? [[String: Any]] else { return nil }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    /// Strips markdown formatting and trims to first 300 chars for terminal display.
    private func cleanMarkdown(_ text: String) -> String {
        var s = text
        // Remove code fences
        s = s.replacingOccurrences(of: "```[a-z]*\n?", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "```", with: "")
        // Remove bold/italic
        s = s.replacingOccurrences(of: "[*_]{1,2}([^*_]+)[*_]{1,2}", with: "$1", options: .regularExpression)
        // Remove inline code backticks
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Collapse multiple newlines
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap at 500 chars for terminal readability
        if s.count > 500 { s = String(s.prefix(500)) + "…" }
        return s
    }

    // MARK: - Parsers

    private func parseExplanation(_ raw: String) -> AIResponse {
        // Try JSON first, fall back to raw text
        if let json = extractJSON(raw), let explanation = json["explanation"] as? String {
            return AIResponse(explanation: explanation, suggestion: nil, risk: nil, agentPlan: nil)
        }
        return AIResponse(explanation: raw.isEmpty ? "Could not get explanation." : raw,
                          suggestion: nil, risk: nil, agentPlan: nil)
    }

    private func parseError(_ raw: String) -> AIResponse {
        if let json = extractJSON(raw) {
            let cause = json["cause"] as? String ?? ""
            let fix   = json["fix"] as? String ?? ""
            let combined = [cause, fix].filter { !$0.isEmpty }.joined(separator: " ")
            return AIResponse(explanation: combined.isEmpty ? raw : combined,
                              suggestion: json["suggested_command"] as? String,
                              risk: nil, agentPlan: nil)
        }
        return AIResponse(explanation: raw, suggestion: nil, risk: nil, agentPlan: nil)
    }

    private func parseNLCommand(_ raw: String) -> AIResponse {
        guard let json = extractJSON(raw),
              let command = json["command"] as? String else {
            return AIResponse(explanation: "Could not convert to command.",
                              suggestion: nil, risk: nil, agentPlan: nil)
        }
        let risk = RiskLevel(rawValue: json["risk"] as? String ?? "low") ?? .low
        return AIResponse(explanation: json["explanation"] as? String ?? "",
                          suggestion: command, risk: risk, agentPlan: nil)
    }

    // Extracts first JSON object from a string (handles markdown code fences)
    private func extractJSON(_ text: String) -> [String: Any]? {
        guard let start = text.range(of: "{"),
              let end   = text.range(of: "}", options: .backwards),
              start.lowerBound <= end.lowerBound else { return nil }
        let s = String(text[start.lowerBound...end.lowerBound])
        guard let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func parseGitExplanation(_ raw: String) -> AIResponse {
        guard let json = extractJSON(raw) else {
            return AIResponse(explanation: raw, suggestion: nil, risk: nil, agentPlan: nil)
        }
        let explanation  = json["explanation"] as? String ?? raw
        let whatChanges  = json["what_changes"] as? String
        let risks        = json["risks"] as? String
        let tip          = json["tip"] as? String
        let parts        = [whatChanges, risks, tip].compactMap { $0 }
        return AIResponse(explanation: explanation,
                          suggestion: parts.isEmpty ? nil : parts.joined(separator: "\n"),
                          risk: nil, agentPlan: nil)
    }

    private func parseCommitSuggestion(_ raw: String) -> CommitSuggestion {
        guard let json = extractJSON(raw) else {
            return CommitSuggestion(short: "chore: update files", conventional: "chore: update files", body: nil)
        }
        return CommitSuggestion(
            short:        json["short"]        as? String ?? "chore: update",
            conventional: json["conventional"] as? String ?? "chore: update",
            body:         json["body"]         as? String
        )
    }
}

