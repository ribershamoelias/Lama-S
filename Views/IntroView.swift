import SwiftUI

struct IntroView: View {
    @ObservedObject var appearance: TerminalAppearance

    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var commandsOpacity: Double = 0
    @State private var titleOffset: CGFloat = 14
    @State private var glow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appearance.background.opacity(0.94),
                    appearance.secondaryBackground.opacity(0.42),
                    appearance.background.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            backgroundBeams

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    Text("RIBER SHAMO ELIAS")
                        .font(TerminalTheme.ui(10, weight: .semibold))
                        .tracking(3.2)
                        .foregroundColor(appearance.textSecondary.opacity(0.72))
                        .opacity(subtitleOpacity)

                    Text("LAMA S")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .tracking(10)
                        .foregroundStyle(appearance.heroGradient)
                        .shadow(color: appearance.textAccent.opacity(glow ? 0.14 : 0.04), radius: glow ? 14 : 4)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)

                    Text("Terminal. AI help. Git workflow. Nothing extra.")
                        .font(TerminalTheme.ui(16))
                        .foregroundColor(appearance.textSecondary.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .opacity(subtitleOpacity)
                }

                VStack(spacing: 8) {
                    introRow(command: "lama help", note: "built-in commands")
                    introRow(command: "lama theme next", note: "switch style")
                    introRow(command: "mkcd project", note: "quick start")
                }
                .opacity(commandsOpacity)

                Spacer()

                Text("Press any key or type a command to continue")
                    .font(TerminalTheme.ui(11, weight: .medium))
                    .foregroundColor(appearance.textSecondary.opacity(0.72))
                    .opacity(commandsOpacity)
                    .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 54)
        }
        .onAppear { runIntroAnimation() }
    }

    private var backgroundBeams: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [appearance.textAccent.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 360, height: 1)
                .blur(radius: 1)
                .offset(x: -80, y: -120)

            Circle()
                .fill(appearance.textAccent.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: 260, y: -210)
        }
        .allowsHitTesting(false)
    }

    private func introRow(command: String, note: String) -> some View {
        HStack(spacing: 16) {
            Text(verbatim: command)
                .font(TerminalTheme.mono(13, weight: .medium))
                .foregroundColor(appearance.textInput)
                .frame(width: 170, alignment: .trailing)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 14, height: 1)

            Text(note)
                .font(TerminalTheme.ui(13))
                .foregroundColor(appearance.textSecondary)
                .frame(width: 112, alignment: .leading)
        }
    }

    private func runIntroAnimation() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(0.08)) {
            titleOpacity = 1
            titleOffset = 0
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.28)) {
            subtitleOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.38).delay(0.5)) {
            commandsOpacity = 1
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}
