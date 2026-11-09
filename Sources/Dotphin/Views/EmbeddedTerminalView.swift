import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI

/// Processes a VT100/xterm byte/character stream with proper support for carriage return (`\r`),
/// line feed (`\n`), backspace (`\u{08}`), form feed (`\u{0C}`), and ANSI CSI/OSC sequences
/// (`ESC [ K`, `ESC [ 2K`, `ESC [ J`, `ESC [ n D`, `ESC [ n C`, `ESC [ n G`) used by `zsh` ZLE.
struct TerminalScreenBuffer: Sendable {
    private(set) var lines: [[Character]] = [[]]
    private(set) var cursorRow: Int = 0
    private(set) var cursorCol: Int = 0
    private var pendingEscape: String = ""

    mutating func reset() {
        lines = [[]]
        cursorRow = 0
        cursorCol = 0
        pendingEscape = ""
    }

    mutating func feed(_ rawChunk: String) {
        let input = pendingEscape + rawChunk
        pendingEscape = ""

        var index = input.startIndex
        while index < input.endIndex {
            let ch = input[index]

            if ch == "\u{001B}" {
                guard let (nextIndex, complete) = parseEscapeSequence(in: input, from: index) else {
                    pendingEscape = String(input[index...])
                    break
                }
                if complete {
                    index = nextIndex
                    continue
                }
            }

            // Note: Swift treats "\r\n" as a single grapheme cluster Character!
            if ch == "\r\n" {
                advanceLine()
            } else if ch == "\r" {
                cursorCol = 0
            } else if ch == "\n" {
                advanceLine()
            } else if ch == "\u{0008}" {
                if cursorCol > 0 {
                    cursorCol -= 1
                }
            } else if ch == "\u{000C}" {
                // Form feed (Ctrl+L)
                lines = [[]]
                cursorRow = 0
                cursorCol = 0
            } else if ch == "\u{0007}" {
                // BEL — ignore
            } else if ch == "\t" {
                let spaces = 4 - (cursorCol % 4)
                for _ in 0..<spaces {
                    putCharacter(" ")
                }
            } else {
                for scalarChar in String(ch) where scalarChar != "\0" {
                    putCharacter(scalarChar)
                }
            }

            index = input.index(after: index)
        }

        trimHistoryIfNeeded()
    }

    var renderedText: String {
        lines.map { String($0) }.joined(separator: "\n")
    }

    private mutating func ensureRowExists(_ row: Int) {
        while lines.count <= row {
            lines.append([])
        }
    }

    private mutating func advanceLine() {
        cursorRow += 1
        ensureRowExists(cursorRow)
        cursorCol = 0
    }

    private mutating func putCharacter(_ ch: Character) {
        ensureRowExists(cursorRow)
        if cursorCol > lines[cursorRow].count {
            let padding = cursorCol - lines[cursorRow].count
            lines[cursorRow].append(contentsOf: repeatElement(" ", count: padding))
        }
        if cursorCol < lines[cursorRow].count {
            lines[cursorRow][cursorCol] = ch
        } else {
            lines[cursorRow].append(ch)
        }
        cursorCol += 1
    }

    private mutating func parseEscapeSequence(
        in text: String,
        from escIndex: String.Index
    ) -> (nextIndex: String.Index, complete: Bool)? {
        let afterEsc = text.index(after: escIndex)
        guard afterEsc < text.endIndex else { return nil }
        let kind = text[afterEsc]

        // 1. CSI sequence: ESC [ ... finalByte (@ through ~)
        if kind == "[" {
            var cur = text.index(after: afterEsc)
            var params = ""
            while cur < text.endIndex {
                let c = text[cur]
                if let ascii = c.asciiValue, ascii >= 0x40 && ascii <= 0x7E {
                    handleCSI(params: params, finalByte: c)
                    return (text.index(after: cur), true)
                }
                params.append(c)
                cur = text.index(after: cur)
            }
            return nil
        }

        // 2. OSC sequence: ESC ] ... (BEL \u{07} or ST: ESC \)
        if kind == "]" {
            var cur = text.index(after: afterEsc)
            while cur < text.endIndex {
                let c = text[cur]
                if c == "\u{0007}" {
                    return (text.index(after: cur), true)
                }
                if c == "\u{001B}" {
                    let next = text.index(after: cur)
                    guard next < text.endIndex else { return nil }
                    if text[next] == "\\" {
                        return (text.index(after: next), true)
                    }
                }
                cur = text.index(after: cur)
            }
            return nil
        }

        // 3. Charset / two-byte sequence: ESC ( X or ESC ) X
        if kind == "(" || kind == ")" {
            let next = text.index(after: afterEsc)
            guard next < text.endIndex else { return nil }
            return (text.index(after: next), true)
        }

        // 4. Single-character ESC sequence (e.g. ESC =, ESC >, ESC M)
        return (text.index(after: afterEsc), true)
    }

