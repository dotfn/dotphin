import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

final class DolphinFullParityTests: XCTestCase {
    private var tempDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "test.parity.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. Grouping (Show in Groups) & Sorting Options

    func test_groupedByName_bucketsByFirstLetterAndHashForNumbers() {
        let items = [
            FileItem(url: tempDir.appendingPathComponent("123.txt"), name: "123.txt", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("alpha.swift"), name: "alpha.swift", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("ardilla.swift"), name: "ardilla.swift", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("beta.md"), name: "beta.md", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
        ]
        let sorted = items.sorted(by: .name, ascending: true)
        let groups = sorted.grouped(by: .name)
        XCTAssertEqual(groups.map(\.title), ["#", "A", "B"])
        XCTAssertEqual(groups[1].items.map(\.name), ["alpha.swift", "ardilla.swift"])
    }

    func test_groupedBySize_bucketsFoldersAndSizeTiers() {
        let items = [
            FileItem(url: tempDir.appendingPathComponent("Docs"), name: "Docs", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("empty.txt"), name: "empty.txt", isDirectory: false, isSymbolicLink: false, size: 0, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("small.txt"), name: "small.txt", isDirectory: false, isSymbolicLink: false, size: 2048, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("medium.bin"), name: "medium.bin", isDirectory: false, isSymbolicLink: false, size: 5_000_000, modificationDate: nil),
        ]
        let groups = items.grouped(by: .size, foldersFirst: true)
        XCTAssertEqual(groups.map(\.title), ["Carpetas", "Vacío (0 B)", "Pequeño (< 1 MB)", "Mediano (1 MB – 100 MB)"])
    }

    func test_sortedWithFoldersFirstFalseAndHiddenLastTrue() {
        let items = [
            FileItem(url: tempDir.appendingPathComponent(".secret"), name: ".secret", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("zebraFolder"), name: "zebraFolder", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("apple.txt"), name: "apple.txt", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil),
        ]
        let sorted = items.sorted(by: .name, ascending: true, foldersFirst: false, hiddenLast: true)
        XCTAssertEqual(sorted.map(\.name), ["apple.txt", "zebraFolder", ".secret"])
    }

    // MARK: - 2. ViewProperties & Apply Scope (Subfolders / All Folders)

    func test_viewProperties_applyToSubfolders_propagatesToNestedDirectories() throws {
        let subA = tempDir.appendingPathComponent("SubA", isDirectory: true)
        let subB = subA.appendingPathComponent("SubB", isDirectory: true)
        try FileManager.default.createDirectory(at: subB, withIntermediateDirectories: true)

        let appStore = AppSettingsStore(defaults: defaults)
        let vpStore = ViewPropertiesStore(defaults: defaults, appSettingsStore: appStore)
        var customProps = ViewProperties(mode: .compact, sortField: .type, ascending: false, zoomLevel: 1.4, showInGroups: true)
        customProps.visibleDetailsColumns = [.type, .size, .permissions, .tags]

        vpStore.applyProperties(customProps, to: tempDir, scope: .currentAndSubfolders, useAsDefault: true)

        XCTAssertEqual(vpStore.properties(for: tempDir), customProps)
        XCTAssertEqual(vpStore.properties(for: subA), customProps)
        XCTAssertEqual(vpStore.properties(for: subB), customProps)
        XCTAssertEqual(appStore.settings().defaultViewMode, .compact)
    }

    // MARK: - 3. Pattern Selection & Selection Mode

    func test_selectItemsMatchingPattern_supportsGlobWildcardsAndAdditiveSelection() throws {
        try Data("1".utf8).write(to: tempDir.appendingPathComponent("main.swift"))
        try Data("2".utf8).write(to: tempDir.appendingPathComponent("helper.swift"))
        try Data("3".utf8).write(to: tempDir.appendingPathComponent("readme.md"))
        try Data("4".utf8).write(to: tempDir.appendingPathComponent("icon_1.png"))
        try Data("5".utf8).write(to: tempDir.appendingPathComponent("icon_2.png"))

        let vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )

        vm.selectItems(matchingPattern: "*.swift", additive: false)
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["main.swift", "helper.swift"])

