import AppKit
import XCTest
@testable import Dotphin

@MainActor
final class FileDropTests: XCTestCase {
    private var root: URL!
    private var folder: FileItem!
    private var file: URL!
    private let everything: NSDragOperation = [.copy, .move, .generic]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = root.appendingPathComponent("carpeta", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        file = root.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let items = try DirectoryReader(showsHiddenFiles: false).contents(of: root, sortField: .name, ascending: true)
        folder = try XCTUnwrap(items.first { $0.name == "carpeta" })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Reglas de Finder

    func test_policy_sameVolume_moves_optionCopies_commandMoves() {
        let destination = folder.url
        XCTAssertEqual(FileDropPolicy.transferKind(for: [file], to: destination, sourceMask: everything), .move)
        XCTAssertEqual(FileDropPolicy.transferKind(for: [file], to: destination, sourceMask: .copy), .copy, "⌥")
        XCTAssertEqual(FileDropPolicy.transferKind(for: [file], to: destination, sourceMask: .generic), .move, "⌘")
        XCTAssertTrue(FileDropPolicy.isSameVolume(file, destination))
    }

    // MARK: Destino del drop

    func test_proposal_ontoFolder_targetsThatFolder() {
        let drops = FileDropController()
        let proposal = drops.proposal(urls: [file], sourceMask: everything, folder: folder, currentURL: root)
        XCTAssertEqual(proposal?.target, .folder(folder.url))
        XCTAssertEqual(proposal?.operation, .move)
    }

    func test_proposal_onBackground_ofSameFolder_rejectsMove_butAllowsOptionCopy() {
        let drops = FileDropController()
        XCTAssertNil(drops.proposal(urls: [file], sourceMask: everything, folder: nil, currentURL: root))

        let copy = drops.proposal(urls: [file], sourceMask: .copy, folder: nil, currentURL: root)
        XCTAssertEqual(copy?.target, .currentDirectory(root))
        XCTAssertEqual(copy?.operation, .copy, "⌥ sobre la misma carpeta duplica")
    }

    func test_proposal_folderOntoItself_fallsBackToCurrentDirectory() {
        let drops = FileDropController()
        let other = root.appendingPathComponent("otra", isDirectory: true)
        let proposal = drops.proposal(urls: [folder.url], sourceMask: everything, folder: folder, currentURL: other)
        XCTAssertEqual(proposal?.target, .currentDirectory(other))
    }

    func test_proposal_inSearchResults_backgroundHasNoDestination() {
        let drops = FileDropController()
        XCTAssertNil(drops.proposal(urls: [file], sourceMask: everything, folder: nil, currentURL: nil))
        XCTAssertNotNil(drops.proposal(urls: [file], sourceMask: everything, folder: folder, currentURL: nil))
    }

    // MARK: Carpetas con resorte

    func test_springLoading_firesAfterHoveringTheSameFolder() async throws {
        let spring = SpringLoadingTimer()
        spring.delay = .milliseconds(80)
        var opened = 0
        // Las validaciones repetidas sobre la misma carpeta no reinician el reloj.
        for _ in 0..<5 {
            spring.hover(folder.url) { opened += 1 }
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(opened, 1)
    }

    func test_springLoading_cancelsWhenLeavingTheFolder() async throws {
        let spring = SpringLoadingTimer()
        spring.delay = .milliseconds(80)
        var opened = 0
        spring.hover(folder.url) { opened += 1 }
        try await Task.sleep(for: .milliseconds(30))
        spring.hover(nil) {}
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(opened, 0)

        spring.hover(folder.url) { opened += 1 }
        spring.cancel()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(opened, 0)
    }

    // MARK: View model

    func test_copyDroppedItems_copiesInsteadOfMoving() async {
        let vm = BrowserViewModel(
            startingAt: root,
            store: ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        )
        vm.copyDroppedItems([file], into: folder.url)
        await vm.waitForBackgroundWork()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("a.txt").path))
    }
}