    private mutating func handleCSI(params: String, finalByte: Character) {
        ensureRowExists(cursorRow)
        let cleanParams = params.trimmingCharacters(in: CharacterSet(charactersIn: "?<>="))
        let parts = cleanParams.split(separator: ";", omittingEmptySubsequences: false)
        let firstNumber = Int(parts.first ?? "") ?? 0
        let secondNumber = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        switch finalByte {
        case "K":
            // Erase in Line (EL): 0 = cursor to end, 1 = start to cursor, 2 = entire line
            let mode = firstNumber
            if mode == 0 {
                if cursorCol < lines[cursorRow].count {
                    lines[cursorRow].removeSubrange(cursorCol..<lines[cursorRow].count)
                }
            } else if mode == 1 {
                let end = min(cursorCol + 1, lines[cursorRow].count)
                for i in 0..<end {
                    lines[cursorRow][i] = " "
                }
            } else if mode == 2 {
                lines[cursorRow].removeAll()
                cursorCol = 0
            }
        case "J":
            // Erase in Display (ED): 0 = cursor to end, 2 or 3 = clear entire screen
            if firstNumber == 2 || firstNumber == 3 {
                lines = [[]]
                cursorRow = 0
                cursorCol = 0
            } else if firstNumber == 0 {
                if cursorCol < lines[cursorRow].count {
                    lines[cursorRow].removeSubrange(cursorCol..<lines[cursorRow].count)
                }
                if cursorRow + 1 < lines.count {
                    lines.removeSubrange((cursorRow + 1)..<lines.count)
                }
            }
        case "A":
            // Cursor Up (CUU)
            let count = max(1, firstNumber)
            cursorRow = max(0, cursorRow - count)
            ensureRowExists(cursorRow)
        case "B":
            // Cursor Down (CUD)
            let count = max(1, firstNumber)
            cursorRow += count
            ensureRowExists(cursorRow)
        case "E":
            // Cursor Next Line (CNL)
            let count = max(1, firstNumber)
            cursorRow += count
            cursorCol = 0
            ensureRowExists(cursorRow)
        case "F":
            // Cursor Previous Line (CPL)
            let count = max(1, firstNumber)
            cursorRow = max(0, cursorRow - count)
            cursorCol = 0
            ensureRowExists(cursorRow)
        case "H", "f":
            // Cursor Position (CUP, 1-based row;col)
            let row = max(1, firstNumber) - 1
            let col = max(1, secondNumber) - 1
            cursorRow = row
            cursorCol = col
            ensureRowExists(cursorRow)
        case "d":
            // Line Position Absolute (VPA, 1-based row)
            let row = max(1, firstNumber) - 1
            cursorRow = row
            ensureRowExists(cursorRow)
        case "D":
            // Cursor Backward (CUB)
            let count = max(1, firstNumber)
            cursorCol = max(0, cursorCol - count)
        case "C":
            // Cursor Forward (CUF)
            let count = max(1, firstNumber)
            cursorCol += count
        case "G":
            // Cursor Horizontal Absolute (CHA, 1-based)
            let col = max(1, firstNumber)
            cursorCol = col - 1
        case "P":
            // Delete Character (DCH)
            let count = max(1, firstNumber)
            if cursorCol < lines[cursorRow].count {
                let end = min(lines[cursorRow].count, cursorCol + count)
                lines[cursorRow].removeSubrange(cursorCol..<end)
            }
        default:
            break
        }
    }

    private mutating func trimHistoryIfNeeded() {
        let maxLines = 1500
        if lines.count > maxLines {
            let overflow = lines.count - 1200
            lines.removeFirst(overflow)
            cursorRow = max(0, cursorRow - overflow)
        }
    }
}

/// Manages an interactive pseudo-terminal (`openpty` + `/bin/zsh`) session that automatically
/// synchronizes its working directory with Dolphin's active folder (just like KDE Dolphin's F4 Konsole panel).
@MainActor
@Observable
final class EmbeddedTerminalSession {
    private(set) var outputText: String = ""
    private(set) var isRunning: Bool = false
    private(set) var currentSyncedDirectory: URL?
    var autoSyncDirectory: Bool = true
    var onDirectoryChanged: ((URL) -> Void)?

    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var shellProcess: Process?
    private var readSource: DispatchSourceRead?
    private var screenBuffer = TerminalScreenBuffer()
    private var hasUserExecutedCommand: Bool = false

