import Foundation

struct ParsedCommand {
    let base: String          // e.g. "ls"
    let flags: [String]       // e.g. ["-la", "--color"]
    let arguments: [String]   // e.g. ["/tmp"]
    let raw: String
}

enum LamaBuiltinCommand {
    case help
    case clear
    case intro
    case mode(Bool)
    case themeList
    case themeSet(String)
    case themeNext
    case accentList
    case accentSet(String)
    case densitySet(String)
    case glass(Bool)
    case mkcd(String)
    case parentDirectory
    case home
}

struct CommandParser {

    static func parse(_ input: String) -> ParsedCommand {
        let tokens = tokenize(input)

        guard !tokens.isEmpty else {
            return ParsedCommand(base: "", flags: [], arguments: [], raw: input)
        }

        let base = tokens[0]
        var flags: [String] = []
        var args: [String] = []

        for token in tokens.dropFirst() {
            if token.hasPrefix("-") {
                flags.append(token)
            } else {
                args.append(token)
            }
        }

        return ParsedCommand(base: base, flags: flags, arguments: args, raw: input)
    }

    static func parseBuiltin(_ input: String) -> LamaBuiltinCommand? {
        let tokens = tokenize(input)
        guard let first = tokens.first?.lowercased() else { return nil }

        switch first {
        case "lama":
            return parseLamaCommand(tokens.dropFirst().map { $0 })
        case "mkcd":
            guard tokens.count > 1 else { return nil }
            return .mkcd(tokens.dropFirst().joined(separator: " "))
        case "..":
            return .parentDirectory
        case "home":
            return .home
        default:
            return nil
        }
    }

    /// Builds a concise prompt asking AI to explain the command
    static func explainPrompt(for command: String) -> String {
        return """
        You are an AI assistant inside a developer terminal called Lama Terminal.
        The user typed: `\(command)`

        If this looks like a valid terminal command, explain it clearly and briefly:
        - What it does (one sentence)
        - When to use it
        - A short example if helpful

        If it is NOT a terminal command (e.g. natural language like "i want to build a flutter app"),
        do NOT treat it as a command. Instead, give a short helpful response guiding the user.

        Keep the total response under 3 sentences. No markdown. No bullet symbols. Plain text only.
        """
    }

    /// Builds a prompt to convert natural language to a shell command
    static func nlToCommandPrompt(_ naturalLanguage: String) -> String {
        return """
        Convert this to a macOS shell command. Reply with JSON only, no explanation outside JSON.
        Request: "\(naturalLanguage)"
        {"command": "...", "explanation": "...", "risk": "low|medium|high"}
        """
    }

    // MARK: - Structure Mode Prompt (Guided AI)

    static let structureSystemPrompt = """
    You are a professional software architect inside a terminal.

    Your task: generate a clean, realistic, professional project structure based on the user's intent.

    Think like a senior developer. Choose a structure used in real-world projects.
    Adapt the depth based on complexity:
    - "simple" or "basic" → fewer folders, minimal files
    - "production", "saas", "advanced" → larger, more complete structure
    - default → modern, clean, practical

    STRUCTURE GUIDELINES:
    - Website/portfolio: css, js, assets, components, pages
    - Backend/API: src, routes, controllers, models, middleware
    - React/Vue: src, components, pages, hooks, public
    - Flutter: lib, lib/screens, lib/widgets, lib/models, assets
    - Swift/iOS: Sources, Models, Views, ViewModels, Resources
    - Python: src, tests, with requirements.txt
    - Blog: posts, pages, public, styles

    Prefer modern naming conventions. Avoid outdated structures.

    STRICT OUTPUT RULES:
    1. ONLY output shell commands — one per line
    2. NO code content (no HTML, CSS, JS inside files)
    3. NO explanations, NO comments, NO markdown
    4. NO GUI apps (no open, no osascript)
    5. NO duplicate commands
    6. NO heredoc, NO editors (vim, nano)
    7. Use only: mkdir, cd, touch

    EXAMPLE:
    User: "I want a personal portfolio website"
    Output:
    mkdir portfolio-site
    cd portfolio-site
    mkdir css js assets components pages
    touch index.html css/style.css js/main.js README.md
    """