        vm.selectItems(matchingPattern: "icon_?.png", additive: true)
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["main.swift", "helper.swift", "icon_1.png", "icon_2.png"])

        vm.deselectAll()
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }

    // MARK: - 4. Move to New Folder & .hidden File Action

    func test_moveSelectedToNewFolder_createsFolderMovesSelectionAndUndoesCleanly() throws {
        let file1 = tempDir.appendingPathComponent("uno.txt")
        let file2 = tempDir.appendingPathComponent("dos.txt")
        let file3 = tempDir.appendingPathComponent("tres.txt")
        try Data("a".utf8).write(to: file1)
        try Data("b".utf8).write(to: file2)
        try Data("c".utf8).write(to: file3)

        let vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        vm.setSelection([file1, file2])
        vm.moveSelectedToNewFolder(named: "Agrupados")

        XCTAssertEqual(Set(vm.items.map(\.name)), ["Agrupados", "tres.txt"])
        XCTAssertEqual(vm.selectedItem?.name, "Agrupados")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Agrupados/uno.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Agrupados/dos.txt").path))
    }

    func test_dotHiddenService_hidesAndUnhidesFilesInDirectoryReader() throws {
        let visibleFile = tempDir.appendingPathComponent("visible.txt")
        let secretFile = tempDir.appendingPathComponent("oculto_por_lista.txt")
        try Data("v".utf8).write(to: visibleFile)
        try Data("s".utf8).write(to: secretFile)

        let dotHidden = DotHiddenService()
        try dotHidden.hide(names: ["oculto_por_lista.txt"], in: tempDir)

        let normalReader = DirectoryReader(showsHiddenFiles: false)
        let normalItems = try normalReader.contents(of: tempDir)
        XCTAssertEqual(normalItems.map(\.name), ["visible.txt"])

        let allReader = DirectoryReader(showsHiddenFiles: true)
        let allItems = try allReader.contents(of: tempDir)
        let secretItem = allItems.first { $0.name == "oculto_por_lista.txt" }
        XCTAssertEqual(secretItem?.isHiddenInDotHidden, true)

        try dotHidden.unhide(names: ["oculto_por_lista.txt"], in: tempDir)
        let afterUnhide = try normalReader.contents(of: tempDir)
        XCTAssertEqual(Set(afterUnhide.map(\.name)), ["visible.txt", "oculto_por_lista.txt"])
    }

    // MARK: - 5. Custom Bookmarks & Recently Closed Tabs

    func test_placesProvider_customBookmarksAddAndRemove() {
        let provider = PlacesProvider(defaults: defaults)
        XCTAssertFalse(provider.isBookmarked(tempDir))

        provider.addBookmark(for: tempDir, name: "Mi Proyecto")
        XCTAssertTrue(provider.isBookmarked(tempDir))
        XCTAssertEqual(provider.customBookmarks().map(\.name), ["Mi Proyecto"])

        provider.removeBookmark(for: tempDir)
        XCTAssertFalse(provider.isBookmarked(tempDir))
        XCTAssertTrue(provider.customBookmarks().isEmpty)
    }

    func test_tabsViewModel_recordsAndReopensRecentlyClosedTabs() throws {
        let secondDir = tempDir.appendingPathComponent("Segunda", isDirectory: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)

        let tabsVM = TabsViewModel(startingAt: tempDir)
        tabsVM.addTab(startingAt: secondDir)
        XCTAssertEqual(tabsVM.tabs.count, 2)

        let secondTabID = tabsVM.tabs[1].id
        tabsVM.closeTab(secondTabID)

        XCTAssertEqual(tabsVM.tabs.count, 1)
        XCTAssertEqual(tabsVM.recentlyClosedTabs.count, 1)
        XCTAssertEqual(tabsVM.recentlyClosedTabs.first?.title, "Segunda")

        tabsVM.reopenLastClosedTab()
        XCTAssertEqual(tabsVM.tabs.count, 2)
        XCTAssertTrue(tabsVM.recentlyClosedTabs.isEmpty)
        XCTAssertEqual(tabsVM.selectedTab?.primary.currentURL.standardizedFileURL, secondDir.standardizedFileURL)
    }

    // MARK: - 6. Content Search & Size/Date Filters

    func test_searchService_contentSearchAndSizeFilter() throws {
        let codeFile = tempDir.appendingPathComponent("Notes.txt")
        let otherFile = tempDir.appendingPathComponent("Other.txt")
        try Data("Contiene la palabra mágica KdeDolphinMacOS adentro".utf8).write(to: codeFile)
        try Data("Texto común".utf8).write(to: otherFile)

        let service = SearchService()
        let byFilename = service.search(for: "KdeDolphinMacOS", in: tempDir, matchMode: .filename)
        XCTAssertTrue(byFilename.isEmpty)

        let byContent = service.search(for: "KdeDolphinMacOS", in: tempDir, matchMode: .content)
        XCTAssertEqual(byContent.map(\.name), ["Notes.txt"])

        let smallMatches = service.search(for: "KdeDolphinMacOS", in: tempDir, sizeFilter: .small, matchMode: .content)
        XCTAssertEqual(smallMatches.map(\.name), ["Notes.txt"])

        let largeMatches = service.search(for: "KdeDolphinMacOS", in: tempDir, sizeFilter: .large, matchMode: .content)
        XCTAssertTrue(largeMatches.isEmpty)
    }

    // MARK: - 7. Disk Usage Analyzer

    func test_diskUsageAnalyzer_sortsEntriesDescendingBySize() throws {
        let smallURL = tempDir.appendingPathComponent("chico.bin")
        let bigURL = tempDir.appendingPathComponent("grande.bin")
        try Data(repeating: 0xAA, count: 128).write(to: smallURL)
        try Data(repeating: 0xBB, count: 4096).write(to: bigURL)

        let entries = DiskUsageAnalyzerSheetView.analyzeDirectory(tempDir)
        XCTAssertEqual(entries.map(\.name), ["grande.bin", "chico.bin"])
        XCTAssertEqual(entries.first?.sizeBytes, 4096)
    }

    // MARK: - 8. Embedded Terminal Buffer & Zsh PROMPT_SP / PATH Handling

    func test_terminalScreenBuffer_handlesZshPromptSpCarriageReturnAndEraseInLine() {
        var buffer = TerminalScreenBuffer()
        // Simulate zsh's PROMPT_SP sequence: `%` + 99 spaces + `\r \r` + ESC[J + actual prompt
        let zshPromptSp = "\u{1B}[1m\u{1B}[7m%\u{1B}[27m\u{1B}[1m\u{1B}[0m"
            + String(repeating: " ", count: 99)
            + "\r \r\u{1B}[0m\u{1B}[27m\u{1B}[24m\u{1B}[Juser@Mac ~ % "
        buffer.feed(zshPromptSp)
        XCTAssertEqual(buffer.renderedText, "user@Mac ~ % ")

        // Simulate typing a command with backspace and Ctrl+U (ESC[2K \r)
        buffer.feed("ls -la\u{08}h\r\narchivo.txt\r\n")
        XCTAssertEqual(buffer.renderedText, "user@Mac ~ % ls -lh\narchivo.txt\n")

        let path = EmbeddedTerminalSession.enrichedDeveloperPath(existingPath: "/usr/bin:/bin")
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
        XCTAssertTrue(path.contains("/.local/bin"))
    }

    @objc static func hook_crashOnException(_ exception: NSException) {
        fputs("APPKIT CRASH ON EXCEPTION: \(exception.name.rawValue) — \(exception.reason ?? "")\n", stderr)
        for sym in exception.callStackSymbols {
            fputs("  \(sym)\n", stderr)
        }
        _exit(1)
    }

    @MainActor
    func test_contentView_mountsAndRendersInWindowWithoutAbort() throws {
        if let orig = class_getClassMethod(NSApplication.self, Selector(("_crashOnException:"))),
           let hook = class_getClassMethod(Self.self, #selector(Self.hook_crashOnException(_:))) {
            method_exchangeImplementations(orig, hook)
        }

        let hostingController = NSHostingController(rootView: ContentView())
        let window = NSWindow(contentViewController: hostingController)
        window.toolbar = NSToolbar(identifier: "TestToolbar")
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // Resize window across small/large sizes while split & info panel are active
        NotificationCenter.default.post(name: .addTabShortcut, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        NotificationCenter.default.post(name: .toggleSplitShortcut, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        NotificationCenter.default.post(name: .toggleInfoPanelShortcut, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        for size in [NSSize(width: 840, height: 540), NSSize(width: 1200, height: 760), NSSize(width: 860, height: 560)] {
            window.setFrame(NSRect(origin: .zero, size: size), display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }

        NotificationCenter.default.post(name: .toggleTabOverview, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        NotificationCenter.default.post(name: .toggleTabOverview, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        NotificationCenter.default.post(name: .closeTabShortcut, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        NotificationCenter.default.post(name: .reopenClosedTabShortcut, object: nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let vm = BrowserViewModel(startingAt: tempDir)
        try Data("hello".utf8).write(to: tempDir.appendingPathComponent("sample.txt"))
        vm.refresh()
        for mode in ViewMode.allCases {
            vm.setViewMode(mode)
            vm.toggleShowInGroups()
            vm.isSelectionModeActive = true
            let browserHost = NSHostingView(rootView: BrowserView(viewModel: vm))
            browserHost.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            window.contentView = browserHost
            browserHost.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            vm.toggleShowInGroups()
            browserHost.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if mode == .details {
                var props = vm.viewProperties
                props.visibleDetailsColumns = [.type, .size, .modificationDate, .permissions, .tags]
                vm.applyViewProperties(props, scope: .currentFolder, useAsDefault: false)
                browserHost.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.06))
                props.visibleDetailsColumns = [.size]
                vm.applyViewProperties(props, scope: .currentFolder, useAsDefault: false)
                browserHost.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            }
        }

        let vpHost = NSHostingView(
            rootView: ViewPropertiesDialogSheetView(
                folderURL: tempDir,
                draft: vm.viewProperties,
                globalShowsHiddenFiles: false
            ) { _, _, _ in }
        )
        vpHost.frame = NSRect(x: 0, y: 0, width: 520, height: 560)
        window.contentView = vpHost
        vpHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))

        let duHost = NSHostingView(
            rootView: DiskUsageAnalyzerSheetView(directoryURL: tempDir)
        )
        duHost.frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        window.contentView = duHost
        duHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let settingsHost = NSHostingView(rootView: SettingsView())
        settingsHost.frame = NSRect(x: 0, y: 0, width: 540, height: 420)
        window.contentView = settingsHost
        settingsHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))

        window.close()
    }

    func testTerminalVerticalCursorMovementAndResizeBounds() {
        // Simulate fastfetch drawing 2 lines of ASCII art, moving up 1 line (ESC[1A),
        // moving right to col 12 (ESC[12G), and printing system info alongside the logo
        let stream = "LOGO_Row1\r\nLOGO_Row2\u{001B}[1A\u{001B}[12GHost: Mac\r\n\u{001B}[12GOS: macOS"
        let rendered = EmbeddedTerminalSession.stripANSISequences(from: stream)
        XCTAssertEqual(rendered, "LOGO_Row1  Host: Mac\nLOGO_Row2  OS: macOS")

        XCTAssertLessThan(EmbeddedTerminalPanelView.minHeight, EmbeddedTerminalPanelView.defaultHeight)
        XCTAssertLessThan(EmbeddedTerminalPanelView.defaultHeight, EmbeddedTerminalPanelView.expandedHeight)
        XCTAssertLessThanOrEqual(EmbeddedTerminalPanelView.expandedHeight, EmbeddedTerminalPanelView.maxHeight)
    }

    func testThreeFingerSwipeRecognizerStrictDirectionAndFourFingerExclusion() {
        var recognizer = ThreeFingerSwipeRecognizer()

        func makeThreeTouches(yOffset: CGFloat, xOffset: CGFloat = 0) -> [TrackpadTouchSample] {
            [
                TrackpadTouchSample(id: 1, position: CGPoint(x: 0.35 + xOffset, y: 0.40 + yOffset)),
                TrackpadTouchSample(id: 2, position: CGPoint(x: 0.50 + xOffset, y: 0.42 + yOffset)),
                TrackpadTouchSample(id: 3, position: CGPoint(x: 0.65 + xOffset, y: 0.40 + yOffset))
            ]
        }

        // 1. 3-finger swipe DOWN when overview is closed -> must NOT trigger, even with upward rebound
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.0), timestamp: 1.00, isOverviewVisible: false)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.02), timestamp: 1.02, isOverviewVisible: false)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.06), timestamp: 1.04, isOverviewVisible: false)
        let downResult = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.14), timestamp: 1.07, isOverviewVisible: false)
        XCTAssertNil(downResult)
        // Rebound upward in the same stroke must still be ignored
        let reboundResult = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.12), timestamp: 1.10, isOverviewVisible: false)
        XCTAssertNil(reboundResult)
        _ = recognizer.processFrame(touches: [], timestamp: 1.12, isOverviewVisible: false)

        // 2. 4-finger gesture (3 fingers touch first at t=2.00, 4th finger lands at t=2.02, moves up, then 1 finger lifts leaving 3) -> must NOT trigger
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.0), timestamp: 2.00, isOverviewVisible: false)
        var fourTouches = makeThreeTouches(yOffset: 0.03)
        fourTouches.append(TrackpadTouchSample(id: 4, position: CGPoint(x: 0.78, y: 0.38)))
        _ = recognizer.processFrame(touches: fourTouches, timestamp: 2.02, isOverviewVisible: false)
        let trailingThreeAfterFour = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.16), timestamp: 2.08, isOverviewVisible: false)
        XCTAssertNil(trailingThreeAfterFour)
        _ = recognizer.processFrame(touches: [], timestamp: 2.10, isOverviewVisible: false)

        // 3. Clean 3-finger swipe UP after cooldown -> triggers .showOverview
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.0), timestamp: 3.00, isOverviewVisible: false)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.03), timestamp: 3.02, isOverviewVisible: false)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.07), timestamp: 3.04, isOverviewVisible: false)
        let upResult = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.12), timestamp: 3.07, isOverviewVisible: false)
        XCTAssertEqual(upResult, .showOverview)
        _ = recognizer.processFrame(touches: [], timestamp: 3.10, isOverviewVisible: true)

        // 4. Clean 3-finger swipe DOWN while overview is open -> triggers .hideOverview
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: 0.0), timestamp: 4.00, isOverviewVisible: true)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.03), timestamp: 4.02, isOverviewVisible: true)
        _ = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.06), timestamp: 4.04, isOverviewVisible: true)
        let closeResult = recognizer.processFrame(touches: makeThreeTouches(yOffset: -0.11), timestamp: 4.07, isOverviewVisible: true)
        XCTAssertEqual(closeResult, .hideOverview)
    }

    // MARK: - 9. File & Directory Comparison (`compare_files`)

    func test_fileComparisonService_comparesFilesAndDirectories() throws {
        let leftFile = tempDir.appendingPathComponent("left.txt")
        let rightIdentical = tempDir.appendingPathComponent("right_same.txt")
        let rightModified = tempDir.appendingPathComponent("right_mod.txt")
        try Data("alpha\nbeta\ngamma\n".utf8).write(to: leftFile)
        try Data("alpha\nbeta\ngamma\n".utf8).write(to: rightIdentical)
        try Data("alpha\nbeta_mod\ngamma\ndelta\n".utf8).write(to: rightModified)

        let sameResult = FileComparisonService.compare(left: leftFile, right: rightIdentical)
        XCTAssertTrue(sameResult.areIdentical)
        XCTAssertEqual(sameResult.addedLineCount, 0)
        XCTAssertEqual(sameResult.removedLineCount, 0)

        let diffResult = FileComparisonService.compare(left: leftFile, right: rightModified)
        XCTAssertFalse(diffResult.areIdentical)
        XCTAssertTrue(diffResult.isTextComparison)
        XCTAssertEqual(diffResult.removedLineCount, 1)
        XCTAssertEqual(diffResult.addedLineCount, 2)

        let dirA = tempDir.appendingPathComponent("DirA", isDirectory: true)
        let dirB = tempDir.appendingPathComponent("DirB", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try Data("same".utf8).write(to: dirA.appendingPathComponent("common.txt"))
        try Data("same".utf8).write(to: dirB.appendingPathComponent("common.txt"))
        try Data("onlyA".utf8).write(to: dirA.appendingPathComponent("a_only.txt"))
        try Data("onlyB".utf8).write(to: dirB.appendingPathComponent("b_only.txt"))
        try Data("v1".utf8).write(to: dirA.appendingPathComponent("changed.txt"))
        try Data("v2_longer".utf8).write(to: dirB.appendingPathComponent("changed.txt"))

        let dirResult = FileComparisonService.compare(left: dirA, right: dirB)
        XCTAssertTrue(dirResult.isDirectoryComparison)
        XCTAssertFalse(dirResult.areIdentical)
        let byPath = Dictionary(uniqueKeysWithValues: dirResult.directoryEntries.map { ($0.name, $0.status) })
        XCTAssertEqual(byPath["common.txt"], .identical)
        XCTAssertEqual(byPath["a_only.txt"], .onlyLeft)
        XCTAssertEqual(byPath["b_only.txt"], .onlyRight)
        XCTAssertEqual(byPath["changed.txt"], .modified)
    }

    // MARK: - 10. File Checksums (`KChecksumsPlugin`)

    func test_fileChecksums_calculatesAndVerifiesSHA256SHA1AndMD5() throws {
        let file = tempDir.appendingPathComponent("checksum.txt")
        try Data("dolphin-kde-macos".utf8).write(to: file)

        let checksums = try XCTUnwrap(FilePropertiesSheetView.computeChecksums(for: file))
        XCTAssertEqual(checksums.sha256.count, 64)
        XCTAssertEqual(checksums.sha1.count, 40)
        XCTAssertEqual(checksums.md5.count, 32)
        XCTAssertEqual(checksums.matches(checksums.sha256.uppercased()), "SHA-256")
        XCTAssertEqual(checksums.matches("  \(checksums.sha1)  "), "SHA-1")
        XCTAssertEqual(checksums.matches(checksums.md5), "MD5")
        XCTAssertNil(checksums.matches("deadbeef"))
    }

    // MARK: - 11. Symbolic Links, Show Target (`show_target`) & History Stack Jump

    func test_symbolicLinkCreation_showTarget_andHistoryJump() throws {
        let subFolder = tempDir.appendingPathComponent("TargetSub", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        let targetFile = subFolder.appendingPathComponent("real.txt")
        try Data("contenido real".utf8).write(to: targetFile)

        let vm = BrowserViewModel(
            startingAt: subFolder,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        vm.setSelection([targetFile])
        vm.createSymbolicLinkToSelected()

        let linkItem = try XCTUnwrap(vm.items.first { $0.isSymbolicLink })
        XCTAssertTrue(linkItem.name.contains("enlace"))

        // Move link into tempDir and verify showSymbolicLinkTarget navigates to TargetSub and selects real.txt
        let movedLink = tempDir.appendingPathComponent(linkItem.name)
        try FileManager.default.moveItem(at: linkItem.url, to: movedLink)
        vm.navigate(to: tempDir)
        let movedLinkItem = try XCTUnwrap(vm.items.first { $0.isSymbolicLink })
        vm.showSymbolicLinkTarget(movedLinkItem)
        XCTAssertEqual(vm.currentURL.standardizedFileURL, subFolder.standardizedFileURL)
        XCTAssertEqual(vm.selectedItem?.name, "real.txt")

        // Test history stack jump
        let thirdFolder = tempDir.appendingPathComponent("Third", isDirectory: true)
        try FileManager.default.createDirectory(at: thirdFolder, withIntermediateDirectories: true)
        vm.navigate(to: thirdFolder)
        XCTAssertGreaterThanOrEqual(vm.backStack.count, 2)
        vm.jumpBack(toStackIndex: 0)
        XCTAssertEqual(vm.currentURL.standardizedFileURL, subFolder.standardizedFileURL)
        XCTAssertGreaterThanOrEqual(vm.forwardStack.count, 2)
        vm.jumpForward(toStackIndex: 0)
        XCTAssertEqual(vm.currentURL.standardizedFileURL, thirdFolder.standardizedFileURL)
    }

    // MARK: - 12. Advanced Tab & Split View Operations

    func test_tabsViewModel_duplicateCloseOtherSplitToTabsAndSwapPanes() throws {
        let dirA = tempDir.appendingPathComponent("A", isDirectory: true)
        let dirB = tempDir.appendingPathComponent("B", isDirectory: true)
        let dirC = tempDir.appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirC, withIntermediateDirectories: true)

        let tabsVM = TabsViewModel(startingAt: dirA)
        tabsVM.openInSplitView(dirB, for: tabsVM.selectedTabID)
        XCTAssertEqual(tabsVM.selectedTab?.isSplit, true)
        XCTAssertEqual(tabsVM.selectedTab?.secondary?.currentURL.standardizedFileURL, dirB.standardizedFileURL)

        tabsVM.swapSplitPanes(for: tabsVM.selectedTabID)
        XCTAssertEqual(tabsVM.selectedTab?.primary.currentURL.standardizedFileURL, dirB.standardizedFileURL)
        XCTAssertEqual(tabsVM.selectedTab?.secondary?.currentURL.standardizedFileURL, dirA.standardizedFileURL)

        tabsVM.moveSplitViewToTabs(for: tabsVM.selectedTabID)
        XCTAssertEqual(tabsVM.tabs.count, 2)
        XCTAssertEqual(tabsVM.tabs[0].isSplit, false)
        XCTAssertEqual(tabsVM.tabs[1].primary.currentURL.standardizedFileURL, dirA.standardizedFileURL)

        tabsVM.duplicateTab(tabsVM.tabs[0].id)
        XCTAssertEqual(tabsVM.tabs.count, 3)

        tabsVM.addTab(startingAt: dirC)
        XCTAssertEqual(tabsVM.tabs.count, 4)

        tabsVM.closeTabsToTheRight(of: tabsVM.tabs[1].id)
        XCTAssertEqual(tabsVM.tabs.count, 2)

        tabsVM.closeOtherTabs(keeping: tabsVM.tabs[0].id)
        XCTAssertEqual(tabsVM.tabs.count, 1)
    }

    // MARK: - 13. SortingChoice & Breadcrumb Subdirectory Listing

    func test_sortingChoice_andBreadcrumbSubdirectories() throws {
        let items = [
            FileItem(url: tempDir.appendingPathComponent("file10.txt"), name: "file10.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("file2.txt"), name: "file2.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: nil),
            FileItem(url: tempDir.appendingPathComponent("File1.txt"), name: "File1.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: nil),
        ]
        let naturalSorted = items.sorted(by: .name, ascending: true, sortingChoice: .natural)
        XCTAssertEqual(naturalSorted.map(\.name), ["File1.txt", "file2.txt", "file10.txt"])

        let caseSensitiveSorted = items.sorted(by: .name, ascending: true, sortingChoice: .caseSensitive)
        XCTAssertEqual(caseSensitiveSorted.map(\.name), ["File1.txt", "file10.txt", "file2.txt"])

        let sub1 = tempDir.appendingPathComponent("Zeta", isDirectory: true)
        let sub2 = tempDir.appendingPathComponent("Alfa", isDirectory: true)
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        let subs = LocationParser.subdirectories(of: tempDir)
        XCTAssertTrue(subs.map(\.lastPathComponent).contains("Alfa"))
        XCTAssertTrue(subs.map(\.lastPathComponent).contains("Zeta"))
    }

    // MARK: - 14. Saved Searches, Color Tag Search Facet & Open Containing Folder

    func test_savedSearchesAndColorTagFacetSearch_andOpenContainingFolder() throws {
        let sub = tempDir.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let taggedFile = sub.appendingPathComponent("tagged_doc.swift")
        let plainFile = sub.appendingPathComponent("plain.txt")
        try Data("let x = 42".utf8).write(to: taggedFile)
        try Data("hola".utf8).write(to: plainFile)
        try FolderIconAndTagService().setColorTag(.red, for: taggedFile)

        let searchService = SearchService()
        // Facet-only search with empty query (matching `isSearchConfigured` in `src/search/bar.cpp`)
        let redMatches = searchService.search(for: "", in: tempDir, colorTagFilter: .red)
        XCTAssertEqual(redMatches.map(\.name), ["tagged_doc.swift"])

        let provider = PlacesProvider(defaults: defaults)
        let vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        vm.searchQuery = "tagged"
        vm.searchTypeFilter = .code
        vm.searchColorTagFilter = .red
        vm.performSearch()
        XCTAssertEqual(vm.searchResults.map(\.name), ["tagged_doc.swift"])

        let saved = try XCTUnwrap(vm.saveCurrentSearch(named: "Código Rojo", using: provider))
        XCTAssertEqual(provider.savedSearches().map(\.name), ["Código Rojo"])

        vm.resetSearchAndFilters()
        XCTAssertTrue(vm.searchQuery.isEmpty)
        XCTAssertEqual(vm.searchColorTagFilter, .none)

        vm.applySavedSearch(saved)
        XCTAssertEqual(vm.searchQuery, "tagged")
        XCTAssertEqual(vm.searchTypeFilter, .code)
        XCTAssertEqual(vm.searchColorTagFilter, .red)

        let resultItem = try XCTUnwrap(vm.searchResults.first)
        vm.openContainingFolder(of: resultItem)
        XCTAssertEqual(vm.currentURL.standardizedFileURL, sub.standardizedFileURL)
        XCTAssertEqual(vm.selectedItem?.name, "tagged_doc.swift")

        provider.removeSavedSearch(id: saved.id)
        XCTAssertTrue(provider.savedSearches().isEmpty)
    }

    // MARK: - 15. Git Version Control Plugin Actions (`KVersionControlPlugin`)

    func test_gitVersionControlPluginActions_stageUnstageCommitDiffAndLog() throws {
        let gitDir = tempDir.appendingPathComponent("Repo", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        func runGit(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git", "-C", gitDir.path] + args
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
        }

        try runGit(["init", "-q"])
        try runGit(["config", "user.email", "dolphin@kde.org"])
        try runGit(["config", "user.name", "Dolphin KDE"])

        let fileA = gitDir.appendingPathComponent("feature.swift")
        try Data("print(1)\n".utf8).write(to: fileA)

        let git = GitStatusProvider()
        XCTAssertTrue(git.isGitRepository(in: gitDir))
        XCTAssertTrue(git.stage(urls: [fileA], in: gitDir))
        XCTAssertTrue(git.commit(message: "Initial commit", in: gitDir))

        let commits = git.recentCommits(in: gitDir)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.subject, "Initial commit")
        XCTAssertNotNil(git.currentBranch(in: gitDir))

        try Data("print(2)\n".utf8).write(to: fileA)
        let diffText = git.diff(for: [fileA], in: gitDir)
        XCTAssertTrue(diffText.contains("+print(2)"))

        XCTAssertTrue(git.discardChanges(urls: [fileA], in: gitDir))
        let restored = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(restored, "print(1)\n")
    }

    // MARK: - 16. InfoPanel Spotlight Comments, Text Preview & FolderTree Hidden Toggle

    func test_infoPanelMetadataHelpers_finderCommentAndTextPreviewAndFolderTreeHidden() throws {
        let codeFile = tempDir.appendingPathComponent("sample.swift")
        try Data("struct Dolphin {}\nlet version = 27\n".utf8).write(to: codeFile)

        let tagService = FolderIconAndTagService()
        XCTAssertEqual(tagService.getFinderComment(for: codeFile), "")
        XCTAssertTrue(tagService.setFinderComment("Porteado desde KDE Dolphin", for: codeFile))
        XCTAssertEqual(tagService.getFinderComment(for: codeFile), "Porteado desde KDE Dolphin")
        XCTAssertTrue(tagService.setFinderComment("", for: codeFile))
        XCTAssertEqual(tagService.getFinderComment(for: codeFile), "")

        let item = FileItem(
            url: codeFile,
            name: "sample.swift",
            isDirectory: false,
            isSymbolicLink: false,
            size: 36,
            modificationDate: Date()
        )
        let preview = InfoPanelView.readTextPreviewSnippet(for: item)
        XCTAssertEqual(preview, "struct Dolphin {}\nlet version = 27")
        XCTAssertEqual(InfoPanelView.formatDuration(125), "2:05")

        let hiddenFolder = tempDir.appendingPathComponent(".hiddenSubDir", isDirectory: true)
        let visibleFolder = tempDir.appendingPathComponent("visibleSubDir", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: visibleFolder, withIntermediateDirectories: true)

        let defaultTree = FolderTreeProvider(showsHiddenFiles: false).subdirectories(of: tempDir)
        XCTAssertFalse(defaultTree.map(\.lastPathComponent).contains(".hiddenSubDir"))

        let hiddenTree = FolderTreeProvider(showsHiddenFiles: true).subdirectories(of: tempDir)
        XCTAssertTrue(hiddenTree.map(\.lastPathComponent).contains(".hiddenSubDir"))
        XCTAssertTrue(hiddenTree.map(\.lastPathComponent).contains("visibleSubDir"))
    }

    // MARK: - 17. ContentDisplay & DetailsMode Formatting, TooltipManager, Templates & Permanent Delete

    func test_contentDisplayAndDetailsFormatting_tooltips_templates_andPermanentDelete() throws {
        let folder = tempDir.appendingPathComponent("DisplayFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let childA = folder.appendingPathComponent("a.txt")
        let childB = folder.appendingPathComponent("b.txt")
        try Data("12345".utf8).write(to: childA)
        try Data("67890".utf8).write(to: childB)

        let folderItem = FileItem(
            url: folder,
            name: "DisplayFolder",
            isDirectory: true,
            isSymbolicLink: false,
            size: nil,
            modificationDate: Date()
        )
        let formatter = FileMetadataFormatter()
        XCTAssertEqual(formatter.sizeDisplayText(for: folderItem, directorySizeMode: .none), "—")
        XCTAssertEqual(formatter.sizeDisplayText(for: folderItem, directorySizeMode: .contentCount), "2 ítems")
        XCTAssertFalse(formatter.sizeDisplayText(for: folderItem, directorySizeMode: .contentSize).isEmpty)
        XCTAssertNotEqual(formatter.sizeDisplayText(for: folderItem, directorySizeMode: .contentSize), "—")

        XCTAssertEqual(FileMetadataFormatter.formatPermissions(0o754, format: .symbolic), "rwxr-xr--")
        XCTAssertEqual(FileMetadataFormatter.formatPermissions(0o754, format: .numeric), "754")
        XCTAssertEqual(FileMetadataFormatter.formatPermissions(0o754, format: .combined), "rwxr-xr-- (754)")

        let tooltip = formatter.hoverTooltip(for: folderItem)
        XCTAssertTrue(tooltip.contains("DisplayFolder"))
        XCTAssertTrue(tooltip.contains("2 ítems"))

        let vm = BrowserViewModel(
            startingAt: folder,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        vm.createFile(named: "script.sh")
        let shURL = folder.appendingPathComponent("script.sh")
        let shContent = try String(contentsOf: shURL, encoding: .utf8)
        XCTAssertTrue(shContent.hasPrefix("#!/usr/bin/env zsh"))
        let attrs = try FileManager.default.attributesOfItem(atPath: shURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o111, 0o111)

        vm.createSymbolicLink(named: "custom_link", pointingTo: childA.path)
        let customLinkItem = try XCTUnwrap(vm.items.first { $0.name == "custom_link" })
        XCTAssertTrue(customLinkItem.isSymbolicLink)

        // Permanent delete (`Shift+Delete` / `⇧⌘⌫`)
        vm.deletePermanently([customLinkItem])
        XCTAssertFalse(FileManager.default.fileExists(atPath: customLinkItem.url.path))
    }

    // MARK: - 18. FilterBar (PlainText/Glob/Regex, CaseSensitive, Lock) & DolphinBookmarkHandler & StatusBar

    @MainActor
    func test_filterBarModesLockAndCaseSensitivity_bookmarkManager_andStatusBarSummary() throws {
        let dir1 = tempDir.appendingPathComponent("FilterDir1", isDirectory: true)
        let dir2 = tempDir.appendingPathComponent("FilterDir2", isDirectory: true)
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        try Data("a".utf8).write(to: dir1.appendingPathComponent("Readme.MD"))
        try Data("b".utf8).write(to: dir1.appendingPathComponent("readme.txt"))
        try Data("c".utf8).write(to: dir1.appendingPathComponent("report_2026.pdf"))
        try Data("d".utf8).write(to: dir2.appendingPathComponent("Readme_dir2.md"))
        try Data("e".utf8).write(to: dir2.appendingPathComponent("notes.txt"))

        let vm = BrowserViewModel(
            startingAt: dir1,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )

        // PlainText + case-sensitive
        vm.filterMode = .plainText
        vm.isFilterCaseSensitive = true
        vm.filterText = "Readme"
        XCTAssertEqual(vm.filteredItems.map(\.name), ["Readme.MD"])

        vm.isFilterCaseSensitive = false
        XCTAssertEqual(Set(vm.filteredItems.map(\.name)), Set(["Readme.MD", "readme.txt"]))

        // Glob pattern
        vm.filterMode = .glob
        vm.filterText = "*.pdf"
        XCTAssertEqual(vm.filteredItems.map(\.name), ["report_2026.pdf"])

        // Regex pattern + validation
        vm.filterMode = .regex
        vm.filterText = "^report_[0-9]{4}\\.pdf$"
        XCTAssertTrue(vm.isFilterPatternValid)
        XCTAssertEqual(vm.filteredItems.map(\.name), ["report_2026.pdf"])

        vm.filterText = "[invalid("
        XCTAssertFalse(vm.isFilterPatternValid)

        // Lock filter across folder changes (`FilterBar::m_lockButton`)
        vm.filterMode = .plainText
        vm.filterText = "Readme"
        vm.isFilterLocked = true
        vm.navigate(to: dir2)
        XCTAssertEqual(vm.filterText, "Readme")
        XCTAssertEqual(vm.filteredItems.map(\.name), ["Readme_dir2.md"])

        vm.isFilterLocked = false
        vm.navigate(to: dir1)
        XCTAssertEqual(vm.filterText, "")
        XCTAssertEqual(vm.filteredItems.count, 3)

        // DolphinBookmarkHandler: batch bookmark tabs, rename, reorder
        let provider = PlacesProvider(defaults: defaults)
        provider.addBookmarks(for: [dir1, dir2])
        XCTAssertEqual(provider.customBookmarks().map(\.name), ["FilterDir1", "FilterDir2"])

        provider.renameBookmark(for: dir1, to: "Proyecto Principal")
        XCTAssertEqual(provider.customBookmarks().first?.name, "Proyecto Principal")

        provider.moveBookmark(from: 0, to: 1)
        XCTAssertEqual(provider.customBookmarks().map(\.name), ["FilterDir2", "Proyecto Principal"])

        // StatusBarView single-item details summary
        let singleItem = try XCTUnwrap(vm.items.first { $0.name == "report_2026.pdf" })
        let bar = StatusBarView(
            itemCount: 3,
            totalCount: 3,
            selectedCount: 1,
            selectedTotalBytes: singleItem.size,
            singleSelectedItem: singleItem,
            availableCapacity: 1024 * 1024,
            displayMode: .small
        )
        XCTAssertTrue(bar.statusSummaryText.contains("«report_2026.pdf»"))
        XCTAssertTrue(bar.statusSummaryText.contains("PDF"))
    }

    // MARK: - 19. Native macOS Spacebar Quick Look (`QuickLookPreviewController`) & Keyboard Navigation

    @MainActor
    func test_quickLookPreviewController_spacebarToggleAndLiveSelectionNavigation() throws {
        let f1 = tempDir.appendingPathComponent("alpha.txt")
        let f2 = tempDir.appendingPathComponent("beta.md")
        let f3 = tempDir.appendingPathComponent("gamma.swift")
        try Data("alpha".utf8).write(to: f1)
        try Data("# Beta".utf8).write(to: f2)
        try Data("print(3)".utf8).write(to: f3)

        let vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        let ql = QuickLookPreviewController.shared
        ql.close()
        XCTAssertFalse(ql.isVisible)

        // Select first item and toggle Quick Look open (Spacebar)
        vm.selectAdjacentItem(by: 1)
        XCTAssertEqual(vm.selectedItem?.name, "alpha.txt")

        ql.toggle(for: vm)
        XCTAssertTrue(ql.isVisible)
        XCTAssertEqual(ql.currentItem?.name, "alpha.txt")
        XCTAssertEqual(ql.previewItems.count, 3)

        // Step next via Quick Look controller -> syncs browser selection to beta.md
        ql.showNext()
        XCTAssertEqual(ql.currentItem?.name, "beta.md")
        XCTAssertEqual(vm.selectedItem?.name, "beta.md")

        // Navigate in BrowserViewModel with arrow keys -> updates Quick Look to gamma.swift
        vm.selectAdjacentItem(by: 1)
        ql.updateIfVisible(for: vm)
        XCTAssertEqual(ql.currentItem?.name, "gamma.swift")

        // Toggle Spacebar again -> closes Quick Look
        ql.toggle(for: vm)
        XCTAssertFalse(ql.isVisible)

        // Multi-selection Quick Look preserves selection in BrowserViewModel when stepping
        vm.setSelection([f1, f3])
        ql.toggle(for: vm)
        XCTAssertTrue(ql.isVisible)
        XCTAssertTrue(ql.isMultiSelectionPreview)
        XCTAssertEqual(ql.previewItems.count, 2)
        ql.showNext()
        XCTAssertEqual(ql.currentItem?.name, "gamma.swift")
        XCTAssertEqual(vm.selectedIDs.count, 2, "multi-selection must remain intact when cycling Quick Look")

        // Verify native QLPreviewPanelDataSource contract & QuickLookPreviewKind classification
        XCTAssertEqual(ql.numberOfPreviewItems(in: nil), 2)
        let firstQLItem = ql.previewPanel(nil, previewItemAt: 0)
        XCTAssertEqual(firstQLItem?.previewItemURL?.standardizedFileURL, f1.standardizedFileURL)
        let secondQLItem = ql.previewPanel(nil, previewItemAt: 1)
        XCTAssertEqual(secondQLItem?.previewItemURL?.standardizedFileURL, f3.standardizedFileURL)

        let pngItem = FileItem(url: tempDir.appendingPathComponent("sample_image.png"), name: "sample_image.png", isDirectory: false, isSymbolicLink: false, size: 120, modificationDate: nil)
        let gifItem = FileItem(url: tempDir.appendingPathComponent("anim.gif"), name: "anim.gif", isDirectory: false, isSymbolicLink: false, size: 120, modificationDate: nil)
        let pdfItem = FileItem(url: tempDir.appendingPathComponent("doc.pdf"), name: "doc.pdf", isDirectory: false, isSymbolicLink: false, size: 120, modificationDate: nil)
        let mp4Item = FileItem(url: tempDir.appendingPathComponent("clip.mp4"), name: "clip.mp4", isDirectory: false, isSymbolicLink: false, size: 120, modificationDate: nil)
        XCTAssertEqual(QuickLookPreviewKind.classify(item: pngItem), .image)
        XCTAssertEqual(QuickLookPreviewKind.classify(item: gifItem), .animatedGIF)
        XCTAssertEqual(QuickLookPreviewKind.classify(item: pdfItem), .pdf)
        XCTAssertEqual(QuickLookPreviewKind.classify(item: mp4Item), .video)
        ql.close()

        // Verify 4-directional arrow navigation (↑, ↓, ←, →) in 2D grid mode (`gridColumnsCount == 2`)
        let f4 = tempDir.appendingPathComponent("delta.txt")
        try Data("delta".utf8).write(to: f4)
        vm.refresh()
        vm.setViewMode(.icons)
        vm.gridColumnsCount = 2
        // Grid layout (2 columns):
        // Row 0: [alpha.txt (0), beta.md (1)]
        // Row 1: [delta.txt (2), gamma.swift (3)]
        vm.deselectAll()
        vm.navigateSelection(direction: .right)
        XCTAssertEqual(vm.selectedItem?.name, "alpha.txt")

        vm.navigateSelection(direction: .right)
        XCTAssertEqual(vm.selectedItem?.name, "beta.md")

        vm.navigateSelection(direction: .down)
        XCTAssertEqual(vm.selectedItem?.name, "gamma.swift", "Down arrow must move to row below in same column")

        vm.navigateSelection(direction: .left)
        XCTAssertEqual(vm.selectedItem?.name, "delta.txt", "Left arrow must move to left column in same row")

        vm.navigateSelection(direction: .up)
        XCTAssertEqual(vm.selectedItem?.name, "alpha.txt", "Up arrow must move to row above in same column")

        // Shift + Down extends selection across row
        vm.navigateSelection(direction: .down, extendSelection: true)
        XCTAssertEqual(vm.selectedIDs.count, 3)

        // Verify localized Spanish display names for standard macOS sidebar places
        let staticPlaces = PlacesProvider().staticBookmarks()
        XCTAssertEqual(staticPlaces.map(\.localizedDisplayName), ["Inicio", "Escritorio", "Documentos", "Descargas", "Papelera"])
    }

    // MARK: - 20. Type-Ahead Selection, Zoom Shortcuts, Extended Sort Roles, Read-Only Detection & Archive Contents
    func test_typeAheadSelection_zoomShortcuts_extendedSortAndDetailsColumns_readOnly_andArchiveListing() throws {
        let dir = tempDir.appendingPathComponent("TypeAheadAndSortDir", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fAlpha = dir.appendingPathComponent("alpha.json")
        let fBeta = dir.appendingPathComponent("beta.swift")
        let fGamma = dir.appendingPathComponent("gamma.md")
        try Data("{}".utf8).write(to: fAlpha)
        try Data("let b = 2".utf8).write(to: fBeta)
        try Data("# Gamma".utf8).write(to: fGamma)

        let vm = BrowserViewModel(
            startingAt: dir,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )

        // 1. Type-ahead selection (`KItemListController::typeAheadUsed`)
        let t0 = Date()
        let matchG = vm.selectItemByTypeAhead("g", now: t0)
        XCTAssertEqual(matchG?.name, "gamma.md")
        XCTAssertEqual(vm.selectedItem?.name, "gamma.md")
        XCTAssertEqual(vm.typeAheadBuffer, "g")

        // Append within 1.0s buffer window -> "ga" still matches "gamma.md"
        let matchGa = vm.selectItemByTypeAhead("a", now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(matchGa?.name, "gamma.md")
        XCTAssertEqual(vm.typeAheadBuffer, "ga")

        // After > 1.0s buffer window -> resets buffer and jumps to "beta.swift"
        let matchB = vm.selectItemByTypeAhead("be", now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(matchB?.name, "beta.swift")
        XCTAssertEqual(vm.typeAheadBuffer, "be")
        vm.clearTypeAheadBuffer()
        XCTAssertEqual(vm.typeAheadBuffer, "")

        // 2. Zoom shortcuts (`slotIncreaseZoom`, `slotDecreaseZoom`, `resetZoomLevel`)
        XCTAssertEqual(vm.viewProperties.zoomLevel, 1.0, accuracy: 0.001)
        vm.increaseZoom()
        XCTAssertEqual(vm.viewProperties.zoomLevel, 1.1, accuracy: 0.001)
        vm.decreaseZoom()
        vm.decreaseZoom()
        XCTAssertEqual(vm.viewProperties.zoomLevel, 0.9, accuracy: 0.001)
        vm.resetZoom()
        XCTAssertEqual(vm.viewProperties.zoomLevel, 1.0, accuracy: 0.001)

        // 3. `defaultSortOrderForRole` (`defaultAscending`) & sorting by `extensionType` and `creationDate`
        XCTAssertTrue(SortField.name.defaultAscending)
        XCTAssertTrue(SortField.type.defaultAscending)
        XCTAssertTrue(SortField.extensionType.defaultAscending)
        XCTAssertFalse(SortField.modificationDate.defaultAscending)
        XCTAssertFalse(SortField.creationDate.defaultAscending)
        XCTAssertFalse(SortField.size.defaultAscending)

        vm.setSort(field: .extensionType, ascending: true)
        XCTAssertEqual(vm.filteredItems.map(\.name), ["alpha.json", "gamma.md", "beta.swift"])
        XCTAssertEqual(vm.groupedFilteredItems.map(\.title), [".json", ".md", ".swift"])

        // Toggle details columns (`slotHeaderContextMenuRequested`)
        XCTAssertFalse(vm.viewProperties.visibleDetailsColumns.contains(.extensionType))
        vm.toggleDetailsColumn(.extensionType)
        XCTAssertTrue(vm.viewProperties.visibleDetailsColumns.contains(.extensionType))
        vm.toggleDetailsColumn(.creationDate)
        XCTAssertTrue(vm.viewProperties.visibleDetailsColumns.contains(.creationDate))

        // 4. Read-only folder detection (`m_isFolderWritable`)
        XCTAssertTrue(vm.isCurrentDirectoryWritable)
        let roDir = tempDir.appendingPathComponent("ReadOnlyFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o555))], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: roDir.path)
        }
        vm.navigate(to: roDir)
        XCTAssertFalse(vm.isCurrentDirectoryWritable)

        // 5. Archive content inspection (`BrowseThroughArchives` / `ArchiveService.listEntries`)
        vm.navigate(to: dir)
        vm.setSelection([fAlpha, fBeta])
        vm.compressSelected(archiveName: "bundle.zip")
        let zipItem = try XCTUnwrap(vm.items.first { $0.name == "bundle.zip" })
        let entries = ArchiveService().listEntries(of: zipItem.url)
        let entryNames = entries.map(\.displayName)
        XCTAssertTrue(entryNames.contains("alpha.json"))
        XCTAssertTrue(entryNames.contains("beta.swift"))
    }

    // MARK: - 21. Session Persistence (`RememberOpenedTabs`), Dynamic Undo/Redo Text, Independent `Group By`, & Reset View Properties
    func test_sessionPersistence_dynamicUndoRedoTitles_independentGroupBy_andResetViewProperties() throws {
        let dirA = tempDir.appendingPathComponent("SessionA", isDirectory: true)
        let dirB = tempDir.appendingPathComponent("SessionB", isDirectory: true)
        let dirC = tempDir.appendingPathComponent("SessionC", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirC, withIntermediateDirectories: true)

        // 1. Session persistence (`RememberOpenedTabs` / `slotSaveSession`)
        let sessionVM1 = TabsViewModel(
            startingAt: dirA,
            startInSplitView: false,
            rememberOpenedTabs: true,
            defaults: defaults
        )
        sessionVM1.addTab(startingAt: dirB, splitView: true)
        sessionVM1.tabs[1].secondary?.navigate(to: dirC)
        sessionVM1.saveSessionSnapshot()

        let sessionVM2 = TabsViewModel(
            startingAt: tempDir,
            startInSplitView: false,
            rememberOpenedTabs: true,
            defaults: defaults
        )
        XCTAssertEqual(sessionVM2.tabs.count, 2)
        XCTAssertEqual(sessionVM2.tabs[0].primary.currentURL.standardizedFileURL, dirA.standardizedFileURL)
        XCTAssertEqual(sessionVM2.tabs[1].primary.currentURL.standardizedFileURL, dirB.standardizedFileURL)
        XCTAssertEqual(sessionVM2.tabs[1].secondary?.currentURL.standardizedFileURL, dirC.standardizedFileURL)
        XCTAssertEqual(sessionVM2.selectedTab?.primary.currentURL.standardizedFileURL, dirB.standardizedFileURL)

        // 2. Dynamic Undo/Redo menu titles (`slotUndoTextChanged` / `slotRedoTextChanged`)
        let vm = BrowserViewModel(
            startingAt: dirA,
            store: ViewPropertiesStore(defaults: defaults, appSettingsStore: AppSettingsStore(defaults: defaults))
        )
        XCTAssertEqual(vm.history.undoMenuTitle, "Deshacer")
        vm.createFolder(named: "CarpetaNueva")
        XCTAssertEqual(vm.history.undoMenuTitle, "Deshacer creación de «CarpetaNueva»")

        vm.createFile(named: "nota.txt")
        XCTAssertEqual(vm.history.undoMenuTitle, "Deshacer creación de archivo «nota.txt»")

        let fileItem = try XCTUnwrap(vm.items.first { $0.name == "nota.txt" })
        vm.select(fileItem)
        vm.renameSelected(to: "nota_renombrada.txt")
        XCTAssertEqual(vm.history.undoMenuTitle, "Deshacer renombrado de «nota.txt»")

        vm.undo()
        XCTAssertEqual(vm.history.redoMenuTitle, "Rehacer renombrado de «nota.txt»")

        // 3. Independent `Group By` (`groupByFieldOverride`) & `resetViewPropertiesToDefault`
        try Data("swift".utf8).write(to: dirA.appendingPathComponent("uno.swift"))
        try Data("md".utf8).write(to: dirA.appendingPathComponent("dos.md"))
        vm.refresh()

        vm.setSort(field: .name, ascending: true)
        vm.setGroupBy(showInGroups: true, groupFieldOverride: .extensionType)
        XCTAssertEqual(vm.viewProperties.effectiveGroupField, .extensionType)
        let groupTitles = vm.groupedFilteredItems.map(\.title)
        XCTAssertTrue(groupTitles.contains(".md"))
        XCTAssertTrue(groupTitles.contains(".swift"))

        vm.toggleShowPreviews()
        XCTAssertFalse(vm.viewProperties.showPreviews)

        vm.resetViewPropertiesToDefault()
        XCTAssertFalse(vm.viewProperties.showInGroups)
        XCTAssertNil(vm.viewProperties.groupByFieldOverride)
        XCTAssertTrue(vm.viewProperties.showPreviews)
    }

    // MARK: - 22. Performance Caches (IconCache, Metadata Caches, Fast Git Ancestor Check, VolumeInfo Cache)
    func test_performanceCaches_iconMetadataGitRootAndVolumeInfo() throws {
        let sub = tempDir.appendingPathComponent("PerfSub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let fileURL = sub.appendingPathComponent("fast.swift")
        try Data("let speed = 100\n".utf8).write(to: fileURL)

        // 1. Icon cache returns identical NSImage instance
        let icon1 = ThumbnailLoader.icon(forFile: fileURL.path)
        let icon2 = ThumbnailLoader.icon(forFile: fileURL.path)
        XCTAssertTrue(icon1 === icon2)

        // 2. FileMetadataFormatter caches directory size, permissions, and tooltips
        FileMetadataFormatter.clearCaches()
        let reader = DirectoryReader(showsHiddenFiles: false)
        let topItems = try reader.contents(of: tempDir)
        let subItem = try XCTUnwrap(topItems.first { $0.name == "PerfSub" })
        let formatter = FileMetadataFormatter()
        XCTAssertEqual(formatter.sizeDisplayText(for: subItem, directorySizeMode: .contentCount), "1 ítem")
        XCTAssertEqual(formatter.sizeDisplayText(for: subItem, directorySizeMode: .contentCount), "1 ítem")
        XCTAssertFalse(formatter.permissionsDisplayText(for: subItem, format: .symbolic).isEmpty)
        XCTAssertTrue(formatter.hoverTooltip(for: subItem).contains("Contenido: 1 ítem"))

        // 3. Fast Git ancestor check avoids spawning git on non-git folders
        XCTAssertFalse(GitStatusProvider.hasGitRepositoryInAncestors(of: sub))
        XCTAssertNil(GitStatusProvider.gitRepositoryRoot(for: sub))

        // 4. VolumeInfoProvider cache returns consistent capacity values
        let v1 = VolumeInfoProvider().info(for: tempDir)
        let v2 = VolumeInfoProvider().info(for: tempDir)
        XCTAssertEqual(v1.totalCapacity, v2.totalCapacity)
        XCTAssertEqual(v1.availableCapacity, v2.availableCapacity)
    }
}
