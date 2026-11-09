import AppKit
import Quartz
@preconcurrency import QuickLookUI

/// Classifies file types for Quick Look metadata and unit test verification.
enum QuickLookPreviewKind: Equatable {
    case image
    case animatedGIF
    case pdf
    case video
    case audio
    case text
    case archive
    case directory
    case other

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "avif",
        "tiff", "tif", "bmp", "icns", "ico", "svg", "dng", "cr2", "nef", "arw", "raw"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "aiff", "ogg", "caf"
    ]

    static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"
    ]

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx", "swift", "c",
        "h", "cpp", "hpp", "m", "mm", "py", "rb", "rs", "go", "java", "kt",
        "sh", "zsh", "bash", "fish", "sql", "graphql", "ini", "conf", "cfg",
        "env", "gitignore", "dockerfile", "makefile", "cmake", "csv", "tsv", "log"
    ]

    static let textFilenames: Set<String> = [
        "dockerfile", "makefile", "cmakelists.txt", "license", "readme",
        ".gitignore", ".gitattributes", ".editorconfig", ".zshrc", ".bashrc", ".hidden"
    ]

    static func classify(item: FileItem) -> QuickLookPreviewKind {
        if item.isDirectory {
            return .directory
        }
        let ext = item.url.pathExtension.lowercased()
        let lowerName = item.name.lowercased()

        if ext == "gif" {
            return .animatedGIF
        }
        if imageExtensions.contains(ext) {
            return .image
        }
        if ext == "pdf" {
            return .pdf
        }
        if videoExtensions.contains(ext) {
            return .video
        }
        if audioExtensions.contains(ext) {
            return .audio
        }
        if archiveExtensions.contains(ext) {
            return .archive
        }
        if textExtensions.contains(ext) || textFilenames.contains(lowerName) {
            return .text
        }
        return .other
    }
}

/// Bridges the responder chain of main browser windows (`NSWindow`) to macOS's native `QLPreviewPanel.shared()`.
/// In AppKit, `QLPreviewPanel` walks the responder chain calling `acceptsPreviewPanelControl(_:)` and
/// `beginPreviewPanelControl(_:)` whenever the panel opens or updates its controller.
extension NSWindow {
    open override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !(self is NSPanel)
    }

    open override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.beginControl(of: panel)
        }
    }

    open override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.endControl(of: panel)
        }
    }
}

