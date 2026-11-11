import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// La terminal F4 sobre SwiftTerm: shell real en un pty, sincronización de
/// carpetas en los dos sentidos y la vista montada en una ventana.
@MainActor
final class EmbeddedTerminalTests: XCTestCase {
    private var tempDir: URL!
    private var dirA: URL!
    private var dirB: URL!
    private var session: EmbeddedTerminalSession!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        dirA = tempDir.appendingPathComponent("uno", isDirectory: true)
        dirB = tempDir.appendingPathComponent("dos con espacio", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        session = EmbeddedTerminalSession()
        // Un zsh sin la configuración del usuario: rápido y predecible.
        let zdotdir = tempDir.appendingPathComponent("zdotdir", isDirectory: true)
        try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        session.environmentOverrides = ["ZDOTDIR": zdotdir.path, "SHELL": "/bin/zsh"]
    }

    override func tearDownWithError() throws {
        session.stop()
        session = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func waitUntil(timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func shellIsIn(_ url: URL) -> Bool {
        session.shellWorkingDirectory.map(EmbeddedTerminalSession.realPath) == EmbeddedTerminalSession.realPath(url)
    }

    func test_session_startsShellInRequestedDirectory_andFollowsDotphin() {
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(session.isRunning)
        XCTAssertNotNil(session.terminalView)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) }, "la shell no arrancó en \(dirA.path)")

