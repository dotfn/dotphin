import Foundation

enum PlaceKind: Equatable {
    case bookmark
    case volume
}

struct PlaceItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let systemImage: String
    let kind: PlaceKind
    var isEjectable: Bool = true

    var id: URL { url }
}
