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
        guard let lastBatch = undoStack.last else { return String(localized: "Deshacer", bundle: #bundle) }
        return String(localized: "Deshacer \(Self.actionSummary(for: lastBatch))", bundle: #bundle)
    }

    /// Mirrors `DolphinMainWindow::slotRedoTextChanged` (`KIO::FileUndoManager::redoText`).
    var redoMenuTitle: String {
        guard let lastBatch = redoStack.last else { return String(localized: "Rehacer", bundle: #bundle) }
        return String(localized: "Rehacer \(Self.actionSummary(for: lastBatch))", bundle: #bundle)
    }

    static func actionSummary(for batch: [FileOperationRecord]) -> String {
        guard let first = batch.first else { return String(localized: "operación", bundle: #bundle) }
        let count = batch.count
        switch first {
        case .moved(let from, let to):
            if from.deletingLastPathComponent().standardizedFileURL == to.deletingLastPathComponent().standardizedFileURL {
                return count == 1 ? String(localized: "renombrado de «\(from.lastPathComponent)»", bundle: #bundle) : String(localized: "renombrado de \(count) ítems", bundle: #bundle)
            }
            return count == 1 ? String(localized: "mover «\(from.lastPathComponent)»", bundle: #bundle) : String(localized: "mover \(count) ítems", bundle: #bundle)
        case .copied(_, let to):
            return count == 1 ? String(localized: "copia de «\(to.lastPathComponent)»", bundle: #bundle) : String(localized: "copia de \(count) ítems", bundle: #bundle)
        case .createdFolder(let url):
            if count > 1, batch.dropFirst().contains(where: { if case .moved = $0 { return true } else { return false } }) {
                return String(localized: "mover a carpeta «\(url.lastPathComponent)»", bundle: #bundle)
            }
            return count == 1 ? String(localized: "creación de «\(url.lastPathComponent)»", bundle: #bundle) : String(localized: "creación de \(count) elementos", bundle: #bundle)
        case .createdFile(let url, _):
            return count == 1 ? String(localized: "creación de archivo «\(url.lastPathComponent)»", bundle: #bundle) : String(localized: "creación de \(count) archivos", bundle: #bundle)
        case .trashed(let original, _):
            return count == 1 ? String(localized: "mover «\(original.lastPathComponent)» a la Papelera", bundle: #bundle) : String(localized: "mover \(count) ítems a la Papelera", bundle: #bundle)
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