    init() {}

    func startIfNeeded(initialDirectory: URL) {
        if isRunning {
            if autoSyncDirectory {
                syncDirectory(to: initialDirectory)
            }
            return
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        var winSize = winsize(ws_row: 36, ws_col: 220, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &winSize) == 0 else {
            outputText += "\n[Error: no se pudo abrir el pseudo-terminal (openpty)]\n"
            return
        }

        let flags = fcntl(master, F_GETFL)
        if flags != -1 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }

        self.masterFD = master
        self.slaveFD = slave
        self.screenBuffer.reset()
        self.hasUserExecutedCommand = false

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        if shellPath.hasSuffix("zsh") {
            // Login + interactive, disable PROMPT_SP (`%` + 99 spaces before prompt), ignore leading-space commands in history
            process.arguments = ["-l", "-i", "-o", "nopromptsp", "-o", "histignorespace"]
        } else {
            process.arguments = ["-l", "-i"]
        }
        process.currentDirectoryURL = initialDirectory

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.enrichedDeveloperPath(existingPath: env["PATH"])
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["CLICOLOR"] = "1"
        env["COLUMNS"] = "220"
        env["LINES"] = "36"
        env["PROMPT_EOL_MARK"] = ""
        env["LANG"] = env["LANG"] ?? "es_ES.UTF-8"
        if shellPath.hasSuffix("zsh") {
            env["PROMPT"] = "%n@%m %1~ %# "
        }
        process.environment = env

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.readAvailableBytes()
            }
        }
        source.setCancelHandler { [master, slave] in
            if master >= 0 { close(master) }
            if slave >= 0 { close(slave) }
        }
        self.readSource = source
        source.resume()

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }

        do {
            try process.run()
            self.shellProcess = process
            self.isRunning = true
            self.currentSyncedDirectory = initialDirectory.standardizedFileURL
        } catch {
            outputText += "\n[Error al iniciar \(shellPath): \(error.localizedDescription)]\n"
            source.cancel()
            self.readSource = nil
            self.masterFD = -1
            self.slaveFD = -1
        }
    }

    /// Builds a complete `PATH` for GUI-launched macOS apps so tools installed via Homebrew,
    /// Mise (`~/.local/share/mise/shims`, `/opt/homebrew/bin/mise`), Cargo, or Bun work in `.zshrc`.
    nonisolated static func enrichedDeveloperPath(existingPath: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let priorityPaths = [
            "\(home)/.local/share/mise/shims",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Library/Apple/usr/bin"
        ]
        var seen = Set<String>()
        var ordered: [String] = []
        for p in priorityPaths where !p.isEmpty {
            if seen.insert(p).inserted {
                ordered.append(p)
            }
        }
        if let existingPath {
            for p in existingPath.split(separator: ":").map(String.init) where !p.isEmpty {
                if seen.insert(p).inserted {
                    ordered.append(p)
                }
            }
        }
        return ordered.joined(separator: ":")
    }

    func stop() {
        if let process = shellProcess, process.isRunning {
            process.terminate()
        }
        shellProcess = nil
        readSource?.cancel()
        readSource = nil
        masterFD = -1
        slaveFD = -1
        isRunning = false
    }

    /// Dolphin's signature Konsole behavior (`src/panels/terminal/terminalpanel.cpp`):
    /// navigating to a folder in the file manager automatically `cd`s the terminal.
    func syncDirectory(to url: URL) {
        guard autoSyncDirectory else { return }
        let standardized = url.standardizedFileURL
        guard isRunning else {
            currentSyncedDirectory = standardized
            return
        }
        guard currentSyncedDirectory != standardized else { return }
        currentSyncedDirectory = standardized
        let quoted = Self.shellSingleQuoted(standardized.path)

        if !hasUserExecutedCommand {
            // Keep the terminal clean when the user is just clicking through folders in Dolphin
            // without having run custom commands yet (matches Dolphin's m_clearTerminal behavior).
            screenBuffer.reset()
            outputText = ""
            sendRaw("\u{0005}\u{0015} cd \(quoted) && clear\r")
        } else {
            // Send Ctrl+E, Ctrl+U to clear any partial input, then leading-space cd
            sendRaw("\u{0005}\u{0015} cd \(quoted)\r")
        }
    }

    func sendCommand(_ command: String) {
        guard isRunning else { return }
        hasUserExecutedCommand = true
        sendRaw(command + "\r")
    }

    func sendInterrupt() {
        guard isRunning else { return }
        // Ctrl+C (ETX, 0x03)
        sendBytes([0x03])
    }

    func clearOutput() {
        hasUserExecutedCommand = false
        screenBuffer.reset()
        outputText = ""
        if isRunning {
            sendRaw("\u{0005}\u{0015} clear\r")
        }
    }

    func updateWindowSize(rows: UInt16, cols: UInt16 = 220) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: max(5, rows), ws_col: max(40, cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    func sendRaw(_ text: String) {
        sendBytes(Array(text.utf8))
    }

    private func sendBytes(_ bytes: [UInt8]) {
        guard masterFD >= 0, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            _ = Darwin.write(masterFD, base, rawBuffer.count)
        }
    }

    private func readAvailableBytes() {
        guard masterFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var collected: [UInt8] = []
        while true {
            let count = Darwin.read(masterFD, &buffer, buffer.count)
            if count > 0 {
                collected.append(contentsOf: buffer[0..<count])
            } else {
                break
            }
        }
        guard !collected.isEmpty else { return }
        let rawChunk = String(decoding: collected, as: UTF8.self)
        screenBuffer.feed(rawChunk)
        outputText = screenBuffer.renderedText
        checkShellWorkingDirectoryAfterOutput()
    }

    /// Queries the shell process's current working directory via `proc_pidinfo(PROC_PIDVNODEPATHINFO)`
    /// so that `cd` commands typed inside the terminal navigate Dolphin's active pane (`slotTerminalDirectoryChanged`).
    private func checkShellWorkingDirectoryAfterOutput() {
        guard autoSyncDirectory, hasUserExecutedCommand,
              let process = shellProcess, process.isRunning else { return }
        guard let detectedURL = Self.workingDirectory(forPID: process.processIdentifier) else { return }
        let standardized = detectedURL.standardizedFileURL
        guard standardized != currentSyncedDirectory else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        currentSyncedDirectory = standardized
        onDirectoryChanged?(standardized)
    }

    nonisolated static func workingDirectory(forPID pid: pid_t) -> URL? {
        guard pid > 0 else { return nil }
        var vnodeInfo = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, size)
        guard ret == size else { return nil }
        let path: String = withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// Processes a raw terminal stream through `TerminalScreenBuffer` (used by unit tests and snapshot helpers).
    nonisolated static func stripANSISequences(from input: String) -> String {
        var buf = TerminalScreenBuffer()
        buf.feed(input)
        return buf.renderedText
    }

    nonisolated static func applyBackspaces(to input: String) -> String {
        var buf = TerminalScreenBuffer()
        buf.feed(input)
        return buf.renderedText
    }

    nonisolated static func shellSingleQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// KDE Dolphin-style integrated bottom terminal panel (`F4`), with live directory synchronization,
