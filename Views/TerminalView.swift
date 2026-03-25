import SwiftUI
import AppKit

struct TerminalView: View {
    @ObservedObject var engine: TerminalEngine
    @ObservedObject var aiSettings: AISettingsStore
    @Binding var inputText: String
    @Binding var lastCommand: String

    let onSubmit: () -> Void
    let onExplain: () -> Void
    let onNLConvert: () -> Void

    @State private var suggestions: [String] = []

    private var appearance: TerminalAppearance { engine.appearance }

    var body: some View {
        VStack(spacing: 0) {
            header
            breadcrumb
            outputArea
            if !suggestions.isEmpty {
                autocompleteBar
            }
            inputBar
        }
        .background(Color.clear)
        .onChange(of: inputText) { _, val in updateSuggestions(val) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("LAMA S")
                        .font(TerminalTheme.ui(11, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundColor(appearance.textPrimary)

                Text(engine.isNLMode ? "Natural language workspace" : "Live shell workspace")
                    .font(TerminalTheme.ui(10))
                    .foregroundColor(appearance.textSecondary.opacity(0.68))
            }

            Spacer()

            if !engine.currentDirectory.isEmpty {
                Text((engine.currentDirectory as NSString).lastPathComponent.isEmpty ? engine.currentDirectory : (engine.currentDirectory as NSString).lastPathComponent)
                    .font(TerminalTheme.mono(10))
                    .foregroundColor(appearance.textSecondary.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.02))
                            .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                    )
            }

            headerBadge(aiSettings.resolvedProviderTitle)
            headerBadge(engine.isNLMode ? "Chat" : "Terminal")

            SettingsLink {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(appearance.textSecondary.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("Open AI settings")
        }
        .padding(.horizontal, appearance.linePaddingH)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.012), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.08)), alignment: .bottom)
    }

    private func headerBadge(_ label: String) -> some View {
        Text(label)
            .font(TerminalTheme.ui(10))
            .foregroundColor(appearance.textSecondary.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.018))
                    .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
            )
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let parts = breadcrumbParts
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    Button(part.name) {
                        engine.cdInto(part.path)
                    }
                    .font(TerminalTheme.ui(11, weight: i == parts.count - 1 ? .semibold : .regular))
                    .foregroundColor(i == parts.count - 1 ? appearance.textPrimary : appearance.textSecondary)
                    .buttonStyle(.plain)

                    if i < parts.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(appearance.textSecondary.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, appearance.linePaddingH)
            .padding(.vertical, 8)
        }
        .background(appearance.secondaryBackground.opacity(0.18))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.06)), alignment: .bottom)
    }

    private struct BreadcrumbPart { let name: String; let path: String }

    private var breadcrumbParts: [BreadcrumbPart] {
        let home = NSHomeDirectory()
        let dir = engine.currentDirectory
        let display = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
        var parts: [BreadcrumbPart] = []
        var accumulated = ""
        for segment in display.split(separator: "/", omittingEmptySubsequences: false) {
            let seg = String(segment)
            if seg == "~" {
                accumulated = home
                parts.append(BreadcrumbPart(name: "~", path: home))
            } else if !seg.isEmpty {
                accumulated += "/" + seg
                parts.append(BreadcrumbPart(name: seg, path: accumulated))
            }
        }
        return parts
    }

    private var autocompleteBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { name in
                    Button(action: { applySuggestion(name) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundColor(appearance.textAccent)
                            Text(verbatim: name)
                                .font(TerminalTheme.mono(12))
                                .foregroundColor(appearance.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, appearance.linePaddingH)
            .padding(.vertical, 8)
        }
        .background(appearance.secondaryBackground.opacity(0.2))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.06)), alignment: .top)
    }

    private func updateSuggestions(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "cd" {
            suggestions = engine.directorySuggestions(for: "")
        } else if t.hasPrefix("cd ") {
            let prefix = String(t.dropFirst(3))
            suggestions = engine.directorySuggestions(for: prefix)
        } else {
            suggestions = []
        }
    }

    private func applySuggestion(_ name: String) {
        inputText = "cd \(name)"
        suggestions = []
        onSubmit()
    }

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: appearance.lineSpacing) {
                    ForEach(engine.lines) { line in
                        TerminalLineView(line: line, appearance: appearance, onCdClick: { path in
                            engine.cdInto(path)
                        })
                        .id(line.id)
                    }
                }
                .padding(.horizontal, appearance.linePaddingH)
                .padding(.top, appearance.linePaddingV)
                .padding(.bottom, 10)

                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: engine.lines.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    appearance.background.opacity(0.32),
                    appearance.background.opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            if let event = engine.authEvent {
                if event.kind == .permissionDenied {
                    PermissionBannerView { engine.authEvent = nil }
                        .padding(.top, 6)
                        .zIndex(10)
                } else {
                    AuthBannerView(event: event) { engine.authEvent = nil }
                        .padding(.top, 6)
                        .zIndex(10)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button(engine.isNLMode ? "NL" : ">") {
                withAnimation(.easeInOut(duration: 0.18)) { engine.isNLMode.toggle() }
                inputText = ""
            }
            .font(TerminalTheme.mono(13, weight: .bold))
            .foregroundColor(engine.isNLMode ? appearance.textAI : appearance.textInput)
            .buttonStyle(.plain)
            .help(engine.isNLMode ? "Natural Language Mode" : "Command Mode")
            .frame(width: 28, alignment: .leading)

            TextField(
                engine.isNLMode ? "Ask something or describe a task..." : "Type a command or `lama help`...",
                text: $inputText
            )
            .font(TerminalTheme.mono(13))
            .textFieldStyle(.plain)
            .foregroundColor(appearance.textPrimary)
            .onSubmit { onSubmit() }
            .onChange(of: inputText) {
                if engine.authEvent != nil { engine.authEvent = nil }
            }

            if !inputText.isEmpty {
                actionButton
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .padding(.horizontal, appearance.inputPaddingH)
        .padding(.vertical, appearance.inputPaddingV)
        .background(appearance.secondaryBackground.opacity(0.22))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.08)), alignment: .top)
    }

    @ViewBuilder
    private var actionButton: some View {
        if engine.isNLMode {
            Button("Convert") { onNLConvert() }
                .buttonStyle(.borderedProminent)
                .tint(appearance.textAI)
                .controlSize(.small)
                .font(TerminalTheme.ui(11))
        } else {
            Button("Explain") { onExplain() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(TerminalTheme.ui(11))
        }
    }
}

