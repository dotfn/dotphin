import AppKit
import Foundation

/// One reversible filesystem step. A user action (e.g. pasting 3 files) is a batch of these.
enum FileOperationRecord: Equatable, Sendable {
    case moved(from: URL, to: URL)
    case copied(source: URL, to: URL)
    case createdFolder(URL)
    case createdFile(URL, Data)
    case trashed(original: URL, trashed: URL)
}

/// Undo/redo stacks for file operations (Dolphin's "Deshacer"/"Rehacer").
struct FileOperationHistory {
    private(set) var undoStack: [[FileOperationRecord]] = []
    private(set) var redoStack: [[FileOperationRecord]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Mirrors `DolphinMainWindow::slotUndoTextChanged` (`KIO::FileUndoManager::undoText`).
    var undoMenuTitle: String {
        guard let lastBatch = undoStack.last else { return "Deshacer" }
        return "Deshacer \(Self.actionSummary(for: lastBatch))"
    }

    /// Mirrors `DolphinMainWindow::slotRedoTextChanged` (`KIO::FileUndoManager::redoText`).
    var redoMenuTitle: String {
        guard let lastBatch = redoStack.last else { return "Rehacer" }
        return "Rehacer \(Self.actionSummary(for: lastBatch))"
    }

    static func actionSummary(for batch: [FileOperationRecord]) -> String {
        guard let first = batch.first else { return "operación" }
        let count = batch.count
        switch first {
        case .moved(let from, let to):
            if from.deletingLastPathComponent().standardizedFileURL == to.deletingLastPathComponent().standardizedFileURL {
                return count == 1 ? "renombrado de «\(from.lastPathComponent)»" : "renombrado de \(count) ítems"
            }
            return count == 1 ? "mover «\(from.lastPathComponent)»" : "mover \(count) ítems"
        case .copied(_, let to):
            return count == 1 ? "copia de «\(to.lastPathComponent)»" : "copia de \(count) ítems"
        case .createdFolder(let url):
            if count > 1, batch.dropFirst().contains(where: { if case .moved = $0 { return true } else { return false } }) {
                return "mover a carpeta «\(url.lastPathComponent)»"
            }
            return count == 1 ? "creación de «\(url.lastPathComponent)»" : "creación de \(count) elementos"
        case .createdFile(let url, _):
            return count == 1 ? "creación de archivo «\(url.lastPathComponent)»" : "creación de \(count) archivos"
        case .trashed(let original, _):
            return count == 1 ? "mover «\(original.lastPathComponent)» a la Papelera" : "mover \(count) ítems a la Papelera"
        }
    }

    mutating func record(_ batch: [FileOperationRecord]) {
        guard !batch.isEmpty else { return }
        undoStack.append(batch)
        redoStack.removeAll()
    }

    /// A batch that fails midway is dropped: the filesystem is no longer in a state we can reason about.
    mutating func undo(using operations: FileOperationsService) throws {
        guard let batch = undoStack.popLast() else { return }
        for record in batch.reversed() {
            try operations.revert(record)
        }
        redoStack.append(batch)
    }

    mutating func redo(using operations: FileOperationsService) throws {
        guard let batch = redoStack.popLast() else { return }
        var updated: [FileOperationRecord] = []
        for record in batch {
            updated.append(try operations.reapply(record))
        }
        undoStack.append(updated)
    }
}

/// Copy/cut clipboard backed by the system pasteboard so it interoperates with Finder.
struct FileClipboard {
    enum Mode { case copy, cut }

    private static let cutMarker = NSPasteboard.PasteboardType("com.dotphin.cut")
    nonisolated(unsafe) private static var cachedChangeCount: Int = -1
    nonisolated(unsafe) private static var cachedPayload: (urls: [URL], mode: Mode)?

    func write(_ urls: [URL], mode: Mode) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        if mode == .cut {
            pasteboard.addTypes([Self.cutMarker], owner: nil)
            pasteboard.setString("1", forType: Self.cutMarker)
        }
        Self.cachedChangeCount = pasteboard.changeCount
        Self.cachedPayload = urls.isEmpty ? nil : (urls, mode)
    }

    func read() -> (urls: [URL], mode: Mode)? {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        if currentCount == Self.cachedChangeCount {
            return Self.cachedPayload
        }
        Self.cachedChangeCount = currentCount
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            Self.cachedPayload = nil
            return nil
        }
        let isCut = pasteboard.types?.contains(Self.cutMarker) == true
        let payload: (urls: [URL], mode: Mode) = (urls, isCut ? .cut : .copy)
        Self.cachedPayload = payload
        return payload
    }

    func clear() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        Self.cachedChangeCount = pasteboard.changeCount
        Self.cachedPayload = nil
    }
}
