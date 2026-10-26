import SwiftUI

struct FileListView: View {
    let items: [FileItem]
    @Binding var selectedID: FileItem.ID?
    let gitStatuses: [String: GitFileStatus]
    /// `nil` cuando esta lista muestra resultados de búsqueda de varias
    /// carpetas a la vez — ahí soltar sobre el fondo no tiene un destino
    /// sin ambigüedad, así que ese drop se deshabilita. Soltar sobre una
    /// fila de carpeta puntual sigue funcionando siempre.
    let currentURL: URL?
    let onOpen: (FileItem) -> Void
    let onDelete: (FileItem) -> Void
    let onMoveDropped: ([URL], URL) -> Void

    var body: some View {
        List(items, selection: $selectedID) { item in
            HStack {
                Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                GitStatusBadge(status: gitStatuses[item.name])
            }
            .contentShape(Rectangle())
            .draggable(item.url)
            .dropDestination(for: URL.self) { urls, _ in
                let destination = item.isDirectory ? item.url : currentURL
                guard let destination else { return false }
                onMoveDropped(urls, destination)
                return true
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let currentURL else { return false }
            onMoveDropped(urls, currentURL)
            return true
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                Button("Eliminar", role: .destructive) { onDelete(item) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                onOpen(item)
            }
        }
    }
}
