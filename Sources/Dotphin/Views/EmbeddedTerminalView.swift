import AppKit
import Darwin
import Foundation
import Observation
import SwiftTerm
import SwiftUI
import Synchronization

/// SwiftTerm terminal view used by the terminal panel (⌃`). SwiftTerm does the whole VT/xterm emulation
/// (colors, alternate screen, mouse, wide characters) and owns the pty; this subclass only adds
/// Dotphin's keyboard rules and follows the system's light/dark colors.
final class DotphinTerminalView: LocalProcessTerminalView {
    /// Called when the user presses Return in the terminal (a command line was submitted).
    var onUserSubmittedLine: (() -> Void)?
    /// Takes keyboard focus the next time the view lands in a window (the panel just opened).
    var focusWhenAttached = false

    private var keyMonitor: Any?

    /// Return or keypad Enter without ⌘: the shell receives a command line.
    static func submitsLine(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && (event.keyCode == 36 || event.keyCode == 76)
            && !event.modifierFlags.contains(.command)
    }

    /// ⌃` / ⌃⇧` toggle the panel and open Terminal.app; they belong to the menu, not to the shell.
    /// (F4 / ⇧F4 are translated to these by `FunctionKeyShortcuts` before the terminal sees them.)
    static func isPanelShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 50 else { return false }
        return event.modifierFlags.contains(.control)
            && event.modifierFlags.isDisjoint(with: [.command, .option])
    }

    func applyDotphinStyle() {
        font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // Option composes characters (e.g. @ on Spanish layouts), as in Terminal.app.
        optionAsMetaKey = false
        applySystemColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySystemColors()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeKeyMonitor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeKeyMonitor()
            return
        }
        installKeyMonitor()
        if focusWhenAttached {
            focusWhenAttached = false
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    private func applySystemColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeForegroundColor = NSColor.textColor.usingColorSpace(.sRGB) ?? .textColor
            nativeBackgroundColor = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .textBackgroundColor
        }
    }

    /// SwiftTerm's `keyDown` is not overridable, so the keys Dotphin cares about are looked at
    /// before AppKit dispatches them, and only while this terminal has the focus.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handledByMenu = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window,
                      event.window === window, window.firstResponder === self else { return false }
                if Self.isPanelShortcut(event), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                    return true
                }
                // Return that commits marked text (IME) is not a command line.
                if Self.submitsLine(event), !self.hasMarkedText() {
                    self.onUserSubmittedLine?()
                }
                return false
            }
            return handledByMenu ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

/// Lets the pty's I/O thread ask for at most one pending main-actor directory check at a time,
/// so a burst of output (`cat` of a big file) does not enqueue thousands of tasks.
private final class OutputCheckGate: Sendable {
    private let pending = Mutex(false)

    func claim() -> Bool {
        pending.withLock { pending in
            defer { pending = true }
            return !pending
        }
    }

    func release() {
        pending.withLock { $0 = false }
    }
}

/// Owns the interactive shell of the F4 panel and keeps its working directory in sync with
/// Dotphin's active folder (like KDE Dolphin's Konsole panel). It outlives the panel view, so
/// hiding and showing the panel keeps the same shell.
@MainActor
@Observable
final class EmbeddedTerminalSession: LocalProcessTerminalViewDelegate {
    private(set) var isRunning: Bool = false
    private(set) var launchFailed: Bool = false
    private(set) var currentSyncedDirectory: URL?
    private(set) var terminalView: DotphinTerminalView?
    /// The user has run something in the shell, so it is no longer just following Dotphin.
    private(set) var hasUserExecutedCommand: Bool = false
    var autoSyncDirectory: Bool = true
    @ObservationIgnored var onDirectoryChanged: ((URL) -> Void)?
    /// Extra variables for the shell (tests point `ZDOTDIR` at an empty folder).
    @ObservationIgnored var environmentOverrides: [String: String] = [:]