    // MARK: - Master Chat Prompt

    static let masterSystemPrompt = """
    You are an AI inside Lama Terminal. Generate terminal commands only.

    STRICT RULES:
    - Each command must be ONE LINE only
    - NO multi-line commands
    - NO heredoc (cat <<EOF, cat <<EOT)
    - NO editors (nano, vim, vi, emacs)
    - NO && chaining
    - NO explanations inside command blocks
    - NO GUI apps (open, TextEdit, Safari)
    - To create a file with content: use touch only, never cat <<EOF

    FORMAT — use exactly this, nothing else:

    One short sentence describing the step.

    [COMMAND]
    mkdir my-project
    [/COMMAND]

    [COMMAND]
    cd my-project
    [/COMMAND]

    Do NOT explain each command. Do NOT add prose after the blocks.
    """

    static func chatPrompt(_ userInput: String) -> String { userInput }

    // MARK: - [COMMAND] Parser

    static func extractCommands(from text: String) -> [String] {
        let pattern = #"\[COMMAND\]([\s\S]*?)\[/COMMAND\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map {
                String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Strips [COMMAND]...[/COMMAND] blocks from text, leaving only the prose.
    static func stripCommandBlocks(from text: String) -> String {
        let pattern = #"\[COMMAND\][\s\S]*?\[/COMMAND\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return cleaned
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if the command is safe and clickable (single-line, no editors, no heredoc).
    static func isValidCommand(_ cmd: String) -> Bool {
        let blocked = ["<<", "EOF", "EOT", "nano", "vim", "vi ", "emacs", "&&", "open -a", "osascript"]
        if cmd.contains("\n") { return false }
        return !blocked.contains { cmd.contains($0) }
    }

    /// Filters extracted commands, keeping only safe single-line ones.
    static func filterCommands(_ commands: [String]) -> [String] {
        commands.filter { isValidCommand($0) }
    }

    /// Builds a prompt to analyze a terminal error
    static func errorPrompt(command: String, errorOutput: String) -> String {
        return "Terminal error: '\(errorOutput)'. In one sentence: what went wrong and how to fix it."
    }

    private static func parseLamaCommand(_ args: [String]) -> LamaBuiltinCommand? {
        guard let head = args.first?.lowercased() else { return .help }

        switch head {
        case "help":
            return .help
        case "clear":
            return .clear
        case "intro":
            return .intro
        case "mode":
            guard let value = args.dropFirst().first?.lowercased() else { return nil }
            if value == "nl" || value == "chat" { return .mode(true) }
            if value == "cmd" || value == "terminal" { return .mode(false) }
            return nil
        case "theme":
            guard let value = args.dropFirst().first?.lowercased() else { return .themeList }
            if value == "list" { return .themeList }
            if value == "next" { return .themeNext }
            return .themeSet(value)
        case "accent", "color":
            guard let value = args.dropFirst().first?.lowercased() else { return .accentList }
            if value == "list" { return .accentList }
            return .accentSet(value)
        case "density":
            guard let value = args.dropFirst().first?.lowercased() else { return nil }
            return .densitySet(value)
        case "glass":
            guard let value = args.dropFirst().first?.lowercased() else { return nil }
            if value == "on" { return .glass(true) }
            if value == "off" { return .glass(false) }
            return nil
        default:
            return nil
        }
    }

    private static func tokenize(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?

        for char in input.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let activeQuote = quote, char == activeQuote {
                result.append(current)
                current = ""
                quote = nil
                continue
            }

            if quote == nil, char == "\"" || char == "'" {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                quote = char
                continue
            }

            if quote == nil, char.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
