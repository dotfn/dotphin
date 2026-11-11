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
    /// Símbolo elegido por el usuario para la barra lateral ("Cambiar ícono…").
    var customSymbol: String? = nil

    var id: URL { url }

    /// Native Spanish display title for standard macOS sidebar folders while keeping `name` stable for serialization/tests.
    var localizedDisplayName: String {
        guard kind == .bookmark else { return name }
        switch name {
        case "Home": return String(localized: "Inicio", bundle: #bundle)
        case "Desktop": return String(localized: "Escritorio", bundle: #bundle)
        case "Documents": return String(localized: "Documentos", bundle: #bundle)
        case "Downloads": return String(localized: "Descargas", bundle: #bundle)
        case "Applications": return String(localized: "Aplicaciones", bundle: #bundle)
        case "Trash": return String(localized: "Papelera", bundle: #bundle)
        default: return name
        }
    }
}
