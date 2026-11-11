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

    func test_keyClassification_returnSubmits_andF4BelongsToTheMenu() throws {
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

        XCTAssertTrue(DotphinTerminalView.isPanelShortcut(try key(f4, code: 118)))
        XCTAssertTrue(DotphinTerminalView.isPanelShortcut(try key(f4, code: 118, flags: [.shift])))
        XCTAssertFalse(DotphinTerminalView.isPanelShortcut(try key(f4, code: 118, flags: [.control])))
        XCTAssertFalse(DotphinTerminalView.isPanelShortcut(try key("a", code: 0)))
    }

    func test_focusedTerminal_givesF4ToTheMenu_andReturnMarksAUserCommand() throws {
        final class MenuTarget: NSObject {
            var fired = 0
            @objc func toggle(_ sender: Any?) { fired += 1 }
        }
        let target = MenuTarget()
        let f4 = String(Character(UnicodeScalar(NSF4FunctionKey)!))
        let mainMenu = NSMenu()
        let viewItem = NSMenuItem(title: "Ver", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "Ver")
        let toggleItem = NSMenuItem(title: "Terminal", action: #selector(MenuTarget.toggle(_:)), keyEquivalent: f4)
        toggleItem.keyEquivalentModifierMask = []
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

        func send(_ chars: String, code: UInt16) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            )))
        }

        try send(f4, code: 118)
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
