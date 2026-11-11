import XCTest
@testable import Dotphin

@MainActor
final class TabsViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_startsWithOneTabSelected() {
        let vm = TabsViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.tabs.count, 1)
        XCTAssertEqual(vm.selectedTabID, vm.tabs[0].id)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, tempDir)
    }

    func test_addTab_appendsAndSelectsIt_atGivenURL() {
        let vm = TabsViewModel(startingAt: tempDir)
        let sub = tempDir.appendingPathComponent("sub")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        vm.addTab(startingAt: sub)
        XCTAssertEqual(vm.tabs.count, 2)
        XCTAssertEqual(vm.selectedTabID, vm.tabs[1].id)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, sub)
    }

    func test_closeTab_removesItAndSelectsAnotherValidTab() {
        let vm = TabsViewModel(startingAt: tempDir)
        vm.addTab(startingAt: tempDir)
        let firstID = vm.tabs[0].id
        let secondID = vm.tabs[1].id
        vm.closeTab(secondID)
        XCTAssertEqual(vm.tabs.map(\.id), [firstID])
        XCTAssertEqual(vm.selectedTabID, firstID)
    }

    func test_closeTab_onLastRemainingTab_doesNothing() {
        let vm = TabsViewModel(startingAt: tempDir)
        let onlyID = vm.tabs[0].id
        vm.closeTab(onlyID)
        XCTAssertEqual(vm.tabs.count, 1)
        XCTAssertEqual(vm.tabs[0].id, onlyID)
    }

    func test_toggleSplit_addsSecondaryAtSamePrimaryURL_thenRemovesIt() {
        let vm = TabsViewModel(startingAt: tempDir)
        let id = vm.selectedTabID
        vm.toggleSplit(for: id)
        XCTAssertTrue(vm.selectedTab!.isSplit)
        XCTAssertEqual(vm.selectedTab!.secondary?.currentURL, tempDir)

        vm.setFocusedPane(1, for: id)
        vm.toggleSplit(for: id)
        XCTAssertFalse(vm.selectedTab!.isSplit)
        XCTAssertEqual(vm.selectedTab!.focusedPaneIndex, 0, "al perder el panel secundario, el foco vuelve al primario")
    }

    func test_setFocusedPane_ignoredWhenNotSplit() {
        let vm = TabsViewModel(startingAt: tempDir)
        let id = vm.selectedTabID
        vm.setFocusedPane(1, for: id)
        XCTAssertEqual(vm.selectedTab!.focusedPaneIndex, 0)
    }

    func test_selectingAnotherTab_doesNotAffectOtherTabsState() {
        let vm = TabsViewModel(startingAt: tempDir)
        let sub = tempDir.appendingPathComponent("sub")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        vm.addTab(startingAt: sub)
        let firstID = vm.tabs[0].id
        vm.selectTab(firstID)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, tempDir)
        XCTAssertEqual(vm.tabs[1].primary.currentURL, sub, "la otra pestaña no debió cambiar")
    }

    // MARK: Sesión por ventana

    private func makeDefaults() -> UserDefaults {
        let name = "TabsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Una ventana de la app: no restaura al crearse, sino con `beginSession`.
    private func makeWindow(defaults: UserDefaults) -> TabsViewModel {
        TabsViewModel(startingAt: tempDir, rememberOpenedTabs: true, restoresSession: false, defaults: defaults)
    }

    func test_twoWindows_keepSeparateSessions() throws {
        let defaults = makeDefaults()
        let dirA = try makeDir("a")
        let dirB = try makeDir("b")

        let windowA = makeWindow(defaults: defaults)
        windowA.beginSession(id: "A", fallingBackToLastSession: false)
        windowA.addTab(startingAt: dirA)
        let windowB = makeWindow(defaults: defaults)
        windowB.beginSession(id: "B", fallingBackToLastSession: false)
        windowB.addTab(startingAt: dirB)
        windowB.addTab(startingAt: dirB)

        // El sistema restaura las dos ventanas: cada una vuelve con lo suyo.
        let restoredA = makeWindow(defaults: defaults)
        restoredA.beginSession(id: "A", fallingBackToLastSession: false)
        let restoredB = makeWindow(defaults: defaults)
        restoredB.beginSession(id: "B", fallingBackToLastSession: false)

        XCTAssertEqual(restoredA.tabs.map(\.primary.currentURL.standardizedFileURL), [tempDir, dirA].map(\.standardizedFileURL))
        XCTAssertEqual(restoredB.tabs.map(\.primary.currentURL.standardizedFileURL), [tempDir, dirB, dirB].map(\.standardizedFileURL))
    }

    func test_newWindow_startsFresh_andFirstWindowResumesLastUsedSession() throws {
        let defaults = makeDefaults()
        let dirA = try makeDir("a")
        let previous = makeWindow(defaults: defaults)
        previous.beginSession(id: "anterior", fallingBackToLastSession: false)
        previous.addTab(startingAt: dirA)

        // Otro arranque, sin restauración del sistema: ids nuevos.
        let first = makeWindow(defaults: defaults)
        first.beginSession(id: "primera", fallingBackToLastSession: true)
        XCTAssertEqual(first.tabs.count, 2, "la primera ventana retoma la última sesión")

        let second = makeWindow(defaults: defaults)
        second.beginSession(id: "segunda", fallingBackToLastSession: false)
        XCTAssertEqual(second.tabs.count, 1, "una ventana nueva no repite la sesión de la otra")
    }

    func test_sessionSavedWithTheOldSingleKey_isStillRestored() throws {
        let defaults = makeDefaults()
        let dirA = try makeDir("a")
        let old = TabSessionSnapshot(
            entries: [
                TabSessionEntry(primaryPath: tempDir.path, secondaryPath: nil, focusedPaneIndex: 0),
                TabSessionEntry(primaryPath: dirA.path, secondaryPath: nil, focusedPaneIndex: 0),
            ],
            selectedIndex: 1
        )
        defaults.set(try JSONEncoder().encode(old), forKey: "tabsSessionSnapshot.v1")

        let window = makeWindow(defaults: defaults)
        window.beginSession(id: "primera", fallingBackToLastSession: true)
        XCTAssertEqual(window.tabs.count, 2)
        XCTAssertEqual(window.selectedTab?.primary.currentURL.standardizedFileURL, dirA.standardizedFileURL)
    }
}