    @ObservationIgnored private let outputGate = OutputCheckGate()
    /// A `cd` Dotphin sent and the shell has not performed yet. Until then the shell's old
    /// directory must not be reported back, or Dotphin would bounce to the previous folder.
    @ObservationIgnored private var pendingDotphinDirectory: (url: URL, deadline: Date)?
    /// Folder Dotphin moved to while a program (vim, less, a dev server) owned the terminal;
    /// the `cd` is sent once the shell is back in the foreground.
    @ObservationIgnored private var deferredDirectory: URL?

    init() {}

    func startIfNeeded(initialDirectory: URL) {
        if isRunning {
            if autoSyncDirectory {
                syncDirectory(to: initialDirectory)
            }
            return
        }

        // A shell that ended leaves its view on screen until the restart replaces it.
        _ = terminalView?.updateUiClosed()
        launchFailed = false
        pendingDotphinDirectory = nil
        deferredDirectory = nil

        let view = DotphinTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        view.applyDotphinStyle()
        view.focusWhenAttached = true
        view.processDelegate = self
        view.onUserSubmittedLine = { [weak self] in
            self?.noteUserSubmittedLine()
        }
        let gate = outputGate
        view.setProcessOutputHandler { [weak self] in
            guard gate.claim() else { return }
            Task { @MainActor [weak self] in
                gate.release()
                self?.checkShellWorkingDirectoryAfterOutput()
            }
        }

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // Login + interactive; with zsh, commands typed with a leading space (Dotphin's own
        // `cd`) stay out of the history.
        let arguments = shellPath.hasSuffix("zsh") ? ["-l", "-i", "-o", "histignorespace"] : ["-l", "-i"]

        terminalView = view
        hasUserExecutedCommand = false
        currentSyncedDirectory = initialDirectory.standardizedFileURL
        view.startProcess(
            executable: shellPath,
            args: arguments,
            environment: Self.shellEnvironment(
                base: ProcessInfo.processInfo.environment.merging(environmentOverrides) { $1 }
            ),
            currentDirectory: initialDirectory.path
        )
        isRunning = view.process.running
    }

    nonisolated static func shellEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var env = base
        env["PATH"] = enrichedDeveloperPath(existingPath: env["PATH"])
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["CLICOLOR"] = "1"
        env["LANG"] = env["LANG"] ?? defaultLanguage()
        // The panel sizes the pty; stale values from the launching environment would win over it.
        env["COLUMNS"] = nil
        env["LINES"] = nil
        // Under `swift run` from iTerm/Terminal these would make shell integrations think they
        // run in that terminal.
        for key in env.keys where key.hasPrefix("ITERM_") || key.hasPrefix("TERM_SESSION") || key.hasPrefix("TERM_PROGRAM") {
            env[key] = nil
        }
        env["TERM_PROGRAM"] = "Dotphin"
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// GUI apps usually get no `LANG`; build one from the user's locale (e.g. `es_AR.UTF-8`).
    nonisolated static func defaultLanguage(locale: Locale = .current) -> String {
        guard let language = locale.language.languageCode?.identifier,
              let region = locale.region?.identifier else { return "en_US.UTF-8" }
        return "\(language)_\(region).UTF-8"
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
        if let view = terminalView {
            view.processDelegate = nil
            view.setProcessOutputHandler(nil)
            view.removeKeyMonitor()
            // An interactive shell ignores SIGTERM; SIGHUP ends it and its background jobs,
            // like closing a Terminal.app window.
            let pid = view.process.shellPid
            if pid > 0 {
                kill(pid, SIGHUP)
            }
            view.terminate()
            _ = view.updateUiClosed()
        }
        terminalView = nil
        isRunning = false
        pendingDotphinDirectory = nil
        deferredDirectory = nil
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
        // Typing `cd` into vim or a running server would corrupt it; wait for the prompt.
        guard shellOwnsTerminal else {
            deferredDirectory = standardized
            return
        }
        deferredDirectory = nil
        pendingDotphinDirectory = (standardized, Date().addingTimeInterval(3))
        let quoted = Self.shellSingleQuoted(standardized.path)

        // Ctrl+E, Ctrl+U clear any partial input; the leading space keeps the `cd` out of history.
        if !hasUserExecutedCommand {
            // Keep the terminal clean while the user is just clicking through folders
            // (matches Dolphin's m_clearTerminal behavior).
            sendRaw("\u{0005}\u{0015} cd \(quoted) && clear\r")
        } else {
            sendRaw("\u{0005}\u{0015} cd \(quoted)\r")
        }
    }

