import Foundation

struct FileItemGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [FileItem]
}

extension Array where Element == FileItem {
    func sorted(
        by field: SortField,
        ascending: Bool,
        foldersFirst: Bool = true,
        hiddenLast: Bool = false,
        sortingChoice: SortingChoice = .natural
    ) -> [FileItem] {
        sorted { lhs, rhs in
            if hiddenLast && lhs.isHiddenItem != rhs.isHiddenItem {
                return !lhs.isHiddenItem
            }
            // Un paquete se ordena con los archivos, como en Finder.
            if foldersFirst && lhs.opensAsFolder != rhs.opensAsFolder {
                return lhs.opensAsFolder
            }
            let (a, b) = ascending ? (lhs, rhs) : (rhs, lhs)
            switch field {
            case .name:
                return sortingChoice.compare(a.name, b.name) == .orderedAscending
            case .size:
                let aSize = a.size ?? 0
                let bSize = b.size ?? 0
                if aSize != bSize { return aSize < bSize }
                return sortingChoice.compare(lhs.name, rhs.name) == .orderedAscending
            case .modificationDate:
                let aDate = a.modificationDate ?? .distantPast
                let bDate = b.modificationDate ?? .distantPast
                if aDate != bDate { return aDate < bDate }
                return sortingChoice.compare(lhs.name, rhs.name) == .orderedAscending
            case .creationDate:
                let aDate = a.creationDate ?? a.modificationDate ?? .distantPast
                let bDate = b.creationDate ?? b.modificationDate ?? .distantPast
                if aDate != bDate { return aDate < bDate }
                return sortingChoice.compare(lhs.name, rhs.name) == .orderedAscending
            case .type:
                let aKind = a.kindDescription
                let bKind = b.kindDescription
                let cmp = sortingChoice.compare(aKind, bKind)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return sortingChoice.compare(lhs.name, rhs.name) == .orderedAscending
            case .extensionType:
                let aExt = a.fileExtension
                let bExt = b.fileExtension
                let cmp = sortingChoice.compare(aExt, bExt)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return sortingChoice.compare(lhs.name, rhs.name) == .orderedAscending
            }
        }
    }

    /// Groups already-sorted items into Dolphin-style sections (`KFileItemModel::groups()`).
    func grouped(
        by field: SortField,
        foldersFirst: Bool = true,
        referenceDate: Date = Date()
    ) -> [FileItemGroup] {
        guard !isEmpty else { return [] }
        var orderedTitles: [String] = []
        var buckets: [String: [FileItem]] = [:]

        for item in self {
            let groupTitle = Self.groupTitle(
                for: item,
                field: field,
                foldersFirst: foldersFirst,
                referenceDate: referenceDate
            )
            if buckets[groupTitle] == nil {
                orderedTitles.append(groupTitle)
                buckets[groupTitle] = []
            }
            buckets[groupTitle]?.append(item)
        }

        return orderedTitles.map { title in
            FileItemGroup(id: title, title: title, items: buckets[title] ?? [])
        }
    }

    private static func groupTitle(
        for item: FileItem,
        field: SortField,
        foldersFirst: Bool,
        referenceDate: Date
    ) -> String {
        switch field {
        case .name:
            guard let first = item.name.trimmingCharacters(in: CharacterSet(charactersIn: ".")).first else {
                return "#"
            }
            let upper = String(first).uppercased()
            if let scalar = upper.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
                return upper
            }
            return "#"

        case .size:
            if foldersFirst && item.opensAsFolder {
                return String(localized: "Carpetas", bundle: #bundle)
            }
            let bytes = item.size ?? 0
            if bytes == 0 {
                return String(localized: "Vacío (0 B)", bundle: #bundle)
            } else if bytes < 1_048_576 {
                return String(localized: "Pequeño (< 1 MB)", bundle: #bundle)
            } else if bytes < 104_857_600 {
                return String(localized: "Mediano (1 MB – 100 MB)", bundle: #bundle)
            } else if bytes < 1_073_741_824 {
                return String(localized: "Grande (100 MB – 1 GB)", bundle: #bundle)
            } else {
                return String(localized: "Enorme (> 1 GB)", bundle: #bundle)
            }

        case .modificationDate, .creationDate:
            let rawDate = (field == .creationDate) ? (item.creationDate ?? item.modificationDate) : item.modificationDate
            guard let date = rawDate else {
                return String(localized: "Fecha desconocida", bundle: #bundle)
            }
            let calendar = Calendar.current
            if calendar.isDate(date, inSameDayAs: referenceDate) {
                return String(localized: "Hoy", bundle: #bundle)
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
               calendar.isDate(date, inSameDayAs: yesterday) {
                return String(localized: "Ayer", bundle: #bundle)
            }
            if calendar.isDate(date, equalTo: referenceDate, toGranularity: .weekOfYear) {
                return String(localized: "Esta semana", bundle: #bundle)
            }
            if calendar.isDate(date, equalTo: referenceDate, toGranularity: .month) {
                return String(localized: "Este mes", bundle: #bundle)
            }
            if calendar.isDate(date, equalTo: referenceDate, toGranularity: .year) {
                return String(localized: "Este año", bundle: #bundle)
            }
            return String(localized: "Anteriores", bundle: #bundle)

        case .type:
            return item.kindDescription

        case .extensionType:
            if item.isDirectory { return String(localized: "Carpetas", bundle: #bundle) }
            let ext = item.fileExtension
            return ext.isEmpty ? String(localized: "Sin extensión", bundle: #bundle) : ".\(ext)"
        }
    }
}
