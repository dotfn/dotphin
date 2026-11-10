import AppKit
import XCTest
@testable import Dotphin

final class TerminalLauncherTests: XCTestCase {
    func test_terminalApp_isResolvedThroughLaunchServices() {
        XCTAssertNotNil(NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalLauncher.terminalBundleIdentifier))
    }

    func test_openTerminal_throwsWhenPathDoesNotExist() {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-does-not-exist")
        XCTAssertThrowsError(try TerminalLauncher().openTerminal(at: missing)) { error in
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
}
