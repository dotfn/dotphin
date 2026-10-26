import Foundation

extension Array where Element == FileItem {
    func sorted(by field: SortField, ascending: Bool) -> [FileItem] {
        sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            let result: Bool
            switch field {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                result = (lhs.size ?? 0) < (rhs.size ?? 0)
            case .modificationDate:
                result = (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
            }
            return ascending ? result : !result
        }
    }
}
