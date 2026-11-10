import XCTest
@testable import Dotphin

/// Copiar / mover / pegar desde `BrowserViewModel`: corren en segundo plano,
/// se pueden deshacer y preguntan ante un nombre repetido.
@MainActor
final class BackgroundTransferTests: XCTestCase {
    private var root: URL!
    private var sourceDir: URL!
    private var destDir: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = root.appendingPathComponent("origen", isDirectory: true)
        destDir = root.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "nuevo".write(to: sourceDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "B".write(to: sourceDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeViewModel(at url: URL) -> BrowserViewModel {
        BrowserViewModel(
            startingAt: url,
            store: ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        )
    }

    private func text(_ name: String, in directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    /// Espera a que la operación quede frenada en un conflicto.
    private func waitForConflict(in vm: BrowserViewModel) async throws -> FileTransferProgress {
        for _ in 0..<200 {
            if let transfer = vm.activeTransfer, transfer.pendingConflict != nil { return transfer }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw XCTSkip("la operación nunca llegó a preguntar")
    }

    func test_copyToOtherPane_refreshesThePaneShowingTheDestination_andUndoRemovesCopies() async {
        let source = makeViewModel(at: sourceDir)
        let other = makeViewModel(at: destDir)
        source.selectAll()

        source.copySelected(to: destDir)
        await source.waitForBackgroundWork()

        XCTAssertNil(source.activeTransfer)
        XCTAssertEqual(Set(other.items.map(\.name)), ["a.txt", "b.txt"], "el otro panel se refresca solo")
        XCTAssertTrue(source.canUndo)
        source.undo()
        XCTAssertNil(text("a.txt", in: destDir))
        XCTAssertEqual(text("a.txt", in: sourceDir), "nuevo")
    }

    func test_cutAndPaste_movesAndClearsClipboard() async {
        let source = makeViewModel(at: sourceDir)
        let destination = makeViewModel(at: destDir)
        source.selectAll()
        source.cutSelected()

        destination.paste()
        await destination.waitForBackgroundWork()

        XCTAssertEqual(Set(destination.items.map(\.name)), ["a.txt", "b.txt"])
        XCTAssertTrue(source.items.isEmpty, "el panel de origen también se refresca")
        XCTAssertFalse(destination.canPaste)
    }

    func test_conflict_withPrompt_waitsForAnswer_thenReplaces() async throws {
        try "viejo".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let source = makeViewModel(at: sourceDir)
        source.presentsConflictPrompts = true
        source.selectAll()

        source.copySelected(to: destDir)
        let transfer = try await waitForConflict(in: source)
        XCTAssertEqual(transfer.pendingConflict?.existing.lastPathComponent, "a.txt")
        XCTAssertEqual(text("a.txt", in: destDir), "viejo", "no toca nada hasta que respondan")

        transfer.resolve(.replace)
        await source.waitForBackgroundWork()

        XCTAssertEqual(text("a.txt", in: destDir), "nuevo")
        XCTAssertEqual(text("b.txt", in: destDir), "B")
        XCTAssertNil(source.operationError)

        source.undo()
        XCTAssertEqual(text("a.txt", in: destDir), "viejo", "deshacer restaura el reemplazado")
        XCTAssertNil(text("b.txt", in: destDir))
    }

    func test_conflict_cancelWhileAsking_stopsAndLeavesEverythingInPlace() async throws {
        try "viejo".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let source = makeViewModel(at: sourceDir)
        source.presentsConflictPrompts = true
        source.selectAll()

        source.moveSelected(to: destDir)
        let transfer = try await waitForConflict(in: source)
        transfer.cancel()
        await source.waitForBackgroundWork()

        XCTAssertNil(source.activeTransfer)
        XCTAssertEqual(text("a.txt", in: destDir), "viejo")
        XCTAssertEqual(text("a.txt", in: sourceDir), "nuevo")
        XCTAssertEqual(text("b.txt", in: sourceDir), "B", "lo que venía después tampoco se movió")
    }

    func test_conflict_withoutPrompt_copyKeepsBoth() async throws {
        try "viejo".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let source = makeViewModel(at: sourceDir)
        source.selectAll()

        source.copySelected(to: destDir)
        await source.waitForBackgroundWork()

        XCTAssertEqual(text("a.txt", in: destDir), "viejo")
        XCTAssertEqual(text("a copy.txt", in: destDir), "nuevo")
    }

    func test_twoTransfersInARow_runOneAfterTheOther() async {
        let source = makeViewModel(at: sourceDir)
        let second = root.appendingPathComponent("segundo", isDirectory: true)
        try? FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        source.selectAll()

        source.copySelected(to: destDir)
        source.copySelected(to: second)
        await source.waitForBackgroundWork()

        XCTAssertEqual(text("b.txt", in: destDir), "B")
        XCTAssertEqual(text("b.txt", in: second), "B")
    }

    // MARK: Carpeta en vivo (slice 20)

    func test_liveDirectory_picksUpFilesCreatedOutsideTheApp_andFollowsNavigation() async throws {
        let vm = makeViewModel(at: sourceDir)
        vm.watchesCurrentDirectory = true
        try await Task.sleep(for: .milliseconds(500))

        try "x".write(to: sourceDir.appendingPathComponent("externo.txt"), atomically: true, encoding: .utf8)
        try await waitUntil { vm.items.contains { $0.name == "externo.txt" } }

        // Al navegar, el observador sigue a la carpeta nueva.
        vm.navigate(to: destDir)
        try await Task.sleep(for: .milliseconds(500))
        try "y".write(to: destDir.appendingPathComponent("otro.txt"), atomically: true, encoding: .utf8)
        try await waitUntil { vm.items.contains { $0.name == "otro.txt" } }
    }

    func test_withoutLiveDirectory_nothingChangesUntilRefresh() async throws {
        let vm = makeViewModel(at: sourceDir)
        try "x".write(to: sourceDir.appendingPathComponent("externo.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(vm.items.contains { $0.name == "externo.txt" })
        vm.refresh()
        XCTAssertTrue(vm.items.contains { $0.name == "externo.txt" })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("la condición no se cumplió a tiempo")
    }
}
