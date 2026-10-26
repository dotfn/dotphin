import Foundation

enum StartupLocation: String, Codable, CaseIterable {
    case home, desktop, custom
}

struct AppSettings: Codable, Equatable {
    var defaultViewMode: ViewMode = .list
    var showsHiddenFiles: Bool = false
    var startupLocation: StartupLocation = .home
    var customStartupPath: String?
}

extension AppSettings {
    var startupURL: URL {
        switch startupLocation {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .desktop:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        case .custom:
            guard let customStartupPath, FileManager.default.fileExists(atPath: customStartupPath) else {
                return FileManager.default.homeDirectoryForCurrentUser
            }
            return URL(fileURLWithPath: customStartupPath, isDirectory: true)
        }
    }
}
