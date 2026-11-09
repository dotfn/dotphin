import XCTest
@testable import Dotphin

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

    func test_startupURL_home_isHomeDirectory() {
        var settings = AppSettings()
        settings.startupLocation = .home
        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_startupURL_desktop_isDesktopFolder() {
        var settings = AppSettings()
        settings.startupLocation = .desktop
        XCTAssertEqual(
            settings.startupURL,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        )
    }

    func test_startupURL_customExistingPath_usesThatPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = tempDir.path

        XCTAssertEqual(settings.startupURL.standardizedFileURL.path, tempDir.standardizedFileURL.path)
    }

    func test_startupURL_customMissingPath_fallsBackToHome() {
        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = "/no/existe/esta/carpeta/\(UUID().uuidString)"

        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_startupURL_customWithNilPath_fallsBackToHome() {
        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = nil

        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_settings_decodingOldBlobMissingNewKeys_keepsOldValuesAndDefaultsTheRest() {
        let oldBlob = """
        {"defaultViewMode":"details","showsHiddenFiles":true}
        """.data(using: .utf8)!
        defaults.set(oldBlob, forKey: "appSettings")

        let store = AppSettingsStore(defaults: defaults)
        let settings = store.settings()

        XCTAssertEqual(settings.defaultViewMode, .details, "un valor guardado antes de este slice no debe perderse")
        XCTAssertEqual(settings.showsHiddenFiles, true, "un valor guardado antes de este slice no debe perderse")
        XCTAssertEqual(settings.startupLocation, .home, "una clave nueva ausente debe usar su default, no romper el decode entero")
        XCTAssertNil(settings.customStartupPath)
        XCTAssertFalse(settings.showsToolbarLabels)
        XCTAssertEqual(settings.toolbarGroups, ToolbarActionItem.defaultGroups)
    }

    func test_defaultToolbarGroups_groupsItemsIntelligentlyByCategory() {
        let defaults = ToolbarActionItem.defaultGroups
        XCTAssertEqual(
            defaults,
            [
                [.back, .forward, .up],
                [.viewMode],
                [.sort],
                [.newFolder, .rename, .delete],
                [.split, .newTab, .infoPanel],
                [.terminal, .search]
            ]
        )
    }

    func test_toggleLabel_togglesPerItemAndRespectsGlobalFlag() {
        var settings = AppSettings()
        XCTAssertFalse(settings.showsLabel(for: .terminal))

        settings.toggleLabel(for: .terminal)
        XCTAssertTrue(settings.showsLabel(for: .terminal))
        XCTAssertFalse(settings.showsLabel(for: .split))

        settings.toggleLabel(for: .terminal)
        XCTAssertFalse(settings.showsLabel(for: .terminal))

        settings.showsToolbarLabels = true
        XCTAssertTrue(settings.showsLabel(for: .terminal))
        XCTAssertTrue(settings.showsLabel(for: .split))

        settings.toggleLabel(for: .terminal)
        XCTAssertFalse(settings.showsLabel(for: .terminal))
        XCTAssertTrue(settings.showsLabel(for: .split))
    }

    func test_toolbarLayoutEngine_regroupsAndSeparatesItems() {
        var groups = ToolbarActionItem.defaultGroups
        // Separate .up out of the navigation group [.back, .forward, .up]
        groups = ToolbarLayoutEngine.separateItem(.up, in: groups)
        XCTAssertEqual(groups[0], [.back, .forward])
        XCTAssertEqual(groups[1], [.up])

        // Regroup .up back into group 0 at index 2
        groups = ToolbarLayoutEngine.apply(
            dropTarget: .joinGroup(groupIndex: 0, insertIndex: 2),
            draggingItem: .up,
            to: groups
        )
        XCTAssertEqual(groups[0], [.back, .forward, .up])

        // Move .search to index 0 as a separate group
        groups = ToolbarLayoutEngine.apply(
            dropTarget: .separateGroup(atIndex: 0, indicatorX: 0),
            draggingItem: .search,
            to: groups
        )
        XCTAssertEqual(groups[0], [.search])
        XCTAssertEqual(groups[1], [.back, .forward, .up])
    }

    func test_applyConfigEntries_managesSeparatorsExpandingSpacerAndHiddenActions() {
        var settings = AppSettings()
        let customEntries: [ToolbarConfigEntry] = [
            .action(.back),
            .divider(UUID()),
            .action(.forward),
            .fixedSpacer(UUID()),
            .action(.viewMode),
            .expandingSpacer,
            .action(.newFolder),
            .action(.search)
        ]

        settings.applyConfigEntries(customEntries)

        let visibleGroups = settings.toolbarGroups.compactMap { group -> [ToolbarActionItem]? in
            let filtered = group.filter { !settings.hiddenToolbarItems.contains($0) }
            return filtered.isEmpty ? nil : filtered
        }
        XCTAssertEqual(visibleGroups, [[.back, .forward], [.viewMode], [.newFolder, .search]])
        XCTAssertTrue(settings.dividersAfterItems.contains(.back))
        XCTAssertTrue(settings.fixedSpacesAfterGroupIndices.contains(0))
        XCTAssertEqual(settings.spacerAfterGroupIndex, 1)
        XCTAssertTrue(settings.hiddenToolbarItems.contains(.terminal))
        XCTAssertFalse(settings.hiddenToolbarItems.contains(.newFolder))
    }

    func test_layoutPlan_overflowsBySemanticPriorityAndProtectsNewTabOverFileActions() {
        let groups: [[ToolbarActionItem]] = [
            [.back, .forward, .up],
            [.viewMode],
            [.sort],
            [.rename, .newFolder, .delete],
            [.newTab],
            [.infoPanel, .split, .terminal, .search]
        ]

        // Wide enough for all items
        let fullPlan = ToolbarLayoutEngine.layoutPlan(for: groups, availableWidth: 800)
        XCTAssertTrue(fullPlan.overflowItems.isEmpty)

        // Step down width gradually and record the exact order items enter overflow
        var seenOverflowOrder: [ToolbarActionItem] = []
        for width in stride(from: 700.0, through: 290.0, by: -2.0) {
            let plan = ToolbarLayoutEngine.layoutPlan(for: groups, availableWidth: CGFloat(width))
            for item in plan.overflowItems where !seenOverflowOrder.contains(item) {
                seenOverflowOrder.append(item)
            }
            // Core items must always remain visible
            let visibleFlat = plan.visibleGroups.flatMap(\.items)
            XCTAssertTrue(visibleFlat.contains(.back))
            XCTAssertTrue(visibleFlat.contains(.forward))
            XCTAssertTrue(visibleFlat.contains(.viewMode))
            XCTAssertTrue(visibleFlat.contains(.search))
        }

        // Expected removal order: terminal, split, infoPanel, delete, rename, newFolder, newTab, sort, up
        XCTAssertEqual(
            seenOverflowOrder,
            [.terminal, .split, .infoPanel, .delete, .rename, .newFolder, .newTab, .sort, .up]
        )
    }

    func test_expandingSpacerVisibleOffsets_keepsSearchRightAlignedEvenWhenPrecedingGroupOverflows() {
        let groups: [[ToolbarActionItem]] = [
            [.back, .forward, .up],
            [.viewMode],
            [.sort],
            [.rename, .newFolder, .delete],
            [.newTab],
            [.infoPanel, .split, .terminal, .search]
        ]

        // Even when group 4 ([.newTab]) and group 3 ([.rename, .newFolder, .delete]) have overflowed,
        // the spacer configured after group 4 must still appear before group 5 ([.search]).
        let narrowPlan = ToolbarLayoutEngine.layoutPlan(for: groups, availableWidth: 430)
        let offsets = ToolbarLayoutEngine.expandingSpacerVisibleOffsets(
            for: narrowPlan.visibleGroups,
            fixedSpacesAfterGroupIndices: [4],
            spacerAfterGroupIndex: nil
        )
        XCTAssertFalse(offsets.isEmpty)
        XCTAssertEqual(narrowPlan.visibleGroups.last?.items, [.search])
        XCTAssertTrue(offsets.contains(narrowPlan.visibleGroups.count - 2))
    }
}
