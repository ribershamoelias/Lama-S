import Foundation
import Combine
import SwiftUI

final class TerminalEngine: ObservableObject {

    @Published var lines: [TerminalLine] = []
    @Published var lastError: String?
    @Published var currentDirectory: String = NSHomeDirectory()
    @Published var authEvent: AuthEvent?
    @Published var hasReceivedOutput: Bool = false
    @Published var isNLMode: Bool = false
    @Published var lastAIChat: AIChatResponse?
    @Published var introToken = UUID()

    let appearance = TerminalAppearance()

    let ai = AIService()

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "lama.pty", qos: .userInteractive)

    // Raw byte buffer — we decode after we have complete UTF-8 sequences
    private var rawBuffer = Data()
    private var lineBuffer = ""
    private var flushWorkItem: DispatchWorkItem?
    // Last command sent — used to suppress PTY echo
    private var lastSentCommand: String?

    // MARK: - Public API

    func start() { spawnShell() }

    func send(_ command: String) {
        let trimmedCmd = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedCmd.isEmpty else { return }

        if let builtin = CommandParser.parseBuiltin(trimmedCmd) {
            DispatchQueue.main.async { self.emit(trimmedCmd, type: .input) }
            handleBuiltin(builtin)
            return
        }

        // ✅ NL MODE — never touches the shell
        if isNLMode {
            DispatchQueue.main.async { self.emit(trimmedCmd, type: .input) }
            Task {
                let response = await ai.chat(trimmedCmd)
                await MainActor.run {
                    // Emit prose as AI line
                    if !response.prose.isEmpty {
                        self.lines.append(TerminalLine(content: response.prose, type: .ai))
                    }
                    // Commands are handled by ContentView via aiState — signal via lastAIChat
                    self.lastAIChat = response
                }
            }
            return
        }

        // TERMINAL MODE — shell only
        guard masterFD >= 0 else {
            emitSystem("❌ Shell not ready")
            return
        }

        // All cd variants go through smart handler
        if trimmedCmd == "cd" || trimmedCmd.hasPrefix("cd ") {
            DispatchQueue.main.async { self.emit(trimmedCmd, type: .input) }
            handleSmartCD(trimmedCmd)
            return
        }

        // ls — render via FileManager, never rely on shell output
        if trimmedCmd == "ls" || trimmedCmd == "ls -la" || trimmedCmd == "ls -l" {
            DispatchQueue.main.async { self.emit(trimmedCmd, type: .input) }
            showDirectoryContents()
            return
        }

        // Natural language in CMD mode — route to AI, never touch shell
        if isNaturalLanguage(trimmedCmd) {
            DispatchQueue.main.async { self.emit(trimmedCmd, type: .input) }
            Task {
                let response = await ai.chat(trimmedCmd)
                await MainActor.run {
                    if !response.prose.isEmpty {
                        self.lines.append(TerminalLine(content: response.prose, type: .ai))
                    }
                    self.lastAIChat = response
                }
            }
            return
        }

        lastSentCommand = trimmedCmd
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.lastSentCommand == trimmedCmd { self?.lastSentCommand = nil }
        }
        DispatchQueue.main.async { self.emit(command, type: .input) }
        let payload = command + "\n"
        payload.withCString { ptr in _ = write(masterFD, ptr, strlen(ptr)) }
        updateDirectoryIfNeeded(command)
    }

    func sendSilent(_ command: String) {
        guard masterFD >= 0 else { return }
        let payload = command + "\n"
        payload.withCString { ptr in _ = write(masterFD, ptr, strlen(ptr)) }
        updateDirectoryIfNeeded(command)
    }

    func stop() {
        flushWorkItem?.cancel()
        readSource?.cancel()
        if childPID > 0 { kill(childPID, SIGTERM) }
        if masterFD >= 0 { close(masterFD) }
    }

    // MARK: - Shell spawn

    private func spawnShell() {
        masterFD = posix_openpt(O_RDWR)
        guard masterFD >= 0, grantpt(masterFD) == 0, unlockpt(masterFD) == 0 else {
            emitSystem("❌ Failed to open PTY (errno=\(errno))")
            return
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        childPID = shell.withCString { pty_spawn_shell(masterFD, $0) }
        guard childPID > 0 else {
            emitSystem("❌ Failed to spawn shell (errno=\(errno))")
            return
        }
        emitSystem("▶ Shell PID: \(childPID)")
        startReading()
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.injectZshHooks()
            // Force initial output so UI is never empty
            let init_ = "echo 'Lama Terminal Ready'\n"
            init_.withCString { ptr in _ = write(self!.masterFD, ptr, strlen(ptr)) }
        }
    }

    /// Disables bracketed paste (source of [?2004h/l artifacts) and clears RPROMPT.
    /// We do NOT override PROMPT or precmd — that breaks command execution.
    private func injectZshHooks() {
        let setup = "unset zle_bracketed_paste; RPROMPT=''\n"
        setup.withCString { ptr in _ = write(masterFD, ptr, strlen(ptr)) }
    }

    // MARK: - PTY reading

    private func startReading() {
        readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        readSource?.setEventHandler { [weak self] in self?.readAvailable() }
        readSource?.resume()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(masterFD, &buf, buf.count)
        guard n > 0 else { return }

        rawBuffer.append(contentsOf: buf.prefix(n))

        // Decode as much valid UTF-8 as possible; keep incomplete sequences in rawBuffer
        let (decoded, remainder) = decodeUTF8Greedy(rawBuffer)
        rawBuffer = remainder

        let clean = stripControlSequences(decoded)
        #if DEBUG
        print("[PTY RAW]", decoded.debugDescription)
        #endif
        lineBuffer += clean
        drainLineBuffer(flushRemainder: false)

        // Flush any partial line (prompt) after a short idle window
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.drainLineBuffer(flushRemainder: true)
        }
        flushWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.06, execute: item)
    }

    // MARK: - Line assembly

    private func drainLineBuffer(flushRemainder: Bool) {
        var remaining = lineBuffer
        var completed: [String] = []

        // Split on \n, strip trailing \r from each segment
        while let nl = remaining.range(of: "\n") {
            var seg = String(remaining[..<nl.lowerBound])
            if seg.hasSuffix("\r") { seg = String(seg.dropLast()) }
            completed.append(seg)
            remaining = String(remaining[nl.upperBound...])
        }

        // Bare \r without \n = overwrite (progress bars) — keep only last part
        if remaining.contains("\r") {
            remaining = remaining.components(separatedBy: "\r").last ?? remaining
        }

        if flushRemainder, !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completed.append(remaining)
            remaining = ""
        }

        lineBuffer = remaining
        guard !completed.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for seg in completed { self.processLine(seg) }
        }
    }

    // MARK: - Line processing

    private func processLine(_ raw: String) {
        guard !raw.isEmpty else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Internal directory marker — update currentDirectory, NO display here
        // (breadcrumb in the input bar handles the visual feedback)
        if trimmed.contains("__LAMADIR__") {
            let parts = trimmed.components(separatedBy: "__LAMADIR__")
            if parts.count >= 3 {
                let dir = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !dir.isEmpty { currentDirectory = dir }
            }
            return
        }

        // Suppress PTY echo of the command we just sent
        if let last = lastSentCommand, trimmed == last {
            lastSentCommand = nil
            return
        }

        // Drop shell prompts silently — we render our own input line
        if isShellPrompt(trimmed) { return }

        // Drop unresolved shell substitutions (e.g. "$(pwd)", "$(ls)") — never real output
        if trimmed.contains("$(") { return }

        if trimmed.isEmpty { return }

        hasReceivedOutput = true
        let isErr = isErrorLine(trimmed)
        emit(raw, type: isErr ? .error : .output)
        if isErr { lastError = raw }

        if let event = AuthEventDetector.detect(in: raw) {
            authEvent = event
        }
    }

    /// Heuristic: is this line just a shell prompt with no real content?
    private func isShellPrompt(_ s: String) -> Bool {
        // Bare sigils
        if s == "%" || s == "$" || s == "#" || s == "❯" || s == ">" { return true }
        // zsh default prompt patterns: "user@host dir %" or just ends with " %" / " $"
        // Only treat as prompt if short enough to not be real output
        if s.count < 80 {
            if s.hasSuffix(" %") || s.hasSuffix(" $") || s.hasSuffix(" #") { return true }
            // zsh with path: "~/Desktop %"
            if s.hasSuffix("%") && !s.contains(" ") == false { return true }
        }
        return false
    }

    private func isErrorLine(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("error:") || l.contains("command not found")
            || l.contains("permission denied") || l.contains("no such file")
    }

    // MARK: - ANSI / control sequence stripping

    /// Removes all ANSI/VT escape sequences and control characters that should not
    /// appear in rendered output.
    private func stripControlSequences(_ s: String) -> String {
        var result = s

        // 1. OSC sequences: ESC ] ... BEL  or  ESC ] ... ESC \
        result = result.replacingOccurrences(
            of: "\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)",
            with: "", options: .regularExpression)

        // 2. CSI sequences: ESC [ ... final-byte (covers colors, cursor, bracketed paste)
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            with: "", options: .regularExpression)

        // 3. DCS / PM / APC / SOS: ESC P/X/^ /_ ... ESC \
        result = result.replacingOccurrences(
            of: "\u{1B}[P X\\^_][^\u{1B}]*(?:\u{1B}\\\\|$)",
            with: "", options: .regularExpression)

        // 4. Remaining lone ESC + single char (ESC c, ESC =, etc.)
        result = result.replacingOccurrences(
            of: "\u{1B}[@-Z\\\\-_]",
            with: "", options: .regularExpression)

        // 5. Bare ESC that survived
        result = result.replacingOccurrences(of: "\u{1B}", with: "")

        // 6. Bracketed paste artifacts that sometimes survive as literal text
        result = result.replacingOccurrences(of: "[?2004h", with: "")
        result = result.replacingOccurrences(of: "[?2004l", with: "")

        // 7. Bare \r (not followed by \n — those are handled in drainLineBuffer)
        result = result.replacingOccurrences(of: "\r\n", with: "\n")

        return result
    }

    // MARK: - UTF-8 greedy decode

    /// Decodes as many complete UTF-8 characters as possible from data.
    /// Returns (decoded string, leftover bytes that form an incomplete sequence).
    private func decodeUTF8Greedy(_ data: Data) -> (String, Data) {
        let bytes = Array(data)
        // Walk backwards to find the last complete UTF-8 sequence boundary
        var end = bytes.count
        while end > 0 {
            let slice = bytes[0..<end]
            if let s = String(bytes: slice, encoding: .utf8) {
                let remainder = end < bytes.count ? Data(bytes[end...]) : Data()
                return (s, remainder)
            }
            end -= 1
        }
        return ("", data)
    }

    // MARK: - Directory rendering

    private func showDirectoryPicker() {
        showDirectoryContents()
    }

    // Renders current directory contents (dirs + files) via FileManager — no shell involved
    private func showDirectoryContents() {
        let url = URL(fileURLWithPath: currentDirectory)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .isRegularFileKey],
            options: .skipsSubdirectoryDescendants
        ) else {
            emitSystem("⚠️ Cannot read directory (permission denied)")
            return
        }

        let sorted = items
            .filter { u in (try? u.resourceValues(forKeys: [.isHiddenKey]))?.isHidden != true }
            .sorted { a, b in
                let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if aDir != bDir { return aDir } // dirs first
                return a.lastPathComponent < b.lastPathComponent
            }

        DispatchQueue.main.async {
            for u in sorted {
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                self.lines.append(TerminalLine(
                    content: u.lastPathComponent,
                    type: isDir ? .directory : .file,
                    metadata: u.path
                ))
            }
        }
    }

    // Called when user clicks a directory chip — full path, no matching needed
    func cdInto(_ path: String) {
        guard masterFD >= 0 else { return }
        DispatchQueue.main.async { self.emit("cd \(path)", type: .input) }
        sendRaw("cd \"\(path)\"")
        updateDirectoryIfNeeded("cd \(path)")
        // Show contents via FileManager after directory updates — no shell ls
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.showDirectoryContents()
        }
    }

    // MARK: - Smart CD

    private func handleSmartCD(_ trimmed: String) {
        // Bare cd — show picker
        guard trimmed.hasPrefix("cd ") else {
            showDirectoryPicker()
            return
        }

        let input = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)

        // Absolute / relative / home paths — pass straight to shell
        if input.hasPrefix("/") || input.hasPrefix("~") || input.hasPrefix(".") {
            sendRaw("cd \"\(input)\"")
            updateDirectoryIfNeeded(trimmed)
            return
        }

        // Case-insensitive match against real filesystem
        let dirs = realDirectories(at: currentDirectory)
        if let match = dirs.first(where: { $0.lowercased() == input.lowercased() }) {
            let quoted = "cd \"\(match)\""
            sendRaw(quoted)
            updateDirectoryIfNeeded(quoted)
        } else {
            // No match — let shell handle it (will show its own error)
            sendRaw("cd \"\(input)\"")
            updateDirectoryIfNeeded(trimmed)
        }
    }

    private func sendRaw(_ cmd: String) {
        let payload = cmd + "\n"
        payload.withCString { ptr in _ = write(masterFD, ptr, strlen(ptr)) }
    }

    // Heuristic: multi-word input with no shell-like characters = natural language
    private func isNaturalLanguage(_ input: String) -> Bool {
        let knownCommands = ["git", "npm", "yarn", "pip", "python", "python3", "node",
                             "swift", "xcode", "brew", "curl", "wget", "ssh", "scp",
                             "grep", "find", "cat", "echo", "mkdir", "touch", "rm",
                             "mv", "cp", "chmod", "chown", "sudo", "export", "source",
                             "which", "man", "kill", "ps", "top", "df", "du", "pwd"]
        let firstWord = input.components(separatedBy: .whitespaces).first ?? ""
        // If it starts with a known command, it's a shell command
        if knownCommands.contains(firstWord.lowercased()) { return false }
        // If it contains shell-specific chars, it's a shell command
        if input.contains("/") || input.contains("|") || input.contains(">") ||
           input.contains("&") || input.contains("$") || input.contains("-") { return false }
        // Multi-word without shell chars = natural language
        return input.contains(" ")
    }

    private func realDirectories(at path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: .skipsSubdirectoryDescendants
        ) else { return [] }
        return items.compactMap { u -> String? in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard v?.isDirectory == true, v?.isHidden != true else { return nil }
            return u.lastPathComponent
        }.sorted()
    }

    // Returns directories matching a prefix — used for autocomplete
    func directorySuggestions(for prefix: String) -> [String] {
        let dirs = realDirectories(at: currentDirectory)
        guard !prefix.isEmpty else { return dirs }
        return dirs.filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
    }

    private func updateDirectoryIfNeeded(_ command: String) {
        let t = command.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("cd ") || t == "cd" else { return }
        // After cd, probe pwd and show new directory as confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let probe = "echo __LAMADIR__$(pwd)__LAMADIR__\n"
            probe.withCString { ptr in _ = write(self.masterFD, ptr, strlen(ptr)) }
        }
    }

    // MARK: - Emit helpers

    private func emit(_ content: String, type: TerminalLine.LineType) {
        lines.append(TerminalLine(content: content, type: type))
    }

    private func emitSystem(_ msg: String) {
        DispatchQueue.main.async {
            self.lines.append(TerminalLine(content: msg, type: .system))
            self.hasReceivedOutput = true
        }
    }

    private func handleBuiltin(_ command: LamaBuiltinCommand) {
        switch command {
        case .help:
            emitSystem("""
LAMA S commands: lama theme list|next|obsidian|dune|matrix, lama color list|ice|amber|lime|coral, lama density compact|comfortable|spacious, lama glass on|off, lama mode cmd|nl, lama clear, lama intro, mkcd <name>, .., home
""")
        case .clear:
            DispatchQueue.main.async {
                self.lines.removeAll()
                self.lastError = nil
                self.hasReceivedOutput = false
            }
        case .intro:
            DispatchQueue.main.async {
                self.introToken = UUID()
                self.emitSystem("Splash screen restarted.")
            }
        case .mode(let nl):
            DispatchQueue.main.async {
                self.isNLMode = nl
                self.emitSystem(nl ? "Natural language mode enabled." : "Command mode enabled.")
            }
        case .themeList:
            let names = TerminalAppearance.ThemePreset.allCases.map(\.rawValue).joined(separator: ", ")
            emitSystem("Themes: \(names)")
        case .themeSet(let value):
            DispatchQueue.main.async {
                if self.appearance.setTheme(named: value) {
                    self.emitSystem("Theme set to \(self.appearance.theme.rawValue).")
                } else {
                    self.emitSystem("Unknown theme '\(value)'. Use: lama theme list")
                }
            }
        case .themeNext:
            DispatchQueue.main.async {
                self.appearance.cycleTheme()
                self.emitSystem("Theme set to \(self.appearance.theme.rawValue).")
            }
        case .accentList:
            let names = TerminalAppearance.AccentPreset.allCases.map(\.rawValue).joined(separator: ", ")
            emitSystem("Colors: \(names)")
        case .accentSet(let value):
            DispatchQueue.main.async {
                if self.appearance.setAccent(named: value) {
                    self.emitSystem("Accent color set to \(self.appearance.accent.rawValue).")
                } else {
                    self.emitSystem("Unknown color '\(value)'. Use: lama color list")
                }
            }
        case .densitySet(let value):
            DispatchQueue.main.async {
                if self.appearance.setDensity(named: value) {
                    self.emitSystem("Density set to \(self.appearance.density.rawValue).")
                } else {
                    self.emitSystem("Unknown density '\(value)'. Use compact, comfortable, or spacious.")
                }
            }
        case .glass(let enabled):
            DispatchQueue.main.async {
                self.appearance.glassEnabled = enabled
                self.emitSystem(enabled ? "Glass chrome enabled." : "Glass chrome disabled.")
            }
        case .mkcd(let name):
            let folderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else {
                emitSystem("Usage: mkcd <folder-name>")
                return
            }

            let destination = URL(fileURLWithPath: currentDirectory).appendingPathComponent(folderName)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                cdInto(destination.path)
                emitSystem("Created and entered \(folderName).")
            } catch {
                emitSystem("Could not create \(folderName): \(error.localizedDescription)")
            }
        case .parentDirectory:
            cdInto((currentDirectory as NSString).deletingLastPathComponent)
        case .home:
            cdInto(NSHomeDirectory())
        }
    }
}
