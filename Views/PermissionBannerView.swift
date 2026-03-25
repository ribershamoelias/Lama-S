import SwiftUI
import AppKit

/// Shown when the terminal detects an "Operation not permitted" or similar
/// macOS permission error. Explains the issue in plain language and guides
/// the user to the correct System Settings panel.
struct PermissionBannerView: View {
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("macOS Permission Required")
                            .font(TerminalTheme.ui(13, weight: .semibold))
                            .foregroundColor(TerminalTheme.textPrimary)

                        Text("ACCESS BLOCKED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    Text("macOS prevented this operation. The app doesn't have permission to access that file or folder.")
                        .font(TerminalTheme.ui(12))
                        .foregroundColor(TerminalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Expandable fix steps
                    Button(showSteps ? "Hide steps" : "How to fix this →") {
                        withAnimation(.easeInOut(duration: 0.2)) { showSteps.toggle() }
                    }
                    .font(TerminalTheme.ui(11, weight: .semibold))
                    .foregroundColor(.orange)
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    if showSteps {
                        fixSteps
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer(minLength: 8)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundColor(TerminalTheme.textSecondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.09, blue: 0.06).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
                .background(
                    GlassView(material: .hudWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 5)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .offset(y: isVisible ? 0 : -24)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                isVisible = true
            }
            // Auto-dismiss after 20s — long enough to read the steps
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { dismiss() }
        }
    }

    // MARK: - Fix Steps

    private var fixSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.3).padding(.vertical, 4)

            Text("Grant Full Disk Access to Lama Terminal:")
                .font(TerminalTheme.ui(11, weight: .semibold))
                .foregroundColor(TerminalTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                step(n: 1, text: "Open  System Settings")
                step(n: 2, text: "Go to Privacy & Security")
                step(n: 3, text: "Scroll down to Full Disk Access")
                step(n: 4, text: "Toggle ON next to Lama Terminal")
                step(n: 5, text: "Restart Lama Terminal")
            }

            HStack(spacing: 10) {
                // Deep-link directly to the Privacy pane
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .font(TerminalTheme.ui(11, weight: .medium))

                Button("Learn more ↗") {
                    NSWorkspace.shared.open(
                        URL(string: "https://support.apple.com/guide/mac-help/allow-apps-to-detect-input-mchl4cedafb6/mac")!
                    )
                }
                .buttonStyle(.plain)
                .font(TerminalTheme.ui(11))
                .foregroundColor(.orange.opacity(0.8))
            }
            .padding(.top, 4)
        }
    }

    private func step(n: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
                .frame(width: 16, height: 16)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            Text(text)
                .font(TerminalTheme.ui(12))
                .foregroundColor(TerminalTheme.textSecondary)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.22)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onDismiss() }
    }
}
