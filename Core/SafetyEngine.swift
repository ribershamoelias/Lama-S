import Foundation

/// Classifies commands by risk level using pattern matching.
/// Runs synchronously — no AI needed for known dangerous patterns.
struct SafetyEngine {

    struct Rule {
        let pattern: String          // regex
        let risk: RiskLevel
        let reason: String
    }

    private static let rules: [Rule] = [
        // Critical — immediate data loss / system damage
        Rule(pattern: #"rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r"#,
             risk: .high, reason: "Recursive force delete — can permanently destroy files"),
        Rule(pattern: #"rm\s+.*\s+/"#,
             risk: .high, reason: "Deleting from root directory"),
        Rule(pattern: #":\(\)\{.*\}.*:"#,
             risk: .high, reason: "Fork bomb — will crash your system"),
        Rule(pattern: #"dd\s+if=.*of=/dev/"#,
             risk: .high, reason: "Writing directly to a disk device"),
        Rule(pattern: #"mkfs\."#,
             risk: .high, reason: "Formatting a filesystem"),
        Rule(pattern: #"chmod\s+[0-9]*7[0-9]*7\s+/"#,
             risk: .high, reason: "Making root world-writable"),

        // Medium — elevated privileges or broad changes
        Rule(pattern: #"sudo\s+rm"#,
             risk: .medium, reason: "Deleting files as root"),
        Rule(pattern: #"sudo\s+chmod"#,
             risk: .medium, reason: "Changing permissions as root"),
        Rule(pattern: #"curl.*\|\s*(ba)?sh"#,
             risk: .medium, reason: "Piping remote script directly to shell"),
        Rule(pattern: #"wget.*\|\s*(ba)?sh"#,
             risk: .medium, reason: "Piping remote script directly to shell"),
        Rule(pattern: #"chmod\s+777"#,
             risk: .medium, reason: "Making files world-writable"),
        Rule(pattern: #"sudo\s+.*"#,
             risk: .medium, reason: "Running command with root privileges"),
    ]

    /// Returns a SafetyWarning if the command matches any rule, nil if safe.
    static func analyze(_ command: String) -> SafetyWarning? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        for rule in rules {
            if let _ = trimmed.range(of: rule.pattern, options: [.regularExpression, .caseInsensitive]) {
                return SafetyWarning(command: trimmed, risk: rule.risk, reason: rule.reason)
            }
        }
        return nil
    }
}
