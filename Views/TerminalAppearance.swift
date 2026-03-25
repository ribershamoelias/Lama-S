import SwiftUI
import Combine

final class TerminalAppearance: ObservableObject {
    enum ThemePreset: String, CaseIterable {
        case obsidian
        case dune
        case matrix

        var title: String { rawValue.capitalized }
    }

    enum AccentPreset: String, CaseIterable {
        case ice
        case amber
        case lime
        case coral

        var title: String { rawValue.capitalized }

        var color: Color {
            switch self {
            case .ice: return Color(red: 0.42, green: 0.82, blue: 1.00)
            case .amber: return Color(red: 1.00, green: 0.72, blue: 0.29)
            case .lime: return Color(red: 0.53, green: 0.95, blue: 0.49)
            case .coral: return Color(red: 1.00, green: 0.48, blue: 0.43)
            }
        }
    }

    enum DensityPreset: String, CaseIterable {
        case compact
        case comfortable
        case spacious

        var title: String { rawValue.capitalized }
    }

    @Published var theme: ThemePreset {
        didSet { save(theme.rawValue, for: Keys.theme) }
    }
    @Published var accent: AccentPreset {
        didSet { save(accent.rawValue, for: Keys.accent) }
    }
    @Published var density: DensityPreset {
        didSet { save(density.rawValue, for: Keys.density) }
    }
    @Published var glassEnabled: Bool {
        didSet { defaults.set(glassEnabled, forKey: Keys.glass) }
    }

    private let defaults = UserDefaults.standard

    init() {
        theme = ThemePreset(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .obsidian
        accent = AccentPreset(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .ice
        density = DensityPreset(rawValue: defaults.string(forKey: Keys.density) ?? "") ?? .comfortable
        glassEnabled = defaults.object(forKey: Keys.glass) as? Bool ?? true
    }

    func setTheme(named value: String) -> Bool {
        guard let preset = ThemePreset.allCases.first(where: { $0.rawValue == value.lowercased() }) else { return false }
        theme = preset
        return true
    }

    func setAccent(named value: String) -> Bool {
        guard let preset = AccentPreset.allCases.first(where: { $0.rawValue == value.lowercased() }) else { return false }
        accent = preset
        return true
    }

    func setDensity(named value: String) -> Bool {
        guard let preset = DensityPreset.allCases.first(where: { $0.rawValue == value.lowercased() }) else { return false }
        density = preset
        return true
    }

    func cycleTheme() {
        guard let current = ThemePreset.allCases.firstIndex(of: theme) else { return }
        theme = ThemePreset.allCases[(current + 1) % ThemePreset.allCases.count]
    }

    var background: Color {
        switch theme {
        case .obsidian: return Color(red: 0.04, green: 0.05, blue: 0.08)
        case .dune: return Color(red: 0.11, green: 0.08, blue: 0.06)
        case .matrix: return Color(red: 0.02, green: 0.08, blue: 0.05)
        }
    }

    var secondaryBackground: Color {
        switch theme {
        case .obsidian: return Color(red: 0.08, green: 0.10, blue: 0.15)
        case .dune: return Color(red: 0.16, green: 0.12, blue: 0.09)
        case .matrix: return Color(red: 0.04, green: 0.12, blue: 0.08)
        }
    }

    var chromeBackground: Color {
        secondaryBackground.opacity(glassEnabled ? 0.36 : 0.92)
    }

    var panelBackground: Color {
        Color.white.opacity(glassEnabled ? 0.02 : 0.016)
    }

    var overlayStroke: Color {
        Color.white.opacity(glassEnabled ? 0.08 : 0.06)
    }

    var lineHover: Color {
        Color.white.opacity(0.04)
    }

    var textPrimary: Color {
        switch theme {
        case .obsidian, .matrix: return Color(red: 0.94, green: 0.96, blue: 0.98)
        case .dune: return Color(red: 0.98, green: 0.94, blue: 0.88)
        }
    }

    var textSecondary: Color {
        switch theme {
        case .obsidian: return Color(red: 0.57, green: 0.63, blue: 0.70)
        case .dune: return Color(red: 0.69, green: 0.61, blue: 0.54)
        case .matrix: return Color(red: 0.52, green: 0.74, blue: 0.61)
        }
    }

    var textInput: Color { accent.color }
    var textAccent: Color { accent.color }
    var textError: Color { Color(red: 1.00, green: 0.42, blue: 0.44) }
    var textWarning: Color { Color(red: 0.99, green: 0.80, blue: 0.31) }
    var textSystem: Color { accent.color.opacity(0.9) }
    var textAI: Color { Color(red: 0.54, green: 0.96, blue: 0.78) }

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                background,
                secondaryBackground.opacity(0.38),
                background.opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.color.opacity(0.95),
                Color.white.opacity(0.8),
                accent.color.opacity(0.45)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var lineSpacing: CGFloat {
        switch density {
        case .compact: return 3
        case .comfortable: return 5
        case .spacious: return 7
        }
    }

    var linePaddingH: CGFloat {
        switch density {
        case .compact: return 14
        case .comfortable: return 18
        case .spacious: return 22
        }
    }

    var linePaddingV: CGFloat {
        switch density {
        case .compact: return 10
        case .comfortable: return 14
        case .spacious: return 18
        }
    }

    var inputPaddingH: CGFloat {
        switch density {
        case .compact: return 14
        case .comfortable: return 18
        case .spacious: return 22
        }
    }

    var inputPaddingV: CGFloat {
        switch density {
        case .compact: return 10
        case .comfortable: return 13
        case .spacious: return 16
        }
    }

    private func save(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let theme = "lama.appearance.theme"
        static let accent = "lama.appearance.accent"
        static let density = "lama.appearance.density"
        static let glass = "lama.appearance.glass"
    }
}
