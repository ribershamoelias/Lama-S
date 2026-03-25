import Foundation

// MARK: - Auth Event Model

/// Describes a detected authentication-related event in terminal output.
struct AuthEvent: Equatable {
    let kind: Kind
    let title: String
    let detail: String
    let isSafe: Bool        // whether we can tell the user this is a normal/safe operation

    enum Kind: Equatable {
        case keychainAccess
        case httpsCredential
        case sshPassphrase
        case twoFactor
        case sudoPassword
        case genericPassword
        case permissionDenied   // macOS Full Disk Access / sandbox restriction
    }
}

// MARK: - Detector

/// Scans a single line of terminal output and returns an AuthEvent if one is detected.
/// Never reads, stores, or logs any credential values — only detects the prompt pattern.
struct AuthEventDetector {

    // Each rule: (regex pattern, event factory)
    private static let rules: [(pattern: String, make: () -> AuthEvent)] = [
        (
            // git-credential-osxkeychain writing to keychain
            #"git-credential-osxkeychain|osxkeychain"#,
            {
                AuthEvent(
                    kind: .keychainAccess,
                    title: "GitHub Credential Access",
                    detail: "Git is requesting access to your saved GitHub credentials via macOS Keychain. This is required to authenticate your push or pull over HTTPS.",
                    isSafe: true
                )
            }
        ),
        (
            // HTTPS username/password prompt
            #"(?i)username for .*(github|gitlab|bitbucket)|password for .*https://"#,
            {
                AuthEvent(
                    kind: .httpsCredential,
                    title: "Git HTTPS Authentication",
                    detail: "Git needs your username and password to access the remote repository over HTTPS. Consider setting up an SSH key or a credential helper to avoid this in the future.",
                    isSafe: true
                )
            }
        ),
        (
            // SSH passphrase
            #"(?i)enter passphrase for key|bad passphrase"#,
            {
                AuthEvent(
                    kind: .sshPassphrase,
                    title: "SSH Key Passphrase",
                    detail: "Your SSH key is protected by a passphrase. Enter it to authenticate. You can add your key to ssh-agent to avoid this prompt: ssh-add ~/.ssh/id_ed25519",
                    isSafe: true
                )
            }
        ),
        (
            // Two-factor / OTP
            #"(?i)two-factor|2fa|one-time password|otp|authenticator"#,
            {
                AuthEvent(
                    kind: .twoFactor,
                    title: "Two-Factor Authentication",
                    detail: "The remote server is requesting a one-time code from your authenticator app. Open your authenticator and enter the 6-digit code.",
                    isSafe: true
                )
            }
        ),
        (
            // sudo password
            #"(?i)^\[sudo\] password for |password:|sudo.*password"#,
            {
                AuthEvent(
                    kind: .sudoPassword,
                    title: "Administrator Password Required",
                    detail: "This command requires administrator (sudo) privileges. macOS is asking for your login password to proceed. Your password is never stored by Lama Terminal.",
                    isSafe: true
                )
            }
        ),
        (
            // macOS permission / sandbox denial
            #"(?i)operation not permitted|permission denied|access denied|sandbox.*denied|not allowed to|cannot open|unable to open"#,
            {
                AuthEvent(
                    kind: .permissionDenied,
                    title: "macOS Permission Required",
                    detail: "macOS blocked this operation because Lama Terminal does not have permission to access that file or folder. You can fix this by granting Full Disk Access in System Settings.",
                    isSafe: false
                )
            }
        ),
        (
            // Generic password prompt fallback
            #"(?i)^password:\s*$|enter password"#,
            {
                AuthEvent(
                    kind: .genericPassword,
                    title: "Password Required",
                    detail: "A password is being requested. Lama Terminal does not capture or log what you type — it goes directly to the running process.",
                    isSafe: true
                )
            }
        ),
    ]

    /// Returns an AuthEvent if the line matches any known authentication pattern, nil otherwise.
    static func detect(in line: String) -> AuthEvent? {
        for rule in rules {
            if line.range(of: rule.pattern,
                          options: [.regularExpression, .caseInsensitive]) != nil {
                return rule.make()
            }
        }
        return nil
    }
}
