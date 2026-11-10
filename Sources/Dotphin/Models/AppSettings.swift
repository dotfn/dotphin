import CoreGraphics
import Foundation

enum StartupLocation: String, Codable, CaseIterable {
    case home, desktop, custom
}

/// KDE Dolphin's `SortingChoice` (`dolphin_generalsettings.kcfg`): Natural, Case Insensitive, or Case Sensitive.
enum SortingChoice: String, Codable, CaseIterable, Identifiable {
    case natural
    case caseInsensitive
    case caseSensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return String(localized: "Natural (ej. archivo2 antes de archivo10)", bundle: #bundle)
        case .caseInsensitive: return String(localized: "Alfabético (sin distinguir mayúsculas)", bundle: #bundle)
        case .caseSensitive: return String(localized: "Alfabético (distinguiendo mayúsculas)", bundle: #bundle)
        }
    }

    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        switch self {
        case .natural:
            return lhs.localizedStandardCompare(rhs)
        case .caseInsensitive:
            return lhs.localizedCaseInsensitiveCompare(rhs)
        case .caseSensitive:
            return lhs.compare(rhs)
        }
    }
}

/// KDE Dolphin's `DirectorySizeMode` (`dolphin_contentdisplaysettings.kcfg`).
enum DirectorySizeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case contentCount
    case contentSize
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentCount: return String(localized: "Cantidad de elementos dentro de la carpeta", bundle: #bundle)
        case .contentSize: return String(localized: "Tamaño de los archivos directos", bundle: #bundle)
        case .none: return String(localized: "No mostrar tamaño (—)", bundle: #bundle)
        }
    }
}

/// KDE Dolphin's `UsePermissionsFormat` (`dolphin_contentdisplaysettings.kcfg`).
enum PermissionsDisplayFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case symbolic
    case numeric
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbolic: return String(localized: "Simbólico (rwxr-xr-x)", bundle: #bundle)
        case .numeric: return String(localized: "Numérico octal (755)", bundle: #bundle)
        case .combined: return String(localized: "Combinado (rwxr-xr-x (755))", bundle: #bundle)
        }
    }
}

/// KDE Dolphin's `ShowStatusBar` (`dolphin_generalsettings.kcfg` & `dolphinstatusbar.cpp`).
enum StatusBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullWidth
    case small
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullWidth: return String(localized: "Ancho completo (con zoom y espacio libre)", bundle: #bundle)
        case .small: return String(localized: "Compacta (solo resumen de elementos)", bundle: #bundle)
        case .disabled: return String(localized: "Oculta", bundle: #bundle)
        }
    }
}

