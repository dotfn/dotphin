import Foundation

enum StartupLocation: String, Codable, CaseIterable {
    case home, desktop, custom
}

struct AppSettings: Codable, Equatable {
    var defaultViewMode: ViewMode = .list
    var showsHiddenFiles: Bool = false
    var startupLocation: StartupLocation = .home
    var customStartupPath: String?

    private enum CodingKeys: String, CodingKey {
        case defaultViewMode, showsHiddenFiles, startupLocation, customStartupPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultViewMode = try container.decodeIfPresent(ViewMode.self, forKey: .defaultViewMode) ?? .list
        showsHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showsHiddenFiles) ?? false
        startupLocation = try container.decodeIfPresent(StartupLocation.self, forKey: .startupLocation) ?? .home
        customStartupPath = try container.decodeIfPresent(String.self, forKey: .customStartupPath)
    }
}

extension AppSettings {
    var startupURL: URL {
        switch startupLocation {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .desktop:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        case .custom:
            var isDirectory: ObjCBool = false
            guard let customStartupPath,
                  FileManager.default.fileExists(atPath: customStartupPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return FileManager.default.homeDirectoryForCurrentUser
            }
            return URL(fileURLWithPath: customStartupPath, isDirectory: true)
        }
    }
}
