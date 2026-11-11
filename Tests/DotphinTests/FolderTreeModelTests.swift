import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Árbol "Carpetas" del panel lateral: lo desplegado vive en `FolderTreeModel`.
@MainActor
final class FolderTreeModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Tres niveles de tres carpetas, más hermanas de sobra para llenar el
        // panel (el aborto necesita filas que entren y salgan de la vista).
        for a in ["a", "b", "c"] {
            for b in ["1", "2", "3"] {
                for c in ["x", "y", "z"] {
                    try FileManager.default.createDirectory(
                        at: root.appendingPathComponent("\(a)/\(a)\(b)/\(a)\(b)\(c)/fin/fin2"),
                        withIntermediateDirectories: true
                    )
                }
            }
        }
        for extra in 0..<12 {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("d\(extra)/sub/subsub"), withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".oculta"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_reveal_expandsTheRootAndTheAncestors_butNotTheFolderItself() {
        let model = FolderTreeModel()
        model.reveal(root.appendingPathComponent("b/b2/b2y"), under: root)
        XCTAssertTrue(model.isExpanded(root))
        XCTAssertTrue(model.isExpanded(root.appendingPathComponent("b")))
        XCTAssertTrue(model.isExpanded(root.appendingPathComponent("b/b2")))
        XCTAssertFalse(model.isExpanded(root.appendingPathComponent("b/b2/b2y")))
        XCTAssertEqual(model.children(of: root.appendingPathComponent("b/b2"))?.map(\.lastPathComponent), ["b2x", "b2y", "b2z"])
    }

    func test_reveal_ignoresFoldersOutsideTheRoot() {
        let model = FolderTreeModel()
        model.reveal(URL(fileURLWithPath: "/Volumes"), under: root)
        XCTAssertTrue(model.expanded.isEmpty)
    }

    func test_childrenAreReadBeforeTheFolderCountsAsExpanded() {
        let model = FolderTreeModel()
        let folder = root.appendingPathComponent("a")
        XCTAssertNil(model.children(of: folder))
        model.setExpanded(true, for: folder)
        XCTAssertEqual(model.children(of: folder)?.map(\.lastPathComponent), ["a1", "a2", "a3"])
    }

    func test_expansionSurvivesCollapsingTheParent() {
        let model = FolderTreeModel()
        model.setExpanded(true, for: root)
        model.setExpanded(true, for: root.appendingPathComponent("a"))
        model.setExpanded(false, for: root)
        model.setExpanded(true, for: root)
        XCTAssertTrue(model.isExpanded(root.appendingPathComponent("a")))
    }

    func test_hiddenFolders_followTheSetting() {
        let model = FolderTreeModel()
        model.setExpanded(true, for: root)
        XCTAssertFalse(model.children(of: root)!.map(\.lastPathComponent).contains(".oculta"))
        model.setShowsHiddenFiles(true)
        XCTAssertTrue(model.children(of: root)!.map(\.lastPathComponent).contains(".oculta"))
    }

    /// Antes cada fila guardaba lo desplegado en `@State`: plegar y desplegar
    /// rápido con el triángulo hacía abortar a SwiftUI (`ViewListTree.visitItem`).
    func test_clickingDisclosureTrianglesQuickly_doesNotCrash() throws {
        let model = FolderTreeModel()
        model.reveal(root.appendingPathComponent("a/a1/a1x"), under: root)
        let view = List {
            Section { Text("Lugar") } header: { Text("Lugares") }
            Section {
                FolderTreeRow(url: root, model: model, currentURL: root.appendingPathComponent("a/a1/a1x"), onSelect: { _ in })
            } header: { Text("Carpetas") }
        }
        .listStyle(.sidebar)
        .frame(width: 260, height: 700)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
        }
        spin(0.4)
        let outline = try XCTUnwrap(views(NSOutlineView.self, in: try XCTUnwrap(window.contentView)).first)

        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        var clicks = 0
        for _ in 0..<200 {
            let visible = outline.rows(in: outline.visibleRect)
            guard visible.length > 0 else { break }
            let row = visible.location + next(visible.length)
            guard let rowView = outline.rowView(atRow: row, makeIfNecessary: false),
                  let triangle = views(NSButton.self, in: rowView).first else { continue }
            triangle.performClick(nil)
            clicks += 1
            spin(Double(next(12)) / 100)
            if clicks % 7 == 0 {
                outline.needsLayout = true
                outline.layoutSubtreeIfNeeded()
            }
        }
        XCTAssertGreaterThan(clicks, 100)
        XCTAssertGreaterThan(outline.numberOfRows, 0)
    }
}