/// Acciones de la toolbar: de acá salen el id, el título y el símbolo de cada
/// ítem de `BrowserToolbar`.
enum ToolbarActionItem: String, Codable, CaseIterable, Identifiable, Hashable {
    case back
    case forward
    case up
    case viewMode
    case sort
    case newFolder
    case rename
    case delete
    case terminal
    case split
    case newTab
    case infoPanel
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return String(localized: "Atrás", bundle: #bundle)
        case .forward: return String(localized: "Adelante", bundle: #bundle)
        case .up: return String(localized: "Subir", bundle: #bundle)
        case .viewMode: return String(localized: "Vista", bundle: #bundle)
        case .sort: return String(localized: "Ordenar", bundle: #bundle)
        case .newFolder: return String(localized: "Nueva carpeta", bundle: #bundle)
        case .rename: return String(localized: "Renombrar", bundle: #bundle)
        case .delete: return String(localized: "Eliminar", bundle: #bundle)
        case .terminal: return String(localized: "Terminal", bundle: #bundle)
        case .split: return String(localized: "Dividir", bundle: #bundle)
        case .newTab: return String(localized: "Pestaña", bundle: #bundle)
        case .infoPanel: return String(localized: "Información", bundle: #bundle)
        case .search: return String(localized: "Buscar", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .up: return "chevron.up"
        case .viewMode: return "square.grid.2x2"
        case .sort: return "arrow.up.arrow.down"
        case .newFolder: return "folder.badge.plus"
        case .rename: return "pencil"
        case .delete: return "trash"
        case .terminal: return "terminal"
        case .split: return "rectangle.split.2x1"
        case .newTab: return "plus.square.on.square"
        case .infoPanel: return "sidebar.right"
        case .search: return "magnifyingglass"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var defaultViewMode: ViewMode = .list
    var showsHiddenFiles: Bool = false
    var startupLocation: StartupLocation = .home
    var customStartupPath: String?
    var sortingChoice: SortingChoice = .natural
    var alwaysShowTabBar: Bool = false
    var rememberOpenedTabs: Bool = true
    var openNewTabAfterLastTab: Bool = true
    var startInSplitView: Bool = false
    var showFullPathInTitlebar: Bool = false
    var editableLocationByDefault: Bool = false
    var showPasteBarAfterCopying: Bool = true
    var statusBarMode: StatusBarDisplayMode = .fullWidth
    var showZoomSliderInStatusBar: Bool = true
    var confirmMoveToTrash: Bool = true
    var confirmEmptyTrash: Bool = true
    var confirmPermanentDelete: Bool = true
    var showPermanentDeleteCommand: Bool = false
    var directorySizeMode: DirectorySizeMode = .contentCount
    var permissionsFormat: PermissionsDisplayFormat = .symbolic
    var useRelativeDates: Bool = true
    var expandableFoldersInDetails: Bool = true
    var browseThroughArchives: Bool = false

    private enum CodingKeys: String, CodingKey {
        case defaultViewMode
        case showsHiddenFiles
        case startupLocation
        case customStartupPath
        case sortingChoice
        case alwaysShowTabBar
        case rememberOpenedTabs
        case openNewTabAfterLastTab
        case startInSplitView
        case showFullPathInTitlebar
        case editableLocationByDefault
        case showPasteBarAfterCopying
        case statusBarMode
        case showZoomSliderInStatusBar
        case confirmMoveToTrash
        case confirmEmptyTrash
        case confirmPermanentDelete
        case showPermanentDeleteCommand
        case directorySizeMode
        case permissionsFormat
        case useRelativeDates
        case expandableFoldersInDetails
        case browseThroughArchives
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultViewMode = try container.decodeIfPresent(ViewMode.self, forKey: .defaultViewMode) ?? .list
        showsHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showsHiddenFiles) ?? false
        startupLocation = try container.decodeIfPresent(StartupLocation.self, forKey: .startupLocation) ?? .home
        customStartupPath = try container.decodeIfPresent(String.self, forKey: .customStartupPath)
        sortingChoice = try container.decodeIfPresent(SortingChoice.self, forKey: .sortingChoice) ?? .natural
        alwaysShowTabBar = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowTabBar) ?? false
        rememberOpenedTabs = try container.decodeIfPresent(Bool.self, forKey: .rememberOpenedTabs) ?? true
        openNewTabAfterLastTab = try container.decodeIfPresent(Bool.self, forKey: .openNewTabAfterLastTab) ?? true
        startInSplitView = try container.decodeIfPresent(Bool.self, forKey: .startInSplitView) ?? false
        showFullPathInTitlebar = try container.decodeIfPresent(Bool.self, forKey: .showFullPathInTitlebar) ?? false
        editableLocationByDefault = try container.decodeIfPresent(Bool.self, forKey: .editableLocationByDefault) ?? false
        showPasteBarAfterCopying = try container.decodeIfPresent(Bool.self, forKey: .showPasteBarAfterCopying) ?? true
        statusBarMode = try container.decodeIfPresent(StatusBarDisplayMode.self, forKey: .statusBarMode) ?? .fullWidth
        showZoomSliderInStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showZoomSliderInStatusBar) ?? true
        confirmMoveToTrash = try container.decodeIfPresent(Bool.self, forKey: .confirmMoveToTrash) ?? true
        confirmEmptyTrash = try container.decodeIfPresent(Bool.self, forKey: .confirmEmptyTrash) ?? true
        confirmPermanentDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmPermanentDelete) ?? true
        showPermanentDeleteCommand = try container.decodeIfPresent(Bool.self, forKey: .showPermanentDeleteCommand) ?? false
        directorySizeMode = try container.decodeIfPresent(DirectorySizeMode.self, forKey: .directorySizeMode) ?? .contentCount
        permissionsFormat = try container.decodeIfPresent(PermissionsDisplayFormat.self, forKey: .permissionsFormat) ?? .symbolic
        useRelativeDates = try container.decodeIfPresent(Bool.self, forKey: .useRelativeDates) ?? true
        expandableFoldersInDetails = try container.decodeIfPresent(Bool.self, forKey: .expandableFoldersInDetails) ?? true
        browseThroughArchives = try container.decodeIfPresent(Bool.self, forKey: .browseThroughArchives) ?? false
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
