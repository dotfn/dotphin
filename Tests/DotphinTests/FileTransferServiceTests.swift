import XCTest
@testable import Dotphin

final class FileTransferServiceTests: XCTestCase {
    private var root: URL!
    private var sourceDir: URL!
    private var destDir: URL!
    private let service = FileTransferService()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = root.appendingPathComponent("origen", isDirectory: true)
        destDir = root.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ text: String, _ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func text(_ name: String, in directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    private func decide(_ resolution: FileConflictResolution, applyToAll: Bool = false) -> @Sendable (FileConflict) async -> FileConflictDecision {
        { _ in FileConflictDecision(resolution: resolution, applyToAll: applyToAll) }
    }

    func test_copy_withoutConflict_copiesAndRecords() async throws {
        let a = try write("A", "a.txt", in: sourceDir)
        let result = await service.run(.copy, sources: [a], into: destDir, resolveConflict: decide(.stop))
        XCTAssertEqual(text("a.txt", in: destDir), "A")
        XCTAssertEqual(text("a.txt", in: sourceDir), "A")
        XCTAssertEqual(result.records, [.copied(source: a, to: destDir.appendingPathComponent("a.txt"))])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.wasCancelled)
    }

    func test_move_conflict_replace_trashesExistingAndIsUndoable() async throws {
        let a = try write("nuevo", "a.txt", in: sourceDir)
        try write("viejo", "a.txt", in: destDir)
        let result = await service.run(.move, sources: [a], into: destDir, resolveConflict: decide(.replace))

        XCTAssertEqual(text("a.txt", in: destDir), "nuevo")
        XCTAssertNil(text("a.txt", in: sourceDir))
        XCTAssertEqual(result.records.count, 2)

        // Deshacer devuelve el nuevo a su origen y el viejo a su lugar.
        var history = FileOperationHistory()
        history.record(result.records)
        try history.undo(using: FileOperationsService())
        XCTAssertEqual(text("a.txt", in: sourceDir), "nuevo")
        XCTAssertEqual(text("a.txt", in: destDir), "viejo")
    }

    func test_copy_conflict_keepBoth_usesFreeName() async throws {
        let a = try write("nuevo", "a.txt", in: sourceDir)
        try write("viejo", "a.txt", in: destDir)
        let result = await service.run(.copy, sources: [a], into: destDir, resolveConflict: decide(.keepBoth))
        XCTAssertEqual(text("a.txt", in: destDir), "viejo")
        XCTAssertEqual(text("a copy.txt", in: destDir), "nuevo")
        XCTAssertEqual(result.createdURLs.map(\.lastPathComponent), ["a copy.txt"])
    }

    func test_conflict_skip_leavesBothUntouched_andContinues() async throws {
        let a = try write("nuevo", "a.txt", in: sourceDir)
        let b = try write("B", "b.txt", in: sourceDir)
        try write("viejo", "a.txt", in: destDir)
        let result = await service.run(.move, sources: [a, b], into: destDir, resolveConflict: decide(.skip))
        XCTAssertEqual(text("a.txt", in: destDir), "viejo")
        XCTAssertEqual(text("a.txt", in: sourceDir), "nuevo")
        XCTAssertEqual(text("b.txt", in: destDir), "B")
        XCTAssertEqual(result.records.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func test_conflict_stop_endsOperationKeepingWhatWasDone() async throws {
        let a = try write("A", "a.txt", in: sourceDir)
        let b = try write("nuevo", "b.txt", in: sourceDir)
        let c = try write("C", "c.txt", in: sourceDir)
        try write("viejo", "b.txt", in: destDir)
        let result = await service.run(.copy, sources: [a, b, c], into: destDir, resolveConflict: decide(.stop))
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(text("a.txt", in: destDir), "A")
        XCTAssertEqual(text("b.txt", in: destDir), "viejo")
        XCTAssertNil(text("c.txt", in: destDir))
    }

    func test_applyToAll_asksOnlyOnce() async throws {
        let a = try write("1", "a.txt", in: sourceDir)
        let b = try write("2", "b.txt", in: sourceDir)
        try write("x", "a.txt", in: destDir)
        try write("y", "b.txt", in: destDir)
        let asked = Counter()
        let result = await service.run(.copy, sources: [a, b], into: destDir) { _ in
            await asked.increment()
            return FileConflictDecision(resolution: .replace, applyToAll: true)
        }
        let count = await asked.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(text("a.txt", in: destDir), "1")
        XCTAssertEqual(text("b.txt", in: destDir), "2")
        XCTAssertTrue(result.failures.isEmpty)
    }

    func test_copyInSameFolder_duplicatesWithoutAsking() async throws {
        let a = try write("A", "a.txt", in: sourceDir)
        let result = await service.run(.copy, sources: [a], into: sourceDir, resolveConflict: decide(.stop))
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(text("a copy.txt", in: sourceDir), "A")
    }

    func test_moveIntoOwnFolder_isNoOp() async throws {
        let a = try write("A", "a.txt", in: sourceDir)
        let result = await service.run(.move, sources: [a], into: sourceDir, resolveConflict: decide(.stop))
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(text("a.txt", in: sourceDir), "A")
    }

    func test_moveFolderIntoItself_reportsFailure() async throws {
        let folder = sourceDir.appendingPathComponent("carpeta", isDirectory: true)
        let inner = folder.appendingPathComponent("adentro", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let result = await service.run(.move, sources: [folder], into: inner, resolveConflict: decide(.stop))
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inner.path))
    }

    func test_cancellation_stopsBetweenItems() async throws {
        let sources = try (0..<20).map { try write("\($0)", "f\($0).txt", in: sourceDir) }
        let destDir = self.destDir!
        let task = Task {
            await FileTransferService().run(.copy, sources: sources, into: destDir, onProgress: { completed, _ in
                if completed == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }, resolveConflict: { _ in FileConflictDecision(resolution: .stop) })
        }
        let result = await task.value
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.records.count, 3)
    }

    func test_progress_reportsEachItemInOrder() async throws {
        let sources = try ["a", "b", "c"].map { try write($0, "\($0).txt", in: sourceDir) }
        let seen = NameLog()
        _ = await service.run(.copy, sources: sources, into: destDir, onProgress: { completed, current in
            await seen.append("\(completed):\(current.lastPathComponent)")
        }, resolveConflict: decide(.stop))
        let names = await seen.values
        XCTAssertEqual(names, ["0:a.txt", "1:b.txt", "2:c.txt"])
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor NameLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