        session.syncDirectory(to: dirB)
        XCTAssertTrue(waitUntil { shellIsIn(dirB) }, "la shell no siguió a Dotphin hasta \(dirB.path)")
    }

    func test_cdTypedInShell_navigatesDotphin() {
        var reported: URL?
        session.onDirectoryChanged = { reported = $0 }
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })

        session.noteUserSubmittedLine()
        session.terminalView?.send(txt: " cd \(EmbeddedTerminalSession.shellSingleQuoted(dirB.path))\r")

        XCTAssertTrue(waitUntil { reported != nil }, "Dotphin no se enteró del cd de la shell")
        XCTAssertEqual(reported.map(EmbeddedTerminalSession.realPath), EmbeddedTerminalSession.realPath(dirB))
    }

    func test_shellCdIsIgnored_untilUserRunsACommand() {
        var reported: URL?
        session.onDirectoryChanged = { reported = $0 }
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })

        session.terminalView?.send(txt: " cd \(EmbeddedTerminalSession.shellSingleQuoted(dirB.path))\r")
        XCTAssertTrue(waitUntil { shellIsIn(dirB) })
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(reported)
    }

    func test_dotphinDrivenCd_afterUserCommand_neverBouncesBack() {
        var reported: [String] = []
        session.onDirectoryChanged = { reported.append(EmbeddedTerminalSession.realPath($0)) }
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })
        session.noteUserSubmittedLine()

        for target: URL in [dirB, dirA, dirB] {
            session.syncDirectory(to: target)
            XCTAssertTrue(waitUntil { shellIsIn(target) })
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(reported, [], "Dotphin no debe navegar por un cd que mandó él mismo")
    }

    func test_cdWaitsWhileAProgramOwnsTheTerminal_thenCatchesUp() {
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) && session.shellOwnsTerminal })

        session.noteUserSubmittedLine()
        session.sendRaw("sleep 30\r")
        XCTAssertTrue(waitUntil { !session.shellOwnsTerminal }, "sleep no tomó la terminal")

        session.syncDirectory(to: dirB)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(shellIsIn(dirA), "el cd no debe escribirse dentro del programa")

        session.sendInterrupt()
        XCTAssertTrue(waitUntil { shellIsIn(dirB) }, "al volver el prompt, la shell debe seguir a Dotphin")
    }

    func test_stop_endsTheShellProcess() {
        session.startIfNeeded(initialDirectory: dirA)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })
        let pid = try! XCTUnwrap(session.terminalView?.process.shellPid)
        XCTAssertGreaterThan(pid, 0)

        session.stop()
        XCTAssertTrue(waitUntil(timeout: 3) { kill(pid, 0) != 0 }, "la shell \(pid) sigue viva después de stop()")
    }

    func test_osc7_acceptsLocalPathsOnly() {
        let local: Set<String> = ["mi-mac.local"]
        XCTAssertEqual(EmbeddedTerminalSession.localPath(fromOSC7: "file://mi-mac.local/Users/ana/con%20espacio", localHostNames: local), "/Users/ana/con espacio")
        XCTAssertEqual(EmbeddedTerminalSession.localPath(fromOSC7: "file://MI-MAC/tmp", localHostNames: local), "/tmp")
        XCTAssertEqual(EmbeddedTerminalSession.localPath(fromOSC7: "file:///tmp", localHostNames: local), "/tmp")
        XCTAssertEqual(EmbeddedTerminalSession.localPath(fromOSC7: "file://localhost/tmp", localHostNames: local), "/tmp")
        XCTAssertEqual(EmbeddedTerminalSession.localPath(fromOSC7: "/tmp", localHostNames: local), "/tmp")
        XCTAssertNil(EmbeddedTerminalSession.localPath(fromOSC7: "file://servidor/tmp", localHostNames: local))
        XCTAssertNil(EmbeddedTerminalSession.localPath(fromOSC7: "https://mi-mac.local/tmp", localHostNames: local))
        XCTAssertNil(EmbeddedTerminalSession.localPath(fromOSC7: "", localHostNames: local))
    }

    func test_shellEnvironment_dropsHostTerminalVariables_andDerivesLang() {
        let env = Set(EmbeddedTerminalSession.shellEnvironment(base: [
            "PATH": "/usr/bin", "TERM_PROGRAM": "iTerm.app", "TERM_SESSION_ID": "x",
            "ITERM_PROFILE": "Default", "COLUMNS": "80", "HOME": "/Users/ana",
        ]))
        XCTAssertTrue(env.contains("TERM_PROGRAM=Dotphin"))
        XCTAssertTrue(env.contains("TERM=xterm-256color"))
        XCTAssertTrue(env.contains("HOME=/Users/ana"))
        XCTAssertFalse(env.contains { $0.hasPrefix("ITERM_") || $0.hasPrefix("TERM_SESSION") || $0.hasPrefix("COLUMNS=") })

        XCTAssertEqual(EmbeddedTerminalSession.defaultLanguage(locale: Locale(identifier: "es_AR")), "es_AR.UTF-8")
        XCTAssertEqual(EmbeddedTerminalSession.defaultLanguage(locale: Locale(identifier: "en")), "en_US.UTF-8")
    }

    func test_stopThenStart_launchesAFreshShell() {
        session.startIfNeeded(initialDirectory: dirA)
        let first = session.terminalView
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })

        session.stop()
        XCTAssertFalse(session.isRunning)

        session.startIfNeeded(initialDirectory: dirB)
        XCTAssertTrue(session.isRunning)
        XCTAssertFalse(first === session.terminalView)
        XCTAssertTrue(waitUntil { shellIsIn(dirB) })
    }

    func test_symlinkedDirectory_isNotReportedBackAsADifferentFolder() throws {
        // /tmp → /private/tmp: la shell informa la ruta real, Dotphin la del enlace.
        let link = tempDir.appendingPathComponent("enlace", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dirA)
        var reported: URL?
        session.onDirectoryChanged = { reported = $0 }
        session.startIfNeeded(initialDirectory: link)
        session.noteUserSubmittedLine()
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })
        session.terminalView?.send(txt: " true\r")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNil(reported)
    }

    func test_keyClassification_returnSubmits_andControlBacktickBelongsToTheMenu() throws {
        func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            ))
        }
        let f4 = String(Character(UnicodeScalar(NSF4FunctionKey)!))

        XCTAssertTrue(DotphinTerminalView.submitsLine(try key("\r", code: 36)))
        XCTAssertTrue(DotphinTerminalView.submitsLine(try key("\u{03}", code: 76)))
        XCTAssertFalse(DotphinTerminalView.submitsLine(try key("a", code: 0)))

        XCTAssertTrue(DotphinTerminalView.isPanelShortcut(try key("`", code: 50, flags: [.control])))
        XCTAssertTrue(DotphinTerminalView.isPanelShortcut(try key("~", code: 50, flags: [.control, .shift])))
        XCTAssertFalse(DotphinTerminalView.isPanelShortcut(try key("`", code: 50)))
        XCTAssertFalse(DotphinTerminalView.isPanelShortcut(try key("`", code: 50, flags: [.command])))
        XCTAssertFalse(DotphinTerminalView.isPanelShortcut(try key("a", code: 0, flags: [.control])))
        // F4 llega como ⌃` gracias a `FunctionKeyShortcuts`.
        XCTAssertEqual(
            FunctionKeyShortcuts.menuShortcut(for: try key(f4, code: 118, flags: [.function])),
            .init(characters: "`", keyCode: 50, modifiers: .control)
        )
    }

    func test_focusedTerminal_givesControlBacktickToTheMenu_andReturnMarksAUserCommand() throws {
        final class MenuTarget: NSObject {
            var fired = 0
            @objc func toggle(_ sender: Any?) { fired += 1 }
        }
        let target = MenuTarget()
        let mainMenu = NSMenu()
        let viewItem = NSMenuItem(title: "Ver", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "Ver")
        let toggleItem = NSMenuItem(title: "Terminal", action: #selector(MenuTarget.toggle(_:)), keyEquivalent: "`")
        toggleItem.keyEquivalentModifierMask = [.control]
        toggleItem.target = target
        viewMenu.addItem(toggleItem)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        let previousMenu = NSApp.mainMenu
        NSApp.mainMenu = mainMenu
        defer { NSApp.mainMenu = previousMenu }

        let window = NSWindow(contentViewController: NSHostingController(rootView: EmbeddedTerminalPanelView(
            session: session, currentDirectory: dirA, onOpenExternalTerminal: {}, onClose: {}
        ).frame(width: 700, height: 300)))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        XCTAssertTrue(waitUntil(timeout: 3) { session.terminalView.map { window.firstResponder === $0 } ?? false })

        func send(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            )))
        }

        try send("`", code: 50, flags: [.control])
        XCTAssertEqual(target.fired, 1)

        XCTAssertFalse(session.hasUserExecutedCommand)
        try send("\r", code: 36)
        XCTAssertTrue(session.hasUserExecutedCommand)
    }

    func test_panel_mountsSwiftTermViewAndFocusesIt() throws {
        let panel = EmbeddedTerminalPanelView(
            session: session,
            currentDirectory: dirA,
            onOpenExternalTerminal: {},
            onClose: {}
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: panel.frame(width: 700, height: 300)))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        XCTAssertTrue(waitUntil(timeout: 3) { session.terminalView?.window === window })
        let terminalView = try XCTUnwrap(session.terminalView)
        XCTAssertTrue(waitUntil(timeout: 3) { window.firstResponder === terminalView })
        XCTAssertGreaterThan(terminalView.bounds.width, 300)
        XCTAssertTrue(waitUntil { shellIsIn(dirA) })
    }
}