struct TerminalLineView: View {
    let line: TerminalLine
    let appearance: TerminalAppearance
    var onCdClick: ((String) -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Group {
            if line.type == .directory {
                DirectoryLineView(name: line.content, path: line.metadata ?? line.content, appearance: appearance) {
                    onCdClick?(line.metadata ?? line.content)
                }
            } else if line.type == .file {
                FileLineView(name: line.content, path: line.metadata ?? line.content, appearance: appearance)
            } else if line.type == .input {
                inputLine
            } else if hasInteractivePaths {
                segmentedLine
            } else {
                plainLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(line.type == .directory || line.type == .file ? Color.clear : (isHovered ? appearance.lineHover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var inputLine: some View {
        HStack(spacing: 0) {
            Text(verbatim: "❯ ")
                .font(TerminalTheme.mono(13, weight: .medium))
                .foregroundColor(appearance.textInput)
            Text(verbatim: line.content)
                .font(TerminalTheme.mono(13))
                .foregroundColor(appearance.textPrimary)
                .textSelection(.enabled)
        }
    }

    private var plainLine: some View {
        Text(verbatim: line.content)
            .font(TerminalTheme.mono(13))
            .foregroundColor(lineColor)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
    }

    private var segmentedLine: some View {
        FlowLayout(spacing: 3) {
            ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let str):
                    Text(verbatim: str)
                        .font(TerminalTheme.mono(13))
                        .foregroundColor(lineColor)
                        .textSelection(.enabled)
                case .path(let path, let isDir):
                    InteractivePathView(path: path, isDirectory: isDir, appearance: appearance)
                }
            }
        }
    }

    private var hasInteractivePaths: Bool {
        line.segments.contains { if case .path = $0 { return true }; return false }
    }

    private var lineColor: Color {
        switch line.type {
        case .input: return appearance.textInput
        case .output: return appearance.textPrimary
        case .error: return appearance.textError
        case .system: return appearance.textSystem
        case .directory, .file: return appearance.textAccent
        case .ai: return appearance.textAI
        }
    }
}

struct DirectoryLineView: View {
    let name: String
    let path: String
    let appearance: TerminalAppearance
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(appearance.textAccent)
                Text(verbatim: name)
                    .font(TerminalTheme.mono(13))
                    .foregroundColor(appearance.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? appearance.textAccent.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? appearance.overlayStroke : Color.white.opacity(0.06), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(path)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        })
        .contextMenu {
            Button("cd \(name)") { onTap() }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

struct FileLineView: View {
    let name: String
    let path: String
    let appearance: TerminalAppearance
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundColor(appearance.textSecondary)
            Text(verbatim: name)
                .font(TerminalTheme.mono(13))
                .foregroundColor(appearance.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .help(path)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }

    private var fileIcon: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go", "rs", "rb", "java", "c", "cpp", "sh":
            return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo.fill"
        case "zip", "tar", "gz", "rar":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        default:
            return "doc.fill"
        }
    }
}

struct InteractivePathView: View {
    let path: String
    let isDirectory: Bool
    let appearance: TerminalAppearance
    @State private var isHovered = false

    private var name: String { (path as NSString).lastPathComponent }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundColor(isDirectory ? appearance.textAccent : appearance.textSecondary)
            Text(verbatim: name)
                .font(TerminalTheme.mono(12))
                .foregroundColor(appearance.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? appearance.textAccent.opacity(0.16) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isHovered ? appearance.overlayStroke : Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help("\(path)\nClick to open in Finder")
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += rowH + spacing; totalH = y; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: totalH + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
