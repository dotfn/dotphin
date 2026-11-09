import XCTest
@testable import Dotphin

final class MultiSelectionTests: XCTestCase {
    private var tempDir: URL!
    private var vm: BrowserViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt", "d.txt"] {
            try "x".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func item(_ name: String) -> FileItem { vm.items.first { $0.name == name }! }

    func test_toggleSelection_addsAndRemoves_andSelectedItemOnlyWhenSingle() {
        vm.select(item("a.txt"))
        XCTAssertEqual(vm.selectedItem?.name, "a.txt")
        vm.toggleSelection(item("c.txt"))
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["a.txt", "c.txt"])
        XCTAssertNil(vm.selectedItem)
        vm.toggleSelection(item("a.txt"))
        XCTAssertEqual(vm.selectedItem?.name, "c.txt")
    }

    func test_extendSelection_selectsRangeFromAnchor() {
        vm.select(item("b.txt"))
        vm.extendSelection(to: item("d.txt"))
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["b.txt", "c.txt", "d.txt"])
        vm.extendSelection(to: item("a.txt"))
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["a.txt", "b.txt"])
    }

    func test_selectAll_respectsFilter() {
        vm.filterText = "b"
        vm.selectAll()
        XCTAssertEqual(vm.selectedItems.map(\.name), ["b.txt"])
    }

    func test_deleteSelectedItems_trashesAllAndUndoRestores() throws {
        vm.select(item("a.txt"))
        vm.toggleSelection(item("b.txt"))
        vm.deleteSelectedItems()
        XCTAssertEqual(Set(vm.items.map(\.name)), ["c.txt", "d.txt"])
        XCTAssertTrue(vm.selectedIDs.isEmpty)
        vm.undo()
        XCTAssertEqual(Set(vm.items.map(\.name)), ["a.txt", "b.txt", "c.txt", "d.txt"])
    }

    func test_navigation_clearsSelection() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        vm.refresh()
        vm.select(item("a.txt"))
        vm.navigate(to: sub)
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }

    func test_batchRenameFormatter_expandsHashSequenceWithZeroPaddingAndPreservesExtension() {
        let items = [item("a.txt"), item("b.txt"), item("c.txt")]
        let planned = BatchRenameFormatter.plannedRenames(for: items, pattern: "Foto_###", startIndex: 5)
        XCTAssertEqual(planned.map(\.newName), ["Foto_005.txt", "Foto_006.txt", "Foto_007.txt"])
    }

    func test_batchRenameFormatter_withoutHash_appendsSequenceNumber() {
        let items = [item("a.txt"), item("b.txt")]
        let planned = BatchRenameFormatter.plannedRenames(for: items, pattern: "Doc_", startIndex: 1)
        XCTAssertEqual(planned.map(\.newName), ["Doc_1.txt", "Doc_2.txt"])
    }

    func test_batchRenameSelected_renamesAllKeepsSelectionAndUndoRestores() {
        vm.select(item("a.txt"))
        vm.toggleSelection(item("b.txt"))
        vm.batchRenameSelected(pattern: "item_##", startIndex: 1)
        XCTAssertEqual(Set(vm.items.map(\.name)), ["item_01.txt", "item_02.txt", "c.txt", "d.txt"])
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["item_01.txt", "item_02.txt"])

        vm.undo()
        XCTAssertEqual(Set(vm.items.map(\.name)), ["a.txt", "b.txt", "c.txt", "d.txt"])
    }

    func test_duplicateSelected_createsCopiesSelectsThemAndUndoRestores() {
        vm.select(item("a.txt"))
        vm.toggleSelection(item("c.txt"))
        vm.duplicateSelected()
        XCTAssertTrue(vm.items.map(\.name).contains("a copy.txt"))
        XCTAssertTrue(vm.items.map(\.name).contains("c copy.txt"))
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["a copy.txt", "c copy.txt"])

        vm.undo()
        XCTAssertEqual(Set(vm.items.map(\.name)), ["a.txt", "b.txt", "c.txt", "d.txt"])
    }

    func test_invertSelection_flipsSelectedSetAmongFilteredItems() {
        vm.select(item("a.txt"))
        vm.invertSelection()
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["b.txt", "c.txt", "d.txt"])
    }

    func test_createFile_createsSelectsAndUndoRedoWorks() {
        vm.createFile(named: "note.md", contents: Data("# Hola".utf8))
        XCTAssertTrue(vm.items.map(\.name).contains("note.md"))
        XCTAssertEqual(vm.selectedItem?.name, "note.md")

        vm.undo()
        XCTAssertFalse(vm.items.map(\.name).contains("note.md"))

        vm.redo()
        XCTAssertTrue(vm.items.map(\.name).contains("note.md"))
    }

    func test_symbolicPermissions_and_computeTotalSize() throws {
        XCTAssertEqual(FilePropertiesSheetView.symbolicPermissions(0o755), "rwxr-xr-x")
        XCTAssertEqual(FilePropertiesSheetView.symbolicPermissions(0o644), "rw-r--r--")
        let size = FilePropertiesSheetView.computeTotalSize(of: tempDir)
        XCTAssertEqual(size, 4) // 4 files of 1 byte each
    }

    func test_applyPermissionsRecursively_appliesModeToEveryDescendant() throws {
        let root = tempDir.appendingPathComponent("permRoot", isDirectory: true)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let fileInRoot = root.appendingPathComponent("a.txt")
        let fileInSub = sub.appendingPathComponent("b.txt")
        try "x".write(to: fileInRoot, atomically: true, encoding: .utf8)
        try "y".write(to: fileInSub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileInRoot.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileInSub.path)

        let failures = FilePropertiesSheetView.applyPermissionsRecursively(0o755, under: root)

        XCTAssertEqual(failures, [])
        for path in [root.path, sub.path, fileInRoot.path, fileInSub.path] {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
            XCTAssertEqual(perms & 0o777, 0o755, "no se aplicó el modo recursivamente a \(path)")
        }
    }

    func test_applyPermissionsRecursively_neverFollowsSymlinksOutOfTheFolder() throws {
        let root = tempDir.appendingPathComponent("permRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("outside.txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link-out"),
            withDestinationURL: outside
        )

        FilePropertiesSheetView.applyPermissionsRecursively(0o755, under: root)

        let attrs = try FileManager.default.attributesOfItem(atPath: outside.path)
        XCTAssertEqual(((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
    }

    func test_applyPermissionsRecursively_removingExecuteStillReachesTheWholeTree() throws {
        let root = tempDir.appendingPathComponent("permRoot", isDirectory: true)
        let deepDir = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let deepFile = deepDir.appendingPathComponent("deep.txt")
        try "x".write(to: deepFile, atomically: true, encoding: .utf8)
        let allPaths = [root, root.appendingPathComponent("a"), deepDir, deepFile].map(\.path)
        defer {
            // Restore traversal so tearDown can delete the tree.
            for path in allPaths {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }

        let failures = FilePropertiesSheetView.applyPermissionsRecursively(0o644, under: root)

        XCTAssertEqual(failures, [])
        for path in [root.path, root.appendingPathComponent("a").path, deepDir.path] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: deepFile.path)
        XCTAssertEqual(((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o644)
    }

    func test_applyPermissionsRecursively_countsUnreadableSubfolderAsFailure() throws {
        let root = tempDir.appendingPathComponent("permRoot", isDirectory: true)
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let failures = FilePropertiesSheetView.applyPermissionsRecursively(0o700, under: root)

        XCTAssertFalse(failures.isEmpty, "una subcarpeta ilegible no puede contar como aplicada")
    }
}
