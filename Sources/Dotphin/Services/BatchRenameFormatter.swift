import Foundation

enum BatchRenameFormatter {
    /// Expands Dolphin/KIOWidgets `#` sequences into zero-padded numbers while preserving each item's file extension.
    /// - Parameters:
    ///   - items: Items to rename, in display order.
    ///   - pattern: Pattern entered by the user (e.g. `Foto_###` or `Archivo #`). If no `#` is present, `#` is appended.
    ///   - startIndex: Starting number for the first item (default 1).
    /// - Returns: Array of `(item, newName)` pairs.
    static func plannedRenames(
        for items: [FileItem],
        pattern: String,
        startIndex: Int = 1
    ) -> [(item: FileItem, newName: String)] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !items.isEmpty else { return [] }

        let effectivePattern = trimmed.contains("#") ? trimmed : "\(trimmed)#"
        let placeholderRange = lastHashSequenceRange(in: effectivePattern)
        let padWidth = placeholderRange.map { effectivePattern.distance(from: $0.lowerBound, to: $0.upperBound) } ?? 1

        return items.enumerated().map { offset, item in
            let number = startIndex + offset
            let formattedNumber = String(format: "%0*d", padWidth, number)
            let baseNewName: String
            if let range = placeholderRange {
                baseNewName = effectivePattern.replacingCharacters(in: range, with: formattedNumber)
            } else {
                baseNewName = "\(effectivePattern)\(formattedNumber)"
            }

            let ext = (item.name as NSString).pathExtension
            let patternHasExtension = !(effectivePattern as NSString).pathExtension.isEmpty
            let finalName: String
            if !item.isDirectory && !ext.isEmpty && !patternHasExtension {
                finalName = "\(baseNewName).\(ext)"
            } else {
                finalName = baseNewName
            }
            return (item, finalName)
        }
    }

    private static func lastHashSequenceRange(in text: String) -> Range<String.Index>? {
        var end: String.Index?
        var start: String.Index?
        var idx = text.endIndex
        while idx > text.startIndex {
            idx = text.index(before: idx)
            if text[idx] == "#" {
                if end == nil {
                    end = text.index(after: idx)
                }
                start = idx
            } else if end != nil {
                break
            }
        }
        if let start, let end {
            return start..<end
        }
        return nil
    }
}
