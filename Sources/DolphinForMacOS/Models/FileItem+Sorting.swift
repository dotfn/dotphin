import Foundation

extension Array where Element == FileItem {
    func sorted(by field: SortField, ascending: Bool) -> [FileItem] {
        sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            let (a, b) = ascending ? (lhs, rhs) : (rhs, lhs)
            switch field {
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size:
                let aSize = a.size ?? 0
                let bSize = b.size ?? 0
                if aSize != bSize { return aSize < bSize }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .modificationDate:
                let aDate = a.modificationDate ?? .distantPast
                let bDate = b.modificationDate ?? .distantPast
                if aDate != bDate { return aDate < bDate }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
