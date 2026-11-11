import XCTest
@testable import Dotphin

@MainActor
final class DirectoryWatcherTests: XCTestCase {
    private var dir: URL!
    private var notifications = 0

    override func setUp() async throws {
        notifications = 0
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Arranca el observador y deja pasar los avisos de la creación de la
    /// propia carpeta de prueba, para contar solo lo que viene después.
    private func startWatching() async throws -> DirectoryWatcher {
        let watcher = DirectoryWatcher()
        watcher.watch(dir, latency: 0.05) { [weak self] in self?.notifications += 1 }
        try await Task.sleep(for: .milliseconds(500))
        notifications = 0
        return watcher
    }

    private func waitForNotification(timeout: Duration = .seconds(5)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if notifications > 0 { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func test_reportsFilesCreatedByAnyone() async throws {
        let watcher = try await startWatching()
        try "x".write(to: dir.appendingPathComponent("nuevo.txt"), atomically: true, encoding: .utf8)
        let notified = try await waitForNotification()
        XCTAssertTrue(notified)
        watcher.stop()
    }

    func test_reportsDeletionsAndRenames() async throws {
        let file = dir.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let watcher = try await startWatching()

        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("b.txt"))
        var notified = try await waitForNotification()
        XCTAssertTrue(notified, "renombrar")

        try await Task.sleep(for: .milliseconds(300))
        notifications = 0
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.txt"))
        notified = try await waitForNotification()
        XCTAssertTrue(notified, "borrar")
        watcher.stop()
    }

    func test_ignoresChangesInsideSubfolders() async throws {
        let watcher = try await startWatching()
        try "x".write(to: dir.appendingPathComponent("sub/adentro.txt"), atomically: true, encoding: .utf8)
        let notified = try await waitForNotification(timeout: .seconds(1))
        XCTAssertFalse(notified)
        watcher.stop()
    }

    func test_ignoringFilter_skipsBatchesMadeOnlyOfIgnoredNames() async throws {
        let watcher = DirectoryWatcher()
        watcher.watch(dir, latency: 0.05, ignoring: { $0.hasPrefix(".") }) { [weak self] in self?.notifications += 1 }
        try await Task.sleep(for: .milliseconds(500))
        notifications = 0

        // Escritura atómica: un temporal oculto y un renombre, como hacen muchas apps.
        try "x".write(to: dir.appendingPathComponent(".estado.json"), atomically: true, encoding: .utf8)
        var notified = try await waitForNotification(timeout: .seconds(1))
        XCTAssertFalse(notified)

        try "x".write(to: dir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        notified = try await waitForNotification()
        XCTAssertTrue(notified)
        watcher.stop()
    }

    func test_reportsSubfolderCreationButNotItsContents() async throws {
        let watcher = try await startWatching()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("nueva"), withIntermediateDirectories: false)
        let notified = try await waitForNotification()
        XCTAssertTrue(notified)
        watcher.stop()
    }

    func test_stop_endsNotifications() async throws {
        let watcher = try await startWatching()
        watcher.stop()
        XCTAssertNil(watcher.watchedURL)
        try "x".write(to: dir.appendingPathComponent("tarde.txt"), atomically: true, encoding: .utf8)
        let notified = try await waitForNotification(timeout: .seconds(1))
        XCTAssertFalse(notified)
    }
}
