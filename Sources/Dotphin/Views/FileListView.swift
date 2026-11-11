import AppKit
import SwiftUI

/// Vista "Lista". La tabla en sí es `FileTableView` (`NSTableView` nativo);
/// acá solo se arman los menús contextuales, que siguen siendo los de SwiftUI.
struct FileListView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var zoomLevel: Double = 1.0
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    /// `nil` cuando esta lista muestra resultados de búsqueda de varias
    /// carpetas a la vez — ahí soltar sobre el fondo no tiene un destino
    /// sin ambigüedad, así que ese drop se deshabilita. Soltar sobre una
    /// fila de carpeta puntual sigue funcionando siempre.
    let currentURL: URL?
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    var contextMenuActions: BrowserContextMenuActions? = nil

    var body: some View {
        FileTableView(
            items: items,
            groups: groups,
            showInGroups: showInGroups,
            zoomLevel: zoomLevel,
            selection: $selection,
            gitStatuses: gitStatuses,
            directorySizeMode: AppSettingsModel.shared.settings.directorySizeMode,
            currentURL: currentURL,
            onOpen: onOpen,
            onMoveDropped: onMoveDropped,
            menuForItems: { targetItems, shareAnchor in
                makeFileItemsMenu(
                    for: targetItems,
                    actions: contextMenuActions,
                    onRename: onRename,
                    onBatchRename: onBatchRename,
                    onDelete: onDelete,
                    onDeleteSelection: onDeleteSelection,
                    shareAnchor: shareAnchor
                )
            }
        )
    }
}

/// Menú contextual de las vistas de archivos de AppKit: los mismos menús de
/// SwiftUI, convertidos a `NSMenu` con `NSHostingMenu`. Sin ítems = fondo.
@MainActor
func makeFileItemsMenu(
    for targetItems: [FileItem],
    actions: BrowserContextMenuActions?,
    onRename: ((FileItem) -> Void)?,
    onBatchRename: (() -> Void)?,
    onDelete: @escaping (FileItem) -> Void,
    onDeleteSelection: @escaping () -> Void,
    shareAnchor: ShareAnchor? = nil
) -> NSMenu? {
    if var actions {
        actions.shareAnchor = shareAnchor
        if targetItems.isEmpty {
            return NSHostingMenu(rootView: DotphinViewportContextMenu(actions: actions))
        }
        return NSHostingMenu(rootView: DotphinItemContextMenu(targetItems: targetItems, actions: actions))
    }
    guard !targetItems.isEmpty else { return nil }
    return NSHostingMenu(rootView: FallbackItemMenu(
        targetItems: targetItems,
        onRename: onRename,
        onBatchRename: onBatchRename,
        onDelete: onDelete,
        onDeleteSelection: onDeleteSelection
    ))
}

/// Menú mínimo para cuando no hay `BrowserContextMenuActions`.
private struct FallbackItemMenu: View {
    let targetItems: [FileItem]
    let onRename: ((FileItem) -> Void)?
    let onBatchRename: (() -> Void)?
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void

    var body: some View {
        if targetItems.count > 1 {
            if let onBatchRename {
                Button(String(localized: "Renombrar \(targetItems.count) ítems…", bundle: #bundle)) { onBatchRename() }
            }
            Button(String(localized: "Eliminar \(targetItems.count) ítems", bundle: #bundle), role: .destructive) { onDeleteSelection() }
        } else if let item = targetItems.first {
            if let onRename {
                Button(String(localized: "Renombrar…", bundle: #bundle)) { onRename(item) }
            }
            Button(String(localized: "Eliminar", bundle: #bundle), role: .destructive) { onDelete(item) }
        }
    }
}
