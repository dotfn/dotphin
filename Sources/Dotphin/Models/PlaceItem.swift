import Foundation

enum PlaceKind: String, Codable, Equatable {
    case bookmark
    case customBookmark
    case volume
}

struct PlaceItem: Identifiable, Hashable, Codable {
    let url: URL
    let name: String
    let systemImage: String
    let kind: PlaceKind
    var isEjectable: Bool = true

    var id: URL { url }

    /// Native Spanish display title for standard macOS sidebar folders while keeping `name` stable for serialization/tests.
    var localizedDisplayName: String {
        guard kind == .bookmark else { return name }
        switch name {
        case "Home": return "Inicio"
        case "Desktop": return "Escritorio"
        case "Documents": return "Documentos"
        case "Downloads": return "Descargas"
        case "Trash": return "Papelera"
        default: return name
        }
    }
}
