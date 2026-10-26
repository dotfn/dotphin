import XCTest
@testable import DolphinForMacOS

final class TerminalLauncherTests: XCTestCase {
    func test_launchArguments_opensTerminalAtGivenPath() {
        let url = URL(fileURLWithPath: "/tmp/some folder")
        let args = TerminalLauncher().launchArguments(for: url)
        XCTAssertEqual(args, ["-a", "Terminal", "/tmp/some folder"])
    }
}