/// command history (`↑` / `↓`), interrupt (`Ctrl+C`), clear, interactive height resizing,
/// and a quick button to open macOS Terminal.app.
struct EmbeddedTerminalPanelView: View {
    nonisolated static let minHeight: CGFloat = 110
    nonisolated static let maxHeight: CGFloat = 560
    nonisolated static let defaultHeight: CGFloat = 220
    nonisolated static let expandedHeight: CGFloat = 420

    let session: EmbeddedTerminalSession
    let currentDirectory: URL
    @Binding var panelHeight: CGFloat
    var onDirectoryChanged: ((URL) -> Void)? = nil
    let onOpenExternalTerminal: () -> Void
    let onClose: () -> Void

    @State private var commandInput: String = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int? = nil
    @State private var dragStartHeight: CGFloat? = nil
    @State private var isHoveringResizeBar: Bool = false
    @FocusState private var isInputFocused: Bool

    init(
        session: EmbeddedTerminalSession,
        currentDirectory: URL,
        panelHeight: Binding<CGFloat> = .constant(Self.defaultHeight),
        onDirectoryChanged: ((URL) -> Void)? = nil,
        onOpenExternalTerminal: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.currentDirectory = currentDirectory
        self._panelHeight = panelHeight
        self.onDirectoryChanged = onDirectoryChanged
        self.onOpenExternalTerminal = onOpenExternalTerminal
        self.onClose = onClose
    }

    private var isExpandedHeight: Bool {
        panelHeight >= 340
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandleBar

            headerBar

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.outputText.isEmpty ? "Iniciando sesión de terminal en \(currentDirectory.path)…" : session.outputText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .id("terminalBottom")
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
                .onChange(of: session.outputText) { _, _ in
                    proxy.scrollTo("terminalBottom", anchor: .bottom)
                }
                .onTapGesture {
                    isInputFocused = true
                }
            }

            Divider()

