import SwiftUI
import AppKit

@main
struct LamaTerminalApp: App {
    @StateObject private var aiSettings = AISettingsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView(aiSettings: aiSettings)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LAMA S") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "LAMA S",
                        .applicationVersion: "Version 1.0 (Build 1)",
                        .credits: aboutCredits
                    ])
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            AISettingsView(settings: aiSettings)
        }
    }

    private var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        return NSAttributedString(
            string: "LAMA S\nby Riber Shamo Elias\n\nModern macOS terminal with AI help, command guidance, and Git workflows.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
    }
}
