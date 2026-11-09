import XCTest
@testable import Dotphin

final class BrowserViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_loadsItemsForStartingURL() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"])
        XCTAssertNil(vm.error)
    }

    func test_navigateToSubfolder_updatesCurrentURLAndItems() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.navigate(to: sub)
        XCTAssertEqual(vm.currentURL, sub)
        XCTAssertEqual(vm.items, [])
    }

    func test_goUp_movesToParentDirectory() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: sub)
        vm.goUp()
        XCTAssertEqual(vm.currentURL, tempDir)
    }

    func test_navigateToDeletedDirectory_setsNotFoundError_doesNotCrash() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        try FileManager.default.removeItem(at: sub)
        vm.navigate(to: sub)
        XCTAssertEqual(vm.error, .notFound(sub))
        XCTAssertEqual(vm.items, [])
    }

    func test_init_loadsViewPropertiesForStartingFolder() throws {
        let store = ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        var saved = ViewProperties()
        saved.mode = .icons
        store.setProperties(saved, for: tempDir)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        XCTAssertEqual(vm.viewProperties.mode, .icons)
    }

    func test_setViewMode_persistsAndDoesNotRereadDisk() throws {
        try "a".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ViewPropertiesStore(defaults: suite)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("a.txt"))
        vm.setViewMode(.icons)
        XCTAssertEqual(vm.viewProperties.mode, .icons)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"], "no debió re-leer el disco al cambiar el modo")
        XCTAssertEqual(store.properties(for: tempDir).mode, .icons)
    }

    func test_setSort_reordersWithoutError() throws {
        try "12345".write(to: tempDir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try "1234567890".write(to: tempDir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.setSort(field: .size, ascending: false)
        XCTAssertEqual(vm.items.map(\.name), ["big.txt", "small.txt"])
    }

    func test_setZoomLevel_persists() throws {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ViewPropertiesStore(defaults: suite)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        vm.setZoomLevel(1.8)
        XCTAssertEqual(vm.viewProperties.zoomLevel, 1.8)
        XCTAssertEqual(store.properties(for: tempDir).zoomLevel, 1.8)
    }

    func test_select_setsSelectedItem() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        let item = vm.items[0]
        vm.select(item)
        XCTAssertEqual(vm.selectedItem, item)
    }

    func test_navigate_clearsSelection() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.navigate(to: sub)
        XCTAssertNil(vm.selectedItem)
    }

    func test_filteredItems_withEmptyFilter_returnsAllItems() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func test_filteredItems_matchesCaseInsensitiveSubstring() throws {
        try "x".write(to: tempDir.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.filterText = "report"
        XCTAssertEqual(vm.filteredItems.map(\.name), ["Report.txt"])
    }

    func test_filteredItems_noMatch_returnsEmpty() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.filterText = "zzz"
        XCTAssertEqual(vm.filteredItems, [])
    }

    func test_navigate_clearsFilterText() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.filterText = "algo"
        vm.navigate(to: sub)
        XCTAssertEqual(vm.filterText, "")
    }

    func test_settingFilter_clearsSelectionIfItHidesTheSelectedItem() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.filterText = "zzz"
        XCTAssertNil(vm.selectedItem)
    }

    func test_settingFilter_keepsSelectionIfStillVisible() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.filterText = "a"
        XCTAssertNotNil(vm.selectedItem)
    }

    func test_renameSelected_renamesAndRefreshes() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.renameSelected(to: "b.txt")
        XCTAssertEqual(vm.items.map(\.name), ["b.txt"])
        XCTAssertNil(vm.operationError)
    }

    func test_renameSelected_toExistingName_setsOperationError_doesNotRefresh() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.renameSelected(to: "b.txt")
        XCTAssertNotNil(vm.operationError)
        XCTAssertEqual(vm.items.map(\.name).sorted(), ["a.txt", "b.txt"])
    }

    func test_deleteSelected_removesItemAndClearsSelection() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.deleteSelected()
        XCTAssertEqual(vm.items, [])
        XCTAssertNil(vm.selectedItem)
    }

    func test_createFolder_addsNewFolderToItems() throws {
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.createFolder(named: "Nueva carpeta")
        XCTAssertEqual(vm.items.map(\.name), ["Nueva carpeta"])
    }

    func test_clearOperationError_clearsIt() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.renameSelected(to: "b.txt")
        vm.clearOperationError()
        XCTAssertNil(vm.operationError)
    }

    func test_renameSelected_reselectsTheRenamedItem_notTheOldGhost() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.renameSelected(to: "b.txt")
        XCTAssertEqual(vm.selectedItem?.name, "b.txt")
        XCTAssertEqual(vm.selectedItem?.url.lastPathComponent, "b.txt")
    }

    func test_refresh_clearsSelectionIfTheSelectedItemNoLongerExists() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("a.txt"))
        vm.refresh()
        XCTAssertNil(vm.selectedItem)
    }

    func test_renameSelected_toHiddenName_isRejectedAsInvalid() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.renameSelected(to: ".a.txt")
        XCTAssertEqual(vm.operationError, .invalidName)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"], "no debió renombrarse")
    }

    func test_delete_removesGivenItemRegardlessOfSelection() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        let itemB = vm.items.first { $0.name == "b.txt" }!
        vm.select(vm.items.first { $0.name == "a.txt" })
        vm.delete(itemB)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"])
        XCTAssertEqual(vm.selectedItem?.name, "a.txt", "borrar otro ítem no debe tocar la selección actual")
    }

    func test_performSearch_findsNestedMatch() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.searchQuery = "report"
        vm.performSearch()
        XCTAssertEqual(vm.searchResults.map(\.name), ["Report.txt"])
    }

    func test_navigate_clearsSearch() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.searchQuery = "algo"
        vm.performSearch()
        vm.navigate(to: sub)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertEqual(vm.searchResults, [])
    }

    func test_settingSearchQuery_clearsStaleSelectionFromBrowseMode() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.searchQuery = "report"
        XCTAssertNil(vm.selectedItem, "la selección de modo navegación no debe sobrevivir invisible durante una búsqueda")
    }

    func test_delete_duringActiveSearch_refreshesSearchResultsToo() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.searchQuery = "report"
        vm.performSearch()
        let found = vm.searchResults[0]
        vm.delete(found)
        XCTAssertEqual(vm.searchResults, [], "el resultado borrado no debe seguir apareciendo en la búsqueda")
    }

    func test_emptyTrash_removesItemsAndRefreshes() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir, trashURL: tempDir)
        vm.emptyTrash()
        XCTAssertEqual(vm.items, [])
        XCTAssertNil(vm.operationError)
    }

    func test_emptyTrash_whenNotBrowsingTrash_doesNothing() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let otherTrash = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: otherTrash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherTrash) }
        let vm = BrowserViewModel(startingAt: tempDir, trashURL: otherTrash)
        vm.emptyTrash()
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"], "no debió borrar nada: currentURL no es la papelera")
    }

    func test_emptyTrash_withPartialFailure_stillRefreshesWhatWasActuallyDeleted() throws {
        try "x".write(to: tempDir.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
        let locked = tempDir.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let vm = BrowserViewModel(startingAt: tempDir, trashURL: tempDir)
        vm.emptyTrash()
        XCTAssertNotNil(vm.operationError)
        XCTAssertEqual(vm.items.map(\.name), ["locked"], "ok.txt se borró de verdad y no debe seguir en la lista")
    }

    func test_restoreSelected_movesToHomeAndClearsSelection() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.select(vm.items[0])
        vm.restoreSelected()
        XCTAssertNil(vm.selectedItem)
        XCTAssertEqual(vm.items, [])
        let restoredPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("a.txt").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath))
        try? FileManager.default.removeItem(atPath: restoredPath)
    }

    private func runGit(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    func test_load_populatesGitStatusesForGitRepo() throws {
        try runGit(["init", "-q"], in: tempDir)
        try "x".write(to: tempDir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.gitStatuses["new.txt"], .untracked)
    }

    func test_moveDroppedItems_movesFileIntoTargetDirectory() throws {
        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)

        vm.moveDroppedItems([fileURL], into: destDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
        XCTAssertNil(vm.operationError)
    }

    func test_moveDroppedItems_whenOneFails_reportsErrorButMovesTheRest() throws {
        let okFile = tempDir.appendingPathComponent("ok.txt")
        try "x".write(to: okFile, atomically: true, encoding: .utf8)
        let conflictFile = tempDir.appendingPathComponent("conflict.txt")
        try "x".write(to: conflictFile, atomically: true, encoding: .utf8)
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "y".write(to: destDir.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)

        vm.moveDroppedItems([okFile, conflictFile], into: destDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: okFile.path), "el que no tenía conflicto se movió igual")
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictFile.path), "el que tenía conflicto se quedó donde estaba")
        XCTAssertNotNil(vm.operationError)
        let message = vm.operationError?.message ?? ""
        XCTAssertTrue(
            message.contains("Ya existe un ítem con ese nombre."),
            "el mensaje debe llevar el motivo real del fallo, no solo el nombre del archivo: \(message)"
        )
    }

    @MainActor
    func test_mountDiskImage_whenImageDoesNotExist_reportsErrorWithoutCrashing() async {
        let vm = BrowserViewModel(startingAt: tempDir)
        let missingImage = FileItem(
            url: tempDir.appendingPathComponent("\(UUID().uuidString).iso"),
            name: "missing.iso",
            isDirectory: false,
            isSymbolicLink: false,
            size: nil,
            modificationDate: nil
        )

        await vm.mountDiskImage(missingImage)

        XCTAssertNotNil(vm.operationError)
        XCTAssertFalse((vm.operationError?.message ?? "").isEmpty)
    }
}