            inputBar
        }
        .background(.bar)
        .onAppear {
            session.onDirectoryChanged = onDirectoryChanged
            session.startIfNeeded(initialDirectory: currentDirectory)
            let approxRows = UInt16(max(6, Int((panelHeight - 64) / 15)))
            session.updateWindowSize(rows: approxRows)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
        .onChange(of: currentDirectory) { _, newURL in
            session.syncDirectory(to: newURL)
        }
        .onChange(of: panelHeight) { _, newHeight in
            let approxRows = UInt16(max(6, Int((newHeight - 64) / 15)))
            session.updateWindowSize(rows: approxRows)
        }
    }

    private var verticalResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartHeight ?? panelHeight
                if dragStartHeight == nil {
                    dragStartHeight = start
                }
                let proposed = start - value.translation.height
                panelHeight = min(Self.maxHeight, max(Self.minHeight, proposed))
            }
            .onEnded { _ in
                dragStartHeight = nil
            }
    }

    private func toggleExpandedHeight() {
        withAnimation(.snappy(duration: 0.18)) {
            panelHeight = isExpandedHeight ? Self.defaultHeight : Self.expandedHeight
        }
    }

    private var resizeHandleBar: some View {
        ZStack {
            Rectangle()
                .fill(isHoveringResizeBar || dragStartHeight != nil ? Color.accentColor.opacity(0.14) : Color.clear)
                .frame(height: 7)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(isHoveringResizeBar || dragStartHeight != nil ? Color.accentColor.opacity(0.65) : Color(nsColor: .separatorColor))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }

            Capsule()
                .fill(isHoveringResizeBar || dragStartHeight != nil ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 36, height: 3.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 7)
        .contentShape(Rectangle())
        .help("Arrastra hacia arriba o abajo para redimensionar la terminal (doble clic para expandir/restaurar)")
        .onHover { hovering in
            isHoveringResizeBar = hovering
            if hovering {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(count: 2) {
            toggleExpandedHeight()
        }
        .gesture(verticalResizeGesture)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Terminal — \(currentDirectory.lastPathComponent.isEmpty ? "/" : currentDirectory.lastPathComponent)")
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)

            Text(currentDirectory.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                session.autoSyncDirectory.toggle()
                if session.autoSyncDirectory {
                    session.syncDirectory(to: currentDirectory)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.autoSyncDirectory ? "link" : "link.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Sincronizar")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(session.autoSyncDirectory ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    session.autoSyncDirectory ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            .buttonStyle(.plain)
            .help("Sincronizar automáticamente el directorio de la terminal con la carpeta actual de Dolphin")

            Button {
                session.sendInterrupt()
            } label: {
                Text("^C")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Enviar interrupción (Ctrl+C)")

            Button {
                session.clearOutput()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Limpiar salida de la terminal")

            Button {
                toggleExpandedHeight()
            } label: {
                Image(systemName: isExpandedHeight ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isExpandedHeight ? "Restaurar altura de la terminal" : "Expandir altura de la terminal")

            Button(action: onOpenExternalTerminal) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Abrir en Terminal.app externa (⇧F4)")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Ocultar panel de terminal (F4)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(verticalResizeGesture)
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Text("❯")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)

            TextField("Escribir comando… (Intro para ejecutar, ↑/↓ historial)", text: $commandInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isInputFocused)
                .onSubmit {
                    submitCommand()
                }
                .onKeyPress(.upArrow) {
                    navigateHistory(direction: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateHistory(direction: 1)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "cC"), phases: .down) { keyPress in
                    if keyPress.modifiers.contains(.control) {
                        session.sendInterrupt()
                        return .handled
                    }
                    return .ignored
                }

            Button {
                submitCommand()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(commandInput.isEmpty ? .tertiary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(commandInput.isEmpty)
            .help("Ejecutar comando (Intro)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
    }

    private func submitCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "clear" {
            commandHistory.append(commandInput)
            historyIndex = nil
            commandInput = ""
            session.clearOutput()
            return
        }
        if !trimmed.isEmpty {
            commandHistory.append(commandInput)
        }
        historyIndex = nil
        let toSend = commandInput
        commandInput = ""
        session.sendCommand(toSend)
    }

    private func navigateHistory(direction: Int) {
        guard !commandHistory.isEmpty else { return }
        if let current = historyIndex {
            let next = current + direction
            if next < 0 {
                historyIndex = 0
                commandInput = commandHistory[0]
            } else if next >= commandHistory.count {
                historyIndex = nil
                commandInput = ""
            } else {
                historyIndex = next
                commandInput = commandHistory[next]
            }
        } else if direction < 0 {
            let last = commandHistory.count - 1
            historyIndex = last
            commandInput = commandHistory[last]
        }
    }
}