    func noteUserSubmittedLine() {
        guard isRunning else { return }
        hasUserExecutedCommand = true
    }

    /// The shell, not a program it launched, is the terminal's foreground process group.
    var shellOwnsTerminal: Bool {
        guard let process = terminalView?.process else { return false }
        let pid = process.shellPid
        let fd = process.childfd
        guard pid > 0, fd >= 0 else { return false }
        return tcgetpgrp(fd) == getpgid(pid)
    }

    func sendInterrupt() {
        guard isRunning else { return }
        // Ctrl+C (ETX, 0x03)
        sendRaw("\u{0003}")
    }

    func clearOutput() {
        hasUserExecutedCommand = false
        if isRunning, shellOwnsTerminal {
            sendRaw("\u{0005}\u{0015} clear\r")
        }
    }

    func sendRaw(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// The shell's working directory, read from the kernel.
    var shellWorkingDirectory: URL? {
        guard let pid = terminalView?.process.shellPid else { return nil }
        return Self.workingDirectory(forPID: pid)
    }

    /// `cd` typed inside the terminal navigates Dolphin's active pane (`slotTerminalDirectoryChanged`).
    private func checkShellWorkingDirectoryAfterOutput() {
        guard isRunning else { return }
        if let deferred = deferredDirectory, shellOwnsTerminal {
            // The program that owned the terminal exited: catch up with Dotphin.
            deferredDirectory = nil
            currentSyncedDirectory = nil
            syncDirectory(to: deferred)
            return
        }
        guard let directory = shellWorkingDirectory else { return }
        reportShellDirectory(directory)
    }

    private func reportShellDirectory(_ directory: URL) {
        let standardized = directory.standardizedFileURL
        if let pending = pendingDotphinDirectory {
            let arrived = Self.realPath(pending.url) == Self.realPath(standardized)
            if arrived || Date() > pending.deadline {
                pendingDotphinDirectory = nil
            }
            // Output printed before the shell ran Dotphin's `cd` still shows the old folder.
            if arrived || pendingDotphinDirectory != nil {
                return
            }
        }
        guard autoSyncDirectory, hasUserExecutedCommand, deferredDirectory == nil else { return }
        // The kernel reports the real path (/private/tmp); Dotphin may be showing a link to it (/tmp).
        if let currentSyncedDirectory, Self.realPath(currentSyncedDirectory) == Self.realPath(standardized) {
            return
        }
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

    /// `realpath(3)`: unlike `resolvingSymlinksInPath()`, it keeps the `/private` prefix.
    nonisolated static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    nonisolated static func shellSingleQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    /// OSC 7, for shells configured to announce their directory.
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard source === terminalView, let path = Self.localPath(fromOSC7: directory) else { return }
        reportShellDirectory(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// `file://host/path` (or a bare path). A directory on another host (an `ssh` session) is not
    /// a local folder, even if one with the same path exists here.
    nonisolated static func localPath(
        fromOSC7 directory: String?,
        localHostNames: Set<String> = [localHostName()]
    ) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        guard let url = URL(string: directory), url.scheme != nil else {
            return directory.hasPrefix("/") ? directory : nil
        }
        guard url.isFileURL else { return nil }
        if let host = url.host(percentEncoded: false), !host.isEmpty, host != "localhost" {
            let names = localHostNames.flatMap { [$0, $0.replacingOccurrences(of: ".local", with: "")] }
            guard names.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) else { return nil }
        }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : path
    }

    /// `gethostname(3)`: what zsh's `$HOST` reports, without the DNS lookup of `ProcessInfo.hostName`.
    nonisolated static func localHostName() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }
        isRunning = false
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        guard source === terminalView else { return }
        isRunning = false
        launchFailed = true
    }
}

