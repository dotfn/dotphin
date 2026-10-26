import XCTest
@testable import DolphinForMacOS

final class TerminalLauncherTests: XCTestCase {
    func test_launchArguments_opensTerminalAtGivenPath() {
        let url = URL(fileURLWithPath: "/tmp/some folder")
        let args = TerminalLauncher().launchArguments(for: url)
        XCTAssertEqual(args, ["-a", "Terminal", "/tmp/some folder"])
    }

    func test_openTerminal_throwsWhenPathDoesNotExist() {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-does-not-exist")
        XCTAssertThrowsError(try TerminalLauncher().openTerminal(at: missing)) { error in
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
}
