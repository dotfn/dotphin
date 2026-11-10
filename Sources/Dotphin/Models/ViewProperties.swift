import Foundation

enum ViewMode: String, Codable, CaseIterable {
    case icons
    case compact
    case list
    case details

    var title: String {
        switch self {
        case .icons: return String(localized: "Iconos", bundle: #bundle)
        case .compact: return String(localized: "Compacta", bundle: #bundle)
        case .list: return String(localized: "Lista", bundle: #bundle)
        case .details: return String(localized: "Detalles", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .compact: return "rectangle.grid.3x2"
        case .list: return "list.bullet"
        case .details: return "tablecells"
        }
    }
}

enum SortField: String, Codable, CaseIterable {
    case name
    case size
    case modificationDate
    case creationDate
    case type
    case extensionType

    var title: String {
        switch self {
        case .name: return String(localized: "Nombre", bundle: #bundle)
        case .size: return String(localized: "Tamaño", bundle: #bundle)
        case .modificationDate: return String(localized: "Fecha de modificación", bundle: #bundle)
        case .creationDate: return String(localized: "Fecha de creación", bundle: #bundle)
        case .type: return String(localized: "Tipo", bundle: #bundle)
        case .extensionType: return String(localized: "Extensión", bundle: #bundle)
        }
    }

    /// Mirrors `DolphinView::defaultSortOrderForRole` (`src/views/dolphinview.cpp` lines 1917-1940):
    /// modificationDate, creationDate, and size default to descending (`false`); name, type, and extension default to ascending (`true`).
    var defaultAscending: Bool {
        switch self {
        case .modificationDate, .creationDate, .size:
            return false
        case .name, .type, .extensionType:
            return true
        }
    }
}

enum DetailsColumn: String, Codable, CaseIterable, Identifiable, Hashable {
    case type
    case extensionType
    case size
    case modificationDate
    case creationDate
    case permissions
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return String(localized: "Tipo", bundle: #bundle)
        case .extensionType: return String(localized: "Extensión", bundle: #bundle)
        case .size: return String(localized: "Tamaño", bundle: #bundle)
        case .modificationDate: return String(localized: "Modificado", bundle: #bundle)
        case .creationDate: return String(localized: "Creado", bundle: #bundle)
        case .permissions: return String(localized: "Permisos", bundle: #bundle)
        case .tags: return String(localized: "Etiquetas", bundle: #bundle)
        }
    }
}

struct ViewProperties: Codable, Equatable {
    var mode: ViewMode = .list
    var sortField: SortField = .name
    var ascending: Bool = true
    var zoomLevel: Double = 1.0
    var showInGroups: Bool = false
    /// When `nil`, groups by `sortField` (`"same_as_sort"` in `DolphinViewActionHandler`); when non-nil, groups by that explicit `SortField`.
    var groupByFieldOverride: SortField? = nil
    var sortFoldersFirst: Bool = true
    var sortHiddenLast: Bool = false
    var showPreviews: Bool = true
    var showsHiddenFilesOverride: Bool? = nil
    var visibleDetailsColumns: [DetailsColumn] = [.type, .size, .modificationDate]

    var effectiveGroupField: SortField {
        groupByFieldOverride ?? sortField
    }

    init(
        mode: ViewMode = .list,
        sortField: SortField = .name,
        ascending: Bool = true,
        zoomLevel: Double = 1.0,
        showInGroups: Bool = false,
        groupByFieldOverride: SortField? = nil,
        sortFoldersFirst: Bool = true,
        sortHiddenLast: Bool = false,
        showPreviews: Bool = true,
        showsHiddenFilesOverride: Bool? = nil,
        visibleDetailsColumns: [DetailsColumn] = [.type, .size, .modificationDate]
    ) {
        self.mode = mode
        self.sortField = sortField
        self.ascending = ascending
        self.zoomLevel = zoomLevel
        self.showInGroups = showInGroups
        self.groupByFieldOverride = groupByFieldOverride
        self.sortFoldersFirst = sortFoldersFirst
        self.sortHiddenLast = sortHiddenLast
        self.showPreviews = showPreviews
        self.showsHiddenFilesOverride = showsHiddenFilesOverride
        self.visibleDetailsColumns = visibleDetailsColumns
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case sortField
        case ascending
        case zoomLevel
        case showInGroups
        case groupByFieldOverride
        case sortFoldersFirst
        case sortHiddenLast
        case showPreviews
        case showsHiddenFilesOverride
        case visibleDetailsColumns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = (try? c.decodeIfPresent(ViewMode.self, forKey: .mode)) ?? .list
        self.sortField = (try? c.decodeIfPresent(SortField.self, forKey: .sortField)) ?? .name
        self.ascending = (try? c.decodeIfPresent(Bool.self, forKey: .ascending)) ?? true
        self.zoomLevel = (try? c.decodeIfPresent(Double.self, forKey: .zoomLevel)) ?? 1.0
        self.showInGroups = (try? c.decodeIfPresent(Bool.self, forKey: .showInGroups)) ?? false
        self.groupByFieldOverride = try? c.decodeIfPresent(SortField.self, forKey: .groupByFieldOverride)
        self.sortFoldersFirst = (try? c.decodeIfPresent(Bool.self, forKey: .sortFoldersFirst)) ?? true
        self.sortHiddenLast = (try? c.decodeIfPresent(Bool.self, forKey: .sortHiddenLast)) ?? false
        self.showPreviews = (try? c.decodeIfPresent(Bool.self, forKey: .showPreviews)) ?? true
        self.showsHiddenFilesOverride = try? c.decodeIfPresent(Bool.self, forKey: .showsHiddenFilesOverride)
        self.visibleDetailsColumns = (try? c.decodeIfPresent([DetailsColumn].self, forKey: .visibleDetailsColumns))
            ?? [.type, .size, .modificationDate]
    }
}
