import Foundation

struct AppSettings: Codable, Equatable {
    var defaultViewMode: ViewMode = .list
    var showsHiddenFiles: Bool = false
}
