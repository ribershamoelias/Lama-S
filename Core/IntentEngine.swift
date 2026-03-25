import Foundation

/// Converts user intent into shell commands — locally, no AI needed.
/// Falls back to AI only for unknown/complex intents.
struct IntentEngine {

    enum Mode {
        case structure          // mkdir/touch only
        case explain            // explain <command>
        case code               // generate code for ...
        case workflow(GitIntent) // automated git workflow
    }

    enum GitIntent {
        case snapshot                   // "save", "checkpoint"
        case featureBranch(String)      // "add login feature" → feature/login
        case undo                       // "undo", "undo last commit"
        case push                       // "push"
        case commit(String)             // "commit <message>"
    }

    struct Result {
        let mode: Mode
        let commands: [String]      // ready-to-run shell commands
        let needsAI: Bool           // true = local rules didn't match
    }

    // MARK: - Public

    static func resolve(_ input: String) -> Result {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Explicit mode overrides
        if trimmed.hasPrefix("explain ") {
            return Result(mode: .explain, commands: [], needsAI: true)
        }
        if trimmed.hasPrefix("generate code") || trimmed.hasPrefix("create code") {
            return Result(mode: .code, commands: [], needsAI: true)
        }

        // Git workflow intents (no AI needed)
        if let intent = gitIntent(from: trimmed) {
            return Result(mode: .workflow(intent), commands: [], needsAI: false)
        }

        // Local structure rules
        if let commands = localMatch(trimmed) {
            return Result(mode: .structure, commands: commands, needsAI: false)
        }

        // Unknown → AI structure mode
        return Result(mode: .structure, commands: [], needsAI: true)
    }

    // MARK: - Git Intent Detection

    private static func gitIntent(from input: String) -> GitIntent? {
        if input == "undo" || input.contains("undo last") || input.contains("undo commit") {
            return .undo
        }
        if input == "push" || input == "git push" || input.contains("push to") {
            return .push
        }
        if input == "save" || input == "checkpoint" || input.contains("save progress") {
            return .snapshot
        }
        if input.hasPrefix("commit ") {
            let message = String(input.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? nil : .commit(message)
        }
        // "add <feature> feature" → feature branch
        if input.hasPrefix("add ") && (input.contains("feature") || input.contains("page") || input.contains("screen")) {
            let name = input
                .replacingOccurrences(of: "add ", with: "")
                .replacingOccurrences(of: " feature", with: "")
                .replacingOccurrences(of: " page", with: "")
                .replacingOccurrences(of: " screen", with: "")
                .trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .featureBranch(name)
        }
        return nil
    }

    // MARK: - Local Rule Engine

    private static func localMatch(_ input: String) -> [String]? {
        for (keywords, template) in rules {
            if keywords.contains(where: { input.contains($0) }) {
                return template(projectName(from: input))
            }
        }
        return nil
    }

    /// Extracts a clean project name from input, or returns a default.
    private static func projectName(from input: String) -> String {
        let stopWords = ["i", "want", "to", "create", "a", "an", "the", "with",
                         "and", "for", "my", "new", "build", "make", "setup",
                         "website", "app", "api", "project", "flutter", "react",
                         "node", "blog", "portfolio", "landing", "page", "swift"]
        let words = input.components(separatedBy: .whitespaces)
            .filter { !stopWords.contains($0) && $0.count > 1 }
        let name = words.first ?? "my-project"
        return name.replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
    }

    // MARK: - Rules Table
    // (keywords, command builder)

    private static let rules: [([String], (String) -> [String])] = [

        // Website / HTML
        (["website", "html", "landing page", "portfolio"],
         { name in [
            "mkdir \(name.isEmpty ? "my-website" : name)",
            "cd \(name.isEmpty ? "my-website" : name)",
            "mkdir css js assets",
            "touch index.html css/style.css js/script.js"
         ]}),

        // React
        (["react"],
         { _ in [
            "mkdir my-react-app",
            "cd my-react-app",
            "mkdir src public src/components src/pages",
            "touch src/index.js src/App.js public/index.html"
         ]}),

        // Flutter
        (["flutter"],
         { _ in [
            "mkdir my-flutter-app",
            "cd my-flutter-app",
            "mkdir lib lib/screens lib/widgets lib/models assets",
            "touch lib/main.dart lib/screens/home_screen.dart lib/widgets/app_bar.dart"
         ]}),

        // Node / Express API
        (["node", "express", "api", "backend", "server"],
         { _ in [
            "mkdir my-api",
            "cd my-api",
            "mkdir src routes controllers models middleware",
            "touch src/index.js src/app.js .env .gitignore"
         ]}),

        // Swift / iOS
        (["swift", "ios", "xcode"],
         { _ in [
            "mkdir my-ios-app",
            "cd my-ios-app",
            "mkdir Sources Sources/Models Sources/Views Sources/ViewModels Resources",
            "touch Sources/App.swift Sources/ContentView.swift"
         ]}),

        // Python
        (["python", "django", "flask", "fastapi"],
         { _ in [
            "mkdir my-python-app",
            "cd my-python-app",
            "mkdir src tests",
            "touch src/main.py requirements.txt .gitignore"
         ]}),

        // Blog
        (["blog"],
         { _ in [
            "mkdir my-blog",
            "cd my-blog",
            "mkdir posts pages public styles",
            "touch index.html styles/main.css posts/first-post.md"
         ]}),
    ]
}
