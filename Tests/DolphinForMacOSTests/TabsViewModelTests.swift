import XCTest
@testable import DolphinForMacOS

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
}
