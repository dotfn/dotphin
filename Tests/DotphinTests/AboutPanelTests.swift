import AppKit
import XCTest
@testable import Dotphin

@MainActor
final class AboutPanelTests: XCTestCase {
    func test_credits_showTaglineAndLinkToSite() {
        let credits = AboutPanel.credits
        XCTAssertTrue(credits.string.contains(AppInfo.tagline))

        let linkRange = (credits.string as NSString).range(of: "dotfn.dev")
        let link = credits.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
        XCTAssertEqual(link, URL(string: "https://dotfn.dev"))
    }

    func test_version_isSemVerWithPrereleaseTag() {
        XCTAssertEqual(AppInfo.version, "0.1.0-beta.1")
        XCTAssertTrue(AppInfo.copyright.contains("●fn"))
    }
}
