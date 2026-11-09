import Foundation

/// Mirrors KDE Dolphin's `HideFileItemAction` (`src/itemactions/hidefileitemaction.cpp`):
/// manages the `.hidden` file inside a directory to hide/unhide files or folders without renaming them.
struct DotHiddenService {
    private static let hiddenFileName = ".hidden"

    func hiddenFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.hiddenFileName, isDirectory: false)
    }

    func hiddenEntries(in directory: URL) -> Set<String> {
        let fileURL = hiddenFileURL(in: directory)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let names = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(names)
    }

    func isHidden(name: String, in directory: URL) -> Bool {
        hiddenEntries(in: directory).contains(name)
    }

    func hide(names: [String], in directory: URL) throws {
        var entries = hiddenEntries(in: directory)
        for name in names where !name.isEmpty && name != Self.hiddenFileName {
            entries.insert(name)
        }
        try writeEntries(entries, in: directory)
    }

    func unhide(names: [String], in directory: URL) throws {
        var entries = hiddenEntries(in: directory)
        for name in names {
            entries.remove(name)
        }
        try writeEntries(entries, in: directory)
    }

    private func writeEntries(_ entries: Set<String>, in directory: URL) throws {
        let fileURL = hiddenFileURL(in: directory)
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        let sorted = entries.sorted().joined(separator: "\n") + "\n"
        try sorted.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
