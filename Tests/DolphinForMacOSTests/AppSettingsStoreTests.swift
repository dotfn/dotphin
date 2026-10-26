import XCTest
@testable import DolphinForMacOS

final class AppSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_settings_withNoSavedEntry_returnsDefaults() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }

    func test_setThenGet_roundTrips() {
        let store = AppSettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.defaultViewMode = .icons
        settings.showsHiddenFiles = true
        store.setSettings(settings)
        XCTAssertEqual(store.settings(), settings)
    }

    func test_settings_withCorruptData_returnsDefaults() {
        defaults.set("not valid json".data(using: .utf8), forKey: "appSettings")
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }
}
