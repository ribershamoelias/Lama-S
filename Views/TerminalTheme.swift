import SwiftUI

enum TerminalTheme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let inputBar = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let lineHover = Color.white.opacity(0.04)
    static let textPrimary = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let textInput = Color(red: 0.45, green: 0.95, blue: 0.55)
    static let textError = Color(red: 1.00, green: 0.38, blue: 0.38)
    static let textWarning = Color(red: 1.00, green: 0.80, blue: 0.30)
    static let textSystem = Color(red: 0.60, green: 0.75, blue: 1.00)
    static let textAccent = Color(red: 0.40, green: 0.75, blue: 1.00)

    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func ui(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
