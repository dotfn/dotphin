import AppKit
import SwiftUI

struct DetailsListView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var visibleColumns: [DetailsColumn] = [.type, .size, .modificationDate]
    var zoomLevel: Double = 1.0
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let currentURL: URL
    var sortField: SortField = .name
    var ascending: Bool = true
    var onChangeSort: ((SortField, Bool) -> Void)? = nil
    var onToggleColumn: ((DetailsColumn) -> Void)? = nil
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    var contextMenuActions: BrowserContextMenuActions? = nil

    @State private var expandedDirectories: Set<URL> = []
    @State private var directoryChildren: [URL: [FileItem]] = [:]

    private var flattenedRows: [DetailsTableRow] {
        var result: [DetailsTableRow] = []
        func appendItems(_ list: [FileItem], depth: Int) {
            for item in list {
                let isExpanded = item.isDirectory && expandedDirectories.contains(item.url)
                result.append(.item(item, depth: depth, isExpanded: isExpanded))
                if isExpanded, let children = directoryChildren[item.url] {
                    appendItems(children, depth: depth + 1)
                }
            }
        }
        if showInGroups && !groups.isEmpty {
            for group in groups {
                result.append(.header("\(group.title) (\(group.items.count))"))
                appendItems(group.items, depth: 0)
            }
        } else {
            appendItems(items, depth: 0)
        }
        return result
    }

    /// La tabla en sí es `DetailsTableView` (`NSTableView` nativo); acá quedan
    /// el estado de carpetas expandidas y los menús contextuales de SwiftUI.
    var body: some View {
        let contentSettings = AppSettingsModel.shared.settings
        DetailsTableView(
            rows: flattenedRows,
            visibleColumns: DetailsColumn.allCases.filter(visibleColumns.contains),
            zoomLevel: zoomLevel,
            selection: $selection,
            gitStatuses: gitStatuses,
            expandableFolders: contentSettings.expandableFoldersInDetails,
            directorySizeMode: contentSettings.directorySizeMode,
            useRelativeDates: contentSettings.useRelativeDates,
            permissionsFormat: contentSettings.permissionsFormat,
            currentURL: currentURL,
            sortField: sortField,
            ascending: ascending,
            onChangeSort: onChangeSort,
            onToggleColumn: onToggleColumn,
            onOpen: onOpen,
            onToggleExpansion: toggleExpansion(for:),
            onMoveDropped: onMoveDropped,
            menuForItems: { targetItems in
                makeFileItemsMenu(
                    for: targetItems,
                    actions: contextMenuActions,
                    onRename: onRename,
                    onBatchRename: onBatchRename,
                    onDelete: onDelete,
                    onDeleteSelection: onDeleteSelection
                )
            }
        )
        .onChange(of: currentURL) { _, _ in
            expandedDirectories.removeAll()
            directoryChildren.removeAll()
        }
    }

    private func toggleExpansion(for directoryURL: URL) {
        if expandedDirectories.contains(directoryURL) {
            expandedDirectories.remove(directoryURL)
        } else {
            let showsHidden = AppSettingsModel.shared.settings.showsHiddenFiles
            let reader = DirectoryReader(showsHiddenFiles: showsHidden)
            if let children = try? reader.contents(of: directoryURL, sortField: sortField, ascending: ascending) {
                directoryChildren[directoryURL] = children
            } else {
                directoryChildren[directoryURL] = []
            }
            expandedDirectories.insert(directoryURL)
        }
    }
}