/// Hosts the session's SwiftTerm view. The view is created by the session (it outlives the
/// panel), so each panel gets its own container and borrows the terminal. On a quick F4 F4
/// the old container may be dismantled after the new one took the terminal; it only removes
/// the terminal if it still holds it.
private struct SwiftTermHostView: NSViewRepresentable {
    let terminalView: DotphinTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        terminalView.focusWhenAttached = true
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
    }
}

/// KDE Dolphin-style integrated bottom terminal panel (`F4`), with live directory synchronization,
/// interrupt (`Ctrl+C`), clear, and a quick button to open macOS Terminal.app.
struct EmbeddedTerminalPanelView: View {
    nonisolated static let minHeight: CGFloat = 110
    nonisolated static let maxHeight: CGFloat = 560
    nonisolated static let defaultHeight: CGFloat = 220
    nonisolated static let expandedHeight: CGFloat = 420

    let session: EmbeddedTerminalSession
    let currentDirectory: URL
    var onDirectoryChanged: ((URL) -> Void)? = nil
    let onOpenExternalTerminal: () -> Void
    let onClose: () -> Void

    init(
        session: EmbeddedTerminalSession,
        currentDirectory: URL,
        onDirectoryChanged: ((URL) -> Void)? = nil,
        onOpenExternalTerminal: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.currentDirectory = currentDirectory
        self.onDirectoryChanged = onDirectoryChanged
        self.onOpenExternalTerminal = onOpenExternalTerminal
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ZStack(alignment: .bottom) {
                if let terminalView = session.terminalView {
                    SwiftTermHostView(terminalView: terminalView)
                        .id(ObjectIdentifier(terminalView))
                        .padding(.leading, 6)
                        .padding(.vertical, 4)
                }
                if !session.isRunning, session.terminalView != nil {
                    shellEndedBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(.bar)
        .onAppear {
            session.onDirectoryChanged = onDirectoryChanged
            session.startIfNeeded(initialDirectory: currentDirectory)
        }
        .onChange(of: currentDirectory) { _, newURL in
            session.syncDirectory(to: newURL)
        }
        // La altura la maneja el `VSplitView` que contiene al panel; SwiftTerm ajusta el pty.
    }

    private var shellEndedBar: some View {
        HStack(spacing: 8) {
            Text(session.launchFailed
                 ? String(localized: "No se pudo iniciar la shell.", bundle: #bundle)
                 : String(localized: "La sesión de la terminal terminó.", bundle: #bundle))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Button(String(localized: "Reiniciar", bundle: #bundle)) {
                session.startIfNeeded(initialDirectory: currentDirectory)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "Terminal — \(currentDirectory.lastPathComponent.isEmpty ? "/" : currentDirectory.lastPathComponent)", bundle: #bundle))
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
                    Text(String(localized: "Sincronizar", bundle: #bundle))
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
            .help(String(localized: "Sincronizar automáticamente el directorio de la terminal con la carpeta actual de Dolphin", bundle: #bundle))

            Button {
                session.sendInterrupt()
            } label: {
                Text(String(localized: "^C", bundle: #bundle))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Enviar interrupción (Ctrl+C)", bundle: #bundle))

            Button {
                session.clearOutput()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Limpiar salida de la terminal", bundle: #bundle))

            Button(action: onOpenExternalTerminal) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Abrir en Terminal.app externa (⌃⇧`)", bundle: #bundle))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Ocultar panel de terminal (⌃`)", bundle: #bundle))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
