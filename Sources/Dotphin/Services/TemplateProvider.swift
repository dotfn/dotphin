import AppKit
import Foundation

/// Lists user-added custom file templates from `~/Templates`, the native-macOS analog
/// to Dolphin's "Create New" template system (`createnewmenu.cpp` scanning
/// `~/.local/share/templates`). Flat only — no per-subfolder submenus, unlike Dolphin.
struct TemplateProvider {
    static var templatesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Templates", isDirectory: true)
    }

    /// Regular, non-hidden files directly inside `directory` (default `~/Templates`),
    /// sorted by display name. Never creates the folder — an absent directory just
    /// means an empty list. `directory` is injectable for testing only.
    func customTemplates(in directory: URL = TemplateProvider.templatesDirectory) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Creates `~/Templates` if it doesn't exist yet, then reveals it in Finder —
    /// the only path by which this app ever creates that folder.
    func revealOrCreateTemplatesDirectory() {
        let dir = Self.templatesDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
