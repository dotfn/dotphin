import Observation
import Synchronization
import XCTest
@testable import Dotphin

/// Carga de carpetas fuera del hilo principal y relecturas por cambios en disco
/// (issue #2): sin reasignar lo que no cambió, sin resultados viejos, agrupadas.
@MainActor
final class DirectoryLoadingTests: XCTestCase {
    private var tempDir: URL!
    private var dirA: URL!
    private var dirB: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        dirA = tempDir.appendingPathComponent("a", isDirectory: true)
        dirB = tempDir.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try "x".write(to: dirA.appendingPathComponent("uno.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: dirB.appendingPathComponent("dos.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: dirB.appendingPathComponent("tres.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeViewModel(at url: URL, background: Bool = false) -> BrowserViewModel {
        BrowserViewModel(startingAt: url, reader: DirectoryReader(showsHiddenFiles: false), loadsInBackground: background)
    }

    private func wait(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - Releer sin cambios

    func test_reloadWithUnchangedContents_doesNotNotifyObservers() {
        let vm = makeViewModel(at: dirA)
        let changed = Mutex(false)
        withObservationTracking {
            _ = vm.items
            _ = vm.error
            _ = vm.availableCapacity
            _ = vm.isCurrentDirectoryWritable
            _ = vm.isGitRepository
            _ = vm.selectedIDs
            _ = vm.isLoadingDirectory
        } onChange: {
            changed.withLock { $0 = true }
        }
        vm.refresh()
        XCTAssertFalse(changed.withLock { $0 }, "releer una carpeta que no cambió no debe redibujar")
    }

    func test_reloadWithNewFile_updatesItems() throws {
        let vm = makeViewModel(at: dirA)
        try "x".write(to: dirA.appendingPathComponent("nuevo.txt"), atomically: true, encoding: .utf8)
        vm.refresh()
        XCTAssertEqual(vm.items.map(\.name), ["nuevo.txt", "uno.txt"])
    }

    // MARK: - Carga en segundo plano

    func test_backgroundLoad_showsLoadingThenItems() async {
        let vm = makeViewModel(at: dirB, background: true)
        XCTAssertTrue(vm.isLoadingDirectory)
        XCTAssertEqual(vm.items, [])
        await vm.waitForBackgroundWork()
        XCTAssertFalse(vm.isLoadingDirectory)
        XCTAssertEqual(vm.items.map(\.name), ["dos.txt", "tres.txt"])
    }

    func test_backgroundNavigation_discardsTheResultOfTheFolderLeftBehind() async {
        let vm = makeViewModel(at: dirA, background: true)
        vm.navigate(to: dirB)
        await vm.waitForBackgroundWork()
        XCTAssertEqual(vm.currentURL, dirB)
        XCTAssertEqual(vm.items.map(\.name), ["dos.txt", "tres.txt"])
    }

    func test_backgroundNavigation_clearsOldItemsAndSelectionRightAway() async {
        let vm = makeViewModel(at: dirA, background: true)
        await vm.waitForBackgroundWork()
        vm.select(vm.items.first)
        vm.navigate(to: dirB)
        XCTAssertEqual(vm.items, [], "no deben quedar a la vista ítems de la carpeta anterior")
        XCTAssertEqual(vm.selectedIDs, [])
        await vm.waitForBackgroundWork()
    }

    func test_navigateSelecting_selectsTheItemOnceLoaded() async {
        for background in [false, true] {
            let vm = makeViewModel(at: dirA, background: background)
            vm.navigate(to: dirB, selecting: dirB.appendingPathComponent("tres.txt"))
            await vm.waitForBackgroundWork()
            XCTAssertEqual(vm.selectedItems.map(\.name), ["tres.txt"], "segundo plano: \(background)")
        }
    }

    func test_backgroundLoad_reportsMissingFolder() async throws {
        try FileManager.default.removeItem(at: dirB)
        let vm = makeViewModel(at: dirA, background: true)
        vm.navigate(to: dirB)
        await vm.waitForBackgroundWork()
        XCTAssertEqual(vm.error, .notFound(dirB))
        XCTAssertFalse(vm.isLoadingDirectory)
    }

    func test_syncRefresh_winsOverAnOlderBackgroundLoad() async throws {
        let vm = makeViewModel(at: dirA, background: true)
        try "x".write(to: dirA.appendingPathComponent("nuevo.txt"), atomically: true, encoding: .utf8)
        vm.refresh()
        await vm.waitForBackgroundWork()
        XCTAssertEqual(vm.items.map(\.name), ["nuevo.txt", "uno.txt"])
    }

    // MARK: - Cambios en disco

    private func watchingViewModel() async throws -> BrowserViewModel {
        let vm = makeViewModel(at: dirA)
        vm.watchesCurrentDirectory = true
        // Avisos de la creación de la carpeta de prueba.
        try await wait(seconds: 0.6)
        await vm.waitForBackgroundWork()
        vm.resetLoadCountForTesting()
        return vm
    }

    func test_burstOfDiskChanges_isReadOnlyAFewTimes() async throws {
        let vm = try await watchingViewModel()
        // Como en el registro del usuario: una app escribe un archivo cada pocas decenas de ms.
        for index in 0..<8 {
            try "x".write(to: dirA.appendingPathComponent("rafaga\(index).txt"), atomically: true, encoding: .utf8)
            try await wait(seconds: 0.04)
        }
        let loaded = try await waitUntil { vm.items.count == 9 }
        XCTAssertTrue(loaded, "la relectura no trajo los archivos nuevos")
        try await wait(seconds: 0.8)
        await vm.waitForBackgroundWork()
        XCTAssertLessThanOrEqual(vm.loadCountForTesting, 3, "una ráfaga de cambios no debe releer la carpeta por cada archivo")
    }

    func test_hiddenOnlyChanges_areIgnoredWhileHiddenFilesAreNotShown() async throws {
        let vm = try await watchingViewModel()
        try "x".write(to: dirA.appendingPathComponent(".config.json"), atomically: true, encoding: .utf8)
        try await wait(seconds: 1)
        await vm.waitForBackgroundWork()
        XCTAssertEqual(vm.loadCountForTesting, 0, "un archivo oculto que no se muestra no justifica releer")

        try "x".write(to: dirA.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        let loaded = try await waitUntil { vm.items.map(\.name).contains("visible.txt") }
        XCTAssertTrue(loaded)
    }

    func test_hiddenChanges_areReadWhenHiddenFilesAreShown() async throws {
        let vm = BrowserViewModel(startingAt: dirA, reader: DirectoryReader(showsHiddenFiles: true))
        vm.watchesCurrentDirectory = true
        try await wait(seconds: 0.6)
        try "x".write(to: dirA.appendingPathComponent(".config.json"), atomically: true, encoding: .utf8)
        let loaded = try await waitUntil { vm.items.map(\.name).contains(".config.json") }
        XCTAssertTrue(loaded)
    }

    func test_turningWatchingOff_stopsReloads_andTurningItOnCatchesUp() async throws {
        let vm = try await watchingViewModel()
        vm.watchesCurrentDirectory = false
        try "x".write(to: dirA.appendingPathComponent("mientras.txt"), atomically: true, encoding: .utf8)
        try await wait(seconds: 1)
        await vm.waitForBackgroundWork()
        XCTAssertFalse(vm.items.map(\.name).contains("mientras.txt"), "una pestaña oculta no debe releer")

        vm.watchesCurrentDirectory = true
        let caughtUp = try await waitUntil { vm.items.map(\.name).contains("mientras.txt") }
        XCTAssertTrue(caughtUp, "al volver a mostrarse se pone al día")
    }
}
