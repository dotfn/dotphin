import Foundation

enum ViewMode: String, Codable {
    case icons, list, details
}

enum SortField: String, Codable {
    case name, size, modificationDate
}

struct ViewProperties: Codable, Equatable {
    var mode: ViewMode = .list
    var sortField: SortField = .name
    var ascending: Bool = true
    var zoomLevel: Double = 1.0
}