/// Native macOS Spacebar Quick Look controller powered directly by the system `QLPreviewPanel.shared()` (`QuickLookUI`).
/// Provides 100% native Finder Quick Look (with native Markup, Rotate, Share, Open with Preview, Live Text, and Index Sheet)
/// while supporting Spacebar toggle, live selection tracking when navigating files in the browser, and multi-selection cycling.
@MainActor
@Observable
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSWindowDelegate {
    static let shared = QuickLookPreviewController()

    private(set) var isVisible: Bool = false
    private(set) var previewItems: [FileItem] = []
    private(set) var currentIndex: Int = 0
    /// True when the user opened Quick Look with 2+ items explicitly selected.
    private(set) var isMultiSelectionPreview: Bool = false

    var onNavigateSelectionInBrowser: ((FileItem) -> Void)?
    var onNavigateDirectionInBrowser: ((ArrowDirection) -> Void)?

    private var closeObserver: NSObjectProtocol?

    var currentItem: FileItem? {
        guard previewItems.indices.contains(currentIndex) else { return nil }
        return previewItems[currentIndex]
    }

    var currentPreviewKind: QuickLookPreviewKind {
        guard let currentItem else { return .other }
        return QuickLookPreviewKind.classify(item: currentItem)
    }

    /// Toggles native macOS Quick Look (`QLPreviewPanel.shared()`) for the current selection in `viewModel` (`Spacebar` or `⌘Y`).
    func toggle(for viewModel: BrowserViewModel) {
        if isVisible {
            close()
        } else {
            show(for: viewModel)
        }
    }

    /// Opens native macOS Quick Look (`QLPreviewPanel.shared()`) for the selected item(s) in `viewModel`.
    func show(for viewModel: BrowserViewModel) {
        let selected = viewModel.selectedItems
        let allItems = viewModel.searchQuery.isEmpty ? viewModel.filteredItems : viewModel.searchResults
        let itemsToPreview: [FileItem]
        let startIndex: Int

        if selected.count > 1 {
            isMultiSelectionPreview = true
            itemsToPreview = selected
            startIndex = 0
        } else if let single = selected.first {
            isMultiSelectionPreview = false
            if let idx = allItems.firstIndex(of: single) {
                itemsToPreview = allItems
                startIndex = idx
            } else {
                itemsToPreview = [single]
                startIndex = 0
            }
        } else if let first = allItems.first {
            isMultiSelectionPreview = false
            viewModel.select(first)
            itemsToPreview = allItems
            startIndex = 0
        } else {
            NSSound.beep()
            return
        }

        onNavigateSelectionInBrowser = { [weak viewModel] item in
            guard let viewModel else { return }
            if !QuickLookPreviewController.shared.isMultiSelectionPreview {
                viewModel.select(item)
            }
        }
        onNavigateDirectionInBrowser = { [weak viewModel] direction in
            guard let viewModel else { return }
            if QuickLookPreviewController.shared.isMultiSelectionPreview {
                switch direction {
                case .left, .up:
                    QuickLookPreviewController.shared.showPrevious()
                case .right, .down:
                    QuickLookPreviewController.shared.showNext()
                }
            } else {
                viewModel.navigateSelection(direction: direction, extendSelection: false)
                QuickLookPreviewController.shared.updateIfVisible(for: viewModel)
            }
        }
        present(items: itemsToPreview, startIndex: startIndex)
    }

    /// Updates the currently open native `QLPreviewPanel.shared()` when the user changes selection in the browser.
    func updateIfVisible(for viewModel: BrowserViewModel) {
        guard isVisible else { return }
        let selected = viewModel.selectedItems
        let allItems = viewModel.searchQuery.isEmpty ? viewModel.filteredItems : viewModel.searchResults

        let previousURLs = previewItems.map(\.url)
        if selected.count > 1 {
            isMultiSelectionPreview = true
            previewItems = selected
            currentIndex = 0
        } else if let single = selected.first {
            isMultiSelectionPreview = false
            if let idx = allItems.firstIndex(of: single) {
                previewItems = allItems
                currentIndex = idx
            } else {
                previewItems = [single]
                currentIndex = 0
            }
        }

        let newURLs = previewItems.map(\.url)
        syncWithSystemPreviewPanel(reloadItems: previousURLs != newURLs)
    }

    func present(items: [FileItem], startIndex: Int = 0) {
        guard !items.isEmpty else { return }
        self.previewItems = items
        self.currentIndex = max(0, min(startIndex, items.count - 1))
        self.isVisible = true

        guard let panel = QLPreviewPanel.shared() else { return }
        observePanelCloseIfNeeded(panel)
        panel.dataSource = self
        panel.delegate = self

        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
        panel.updateController()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if previewItems.indices.contains(currentIndex) {
            panel.currentPreviewItemIndex = currentIndex
        }
        panel.refreshCurrentPreviewItem()
    }

    func close() {
        isVisible = false
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            if panel.dataSource === self {
                panel.dataSource = nil
            }
            if panel.delegate === self {
                panel.delegate = nil
            }
            if panel.isVisible {
                panel.orderOut(nil)
            }
        }
        if let mainBrowserWindow = NSApp?.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) {
            mainBrowserWindow.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    func beginControl(of panel: QLPreviewPanel) {
        observePanelCloseIfNeeded(panel)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if previewItems.indices.contains(currentIndex) {
            panel.currentPreviewItemIndex = currentIndex
        }
    }

    func endControl(of panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
        isVisible = false
    }

    func showPrevious() {
        guard !previewItems.isEmpty else { return }
        currentIndex = (currentIndex - 1 + previewItems.count) % previewItems.count
        if let currentItem {
            onNavigateSelectionInBrowser?(currentItem)
        }
        syncWithSystemPreviewPanel(reloadItems: false)
    }

    func showNext() {
        guard !previewItems.isEmpty else { return }
        currentIndex = (currentIndex + 1) % previewItems.count
        if let currentItem {
            onNavigateSelectionInBrowser?(currentItem)
        }
        syncWithSystemPreviewPanel(reloadItems: false)
    }

    private func syncWithSystemPreviewPanel(reloadItems: Bool) {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        if panel.dataSource !== self {
            panel.dataSource = self
        }
        if panel.delegate !== self {
            panel.delegate = self
        }
        if reloadItems {
            panel.reloadData()
        }
        if previewItems.indices.contains(currentIndex) {
            panel.currentPreviewItemIndex = currentIndex
        }
        panel.refreshCurrentPreviewItem()
    }

    private func observePanelCloseIfNeeded(_ panel: QLPreviewPanel) {
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isVisible = false
                }
            }
        }
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            previewItems.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let itemURL: URL? = MainActor.assumeIsolated {
            guard previewItems.indices.contains(index) else { return nil }
            return previewItems[index].url.standardizedFileURL
        }
        return itemURL.map { $0 as NSURL }
    }

    // MARK: - QLPreviewPanelDelegate

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        return MainActor.assumeIsolated {
            switch keyCode {
            case 49, 53: // Spacebar or Escape
                close()
                return true
            case 123: // Left arrow (←)
                if let onNavigateDirectionInBrowser {
                    onNavigateDirectionInBrowser(.left)
                } else {
                    showPrevious()
                }
                return true
            case 124: // Right arrow (→)
                if let onNavigateDirectionInBrowser {
                    onNavigateDirectionInBrowser(.right)
                } else {
                    showNext()
                }
                return true
            case 125: // Down arrow (↓)
                if let onNavigateDirectionInBrowser {
                    onNavigateDirectionInBrowser(.down)
                } else {
                    showNext()
                }
                return true
            case 126: // Up arrow (↑)
                if let onNavigateDirectionInBrowser {
                    onNavigateDirectionInBrowser(.up)
                } else {
                    showPrevious()
                }
                return true
            default:
                return false
            }
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        MainActor.assumeIsolated {
            guard let referenceWindow = NSApplication.shared.windows.first(where: { !($0 is NSPanel) && $0.isVisible })
                ?? NSApplication.shared.mainWindow
                ?? NSApplication.shared.keyWindow else {
                return .zero
            }
            let frame = referenceWindow.frame
            return NSRect(x: frame.midX - 32, y: frame.midY - 32, width: 64, height: 64)
        }
    }
}
