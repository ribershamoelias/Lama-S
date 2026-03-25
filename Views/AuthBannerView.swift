import SwiftUI

/// A non-intrusive glass banner that appears over the terminal output
/// when an authentication event is detected.
/// Auto-dismisses after the user types (event resolved) or after a timeout.
struct AuthBannerView: View {
    let event: AuthEvent
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showDetail = false

    // URLs for "Learn more" per event kind
    private var learnMoreURL: URL? {
        switch event.kind {
        case .keychainAccess:
            return URL(string: "https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git")
        case .httpsCredential:
            return URL(string: "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github")
        case .sshPassphrase:
            return URL(string: "https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent")
        case .twoFactor:
            return URL(string: "https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa")
        case .sudoPassword, .genericPassword, .permissionDenied:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 10) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    // Title + safe badge
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.system(.callout, weight: .semibold))
                            .foregroundColor(.primary)

                        if event.isSafe {
                            Label("Safe", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    // Detail — collapsed by default, expandable
                    Text(event.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(showDetail ? nil : 2)
                        .animation(.easeInOut(duration: 0.2), value: showDetail)

                    // Action row
                    HStack(spacing: 10) {
                        Button(showDetail ? "Less" : "More info") {
                            withAnimation { showDetail.toggle() }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)

                        if let url = learnMoreURL {
                            Button("Learn more ↗") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor.opacity(0.8))
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
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
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(iconColor.opacity(0.35), lineWidth: 1)
                )
                // Frosted glass underneath the fill
                .background(
                    GlassView(material: .hudWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Slide in from top
        .offset(y: isVisible ? 0 : -20)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isVisible = true
            }
            // Auto-dismiss after 12 seconds — long enough to read, short enough to not annoy
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
    }

    private var iconName: String {
        switch event.kind {
        case .keychainAccess:  return "key.fill"
        case .httpsCredential: return "lock.fill"
        case .sshPassphrase:   return "key.horizontal.fill"
        case .twoFactor:       return "number.square.fill"
        case .sudoPassword:    return "person.badge.shield.checkmark.fill"
        case .genericPassword: return "lock.circle.fill"
        case .permissionDenied: return "lock.shield.fill"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .keychainAccess:  return .blue
        case .httpsCredential: return .blue
        case .sshPassphrase:   return .purple
        case .twoFactor:       return .orange
        case .sudoPassword:    return .yellow
        case .genericPassword: return .secondary
        case .permissionDenied: return .orange
        }
    }
}
