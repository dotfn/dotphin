import XCTest
@testable import DolphinForMacOS

final class ViewPropertiesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_propertiesForNeverVisitedFolder_returnsDefaults() {
        let store = ViewPropertiesStore(defaults: defaults)
        let props = store.properties(for: URL(fileURLWithPath: "/tmp/never-visited"))
        XCTAssertEqual(props, ViewProperties())
    }

    func test_setThenGet_roundTrips() {
        let store = ViewPropertiesStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/some-folder")
        var props = ViewProperties()
        props.mode = .icons
        props.sortField = .size
        props.ascending = false
        props.zoomLevel = 1.5
        store.setProperties(props, for: url)
        XCTAssertEqual(store.properties(for: url), props)
    }

    func test_differentFolders_haveIndependentProperties() {
        let store = ViewPropertiesStore(defaults: defaults)
        let a = URL(fileURLWithPath: "/tmp/a")
        let b = URL(fileURLWithPath: "/tmp/b")
        var propsA = ViewProperties()
        propsA.mode = .details
        store.setProperties(propsA, for: a)
        XCTAssertEqual(store.properties(for: b), ViewProperties())
        XCTAssertEqual(store.properties(for: a), propsA)
    }
}
