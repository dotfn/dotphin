import AppKit
import SwiftUI

/// Actions surfaced in Dolphin's context menu (`DolphinContextMenu`) for items and the folder viewport.
struct BrowserContextMenuActions {
    let viewModel: BrowserViewModel
    var otherPaneURL: URL? = nil
    var onCrossPaneTransferCompleted: (() -> Void)? = nil
    var onOpen: (FileItem) -> Void
    var onOpenInNewTab: ((URL) -> Void)?
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onCompareItems: ((URL, URL) -> Void)? = nil
    var onNewFolderPrompt: () -> Void
    var onMoveToNewFolderPrompt: (() -> Void)? = nil
    var onNewFilePrompt: (String) -> Void
    var onNewSymbolicLinkPrompt: (() -> Void)? = nil
    var onRename: (FileItem) -> Void
    var onBatchRename: () -> Void
    var onDelete: (FileItem) -> Void
    var onDeleteSelection: () -> Void
    var onDeletePermanently: (([FileItem]) -> Void)? = nil
    var onShowProperties: (URL) -> Void
    var onShowViewPropertiesDialog: (() -> Void)? = nil
    var onSelectByPatternPrompt: (() -> Void)? = nil
    var onShowGitRepoSheet: (([FileItem]) -> Void)? = nil
    var onInspectArchive: ((FileItem) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)?
}

struct DotphinItemContextMenu: View {
    let targetItems: [FileItem]
    let actions: BrowserContextMenuActions

    private var singleItem: FileItem? {
        targetItems.count == 1 ? targetItems.first : nil
    }

    var body: some View {
        if actions.viewModel.isBrowsingTrash {
            trashItemMenuBody
        } else {
            standardItemMenuBody
        }
    }

    @ViewBuilder
    private var trashItemMenuBody: some View {
        Button(targetItems.count > 1 ? "Restaurar de la Papelera (\(targetItems.count) ítems)" : "Restaurar de la Papelera") {
            actions.viewModel.restoreItemsFromTrash(targetItems)
        }
        Divider()
        Button("Cortar") {
            ensureTargetItemsSelected()
            actions.viewModel.cutSelected()
        }
        Button("Copiar") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelected()
        }
        Divider()
        Button(
            targetItems.count > 1
                ? "Eliminar permanentemente \(targetItems.count) ítems…"
                : "Eliminar permanentemente…",
            role: .destructive
        ) {
            if let onDeletePermanently = actions.onDeletePermanently {
                onDeletePermanently(targetItems)
            } else {
                actions.viewModel.deletePermanently(targetItems)
            }
        }
        if let item = singleItem {
            Divider()
            Button("Propiedades…") {
                actions.onShowProperties(item.url)
            }
        }
    }

    @ViewBuilder
    private var standardItemMenuBody: some View {
        if let item = singleItem {
            Button("Abrir") {
                actions.onOpen(item)
            }
            if item.isDirectory, let onOpenInNewTab = actions.onOpenInNewTab {
                Button("Abrir en una pestaña nueva") {
                    onOpenInNewTab(item.url)
                }
            }
            if item.isDirectory, let onOpenInSplitView = actions.onOpenInSplitView {
                Button("Abrir en vista dividida") {
                    onOpenInSplitView(item.url)
                }
            }
            let parentFolder = item.url.deletingLastPathComponent()
            if parentFolder.standardizedFileURL.path != actions.viewModel.currentURL.standardizedFileURL.path {
                Button("Abrir ubicación contenedora") {
                    actions.viewModel.openContainingFolder(of: item)
                }
                if let onOpenInNewTab = actions.onOpenInNewTab {
                    Button("Abrir ubicación contenedora en pestaña nueva") {
                        onOpenInNewTab(parentFolder)
                    }
                }
            }
            if item.isSymbolicLink {
                Button("Mostrar destino del enlace") {
                    actions.viewModel.showSymbolicLinkTarget(item)
                }
            }
            openWithMenu(for: item.url)

            Button("Vista rápida de «\(item.name)»") {
                ensureTargetItemsSelected()
                QuickLookPreviewController.shared.show(for: actions.viewModel)
            }

            Divider()

            if item.isDirectory {
                createNewMenu
                Divider()
            }
        } else if !targetItems.isEmpty {
            let allDirs = targetItems.allSatisfy(\.isDirectory)
            if allDirs, let onOpenInNewTab = actions.onOpenInNewTab {
                Button("Abrir en pestañas nuevas") {
                    for dir in targetItems {
                        onOpenInNewTab(dir.url)
                    }
                }
            }
            if targetItems.count == 2, let onCompareItems = actions.onCompareItems {
                Button("Comparar «\(targetItems[0].name)» y «\(targetItems[1].name)»…") {
                    onCompareItems(targetItems[0].url, targetItems[1].url)
                }
            }
            Button("Vista rápida de \(targetItems.count) ítems") {
                ensureTargetItemsSelected()
                QuickLookPreviewController.shared.show(for: actions.viewModel)
            }
            Divider()
        }

        Button("Cortar") {
            ensureTargetItemsSelected()
            actions.viewModel.cutSelected()
        }
        Button("Copiar") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelected()
        }
        Button(targetItems.count > 1 ? "Copiar ubicaciones" : "Copiar ubicación") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelectedPathsToPasteboard()
        }
        if let item = singleItem, item.isDirectory, actions.viewModel.canPaste {
            Button("Pegar dentro de la carpeta") {
                actions.viewModel.paste(into: item.url)
            }
        } else if actions.viewModel.canPaste {
            Button("Pegar") {
                actions.viewModel.paste()
            }
        }

        if let otherPaneURL = actions.otherPaneURL {
            Divider()
            Button("Copiar al otro panel dividido") {
                ensureTargetItemsSelected()
                actions.viewModel.copySelected(to: otherPaneURL)
                actions.onCrossPaneTransferCompleted?()
            }
            Button("Mover al otro panel dividido") {
                ensureTargetItemsSelected()
                actions.viewModel.moveSelected(to: otherPaneURL)
                actions.onCrossPaneTransferCompleted?()
            }
        }

        copyOrMoveToDestinationsMenus

        Divider()

        Button("Duplicar aquí") {
            ensureTargetItemsSelected()
            actions.viewModel.duplicateSelected()
        }

        Button(targetItems.count > 1 ? "Crear enlaces simbólicos aquí" : "Crear enlace simbólico aquí") {
            ensureTargetItemsSelected()
            actions.viewModel.createSymbolicLinkToSelected()
        }

        if let onMoveToNewFolderPrompt = actions.onMoveToNewFolderPrompt,
           !(targetItems.count == 1 && (singleItem?.isDirectory ?? false)) {
            Button("Mover a una carpeta nueva…") {
                ensureTargetItemsSelected()
                onMoveToNewFolderPrompt()
            }
        }

        Button(
            targetItems.count > 1
                ? "Comprimir \(targetItems.count) ítems en ZIP"
                : "Comprimir «\(singleItem?.name ?? "")» en ZIP"
        ) {
            ensureTargetItemsSelected()
            actions.viewModel.compressSelected()
        }

        if let item = singleItem, !item.isDirectory, ArchiveService.isArchive(item.url) {
            if let onInspectArchive = actions.onInspectArchive {
                Button("Inspeccionar contenido del archivo comprimido…") {
                    onInspectArchive(item)
                }
            }
            Button("Extraer archivo aquí") {
                actions.viewModel.extractArchive(item)
            }
        }

        if targetItems.count > 1 {
            Button("Renombrar \(targetItems.count) ítems…") {
                ensureTargetItemsSelected()
                actions.onBatchRename()
            }
        } else if let item = singleItem {
            Button("Renombrar…") {
                actions.onRename(item)
            }
        }

        Divider()

        // Dolphin Item Actions: Color Tags, Folder Icons, Hide/Unhide (.hidden), Bookmarks
        colorTagMenu

        if let item = singleItem, item.isDirectory {
            folderIconMenu(for: item.url)

            let placesProvider = PlacesProvider()
            if placesProvider.isBookmarked(item.url) {
                Button("Quitar de Lugares") {
                    placesProvider.removeBookmark(for: item.url)
                }
            } else {
                Button("Añadir a Lugares") {
                    placesProvider.addBookmark(for: item.url, name: item.name)
                }
            }
        }

        hideItemActionButtons

        if actions.viewModel.isGitRepository {
            gitVersionControlMenu
        }

        Divider()

        if let item = singleItem {
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.isDirectory, let onOpenTerminal = actions.onOpenTerminal {
                Button("Abrir Terminal aquí") {
                    onOpenTerminal(item.url)
                }
            }
            Divider()
        }

        if targetItems.count > 1 {
            Button("Mover \(targetItems.count) ítems a la Papelera", role: .destructive) {
                ensureTargetItemsSelected()
                actions.onDeleteSelection()
            }
        } else if let item = singleItem {
            Button("Mover a la Papelera", role: .destructive) {
                actions.onDelete(item)
            }
        }

        if AppSettingsModel.shared.settings.showPermanentDeleteCommand {
            Button(
                targetItems.count > 1
                    ? "Eliminar permanentemente \(targetItems.count) ítems…"
                    : "Eliminar permanentemente…",
                role: .destructive
            ) {
                ensureTargetItemsSelected()
                if let onDeletePermanently = actions.onDeletePermanently {
                    onDeletePermanently(targetItems)
                } else {
                    actions.viewModel.deletePermanently(targetItems)
                }
            }
        }

        if let item = singleItem {
            Divider()
            Button("Propiedades…") {
                actions.onShowProperties(item.url)
            }
        }
    }

    @ViewBuilder
    private var copyOrMoveToDestinationsMenus: some View {
        let provider = PlacesProvider()
        let destinations = (provider.staticBookmarks().filter { $0.name != "Trash" } + provider.customBookmarks())
        Menu("Copiar a") {
            ForEach(destinations) { dest in
                Button(dest.name) {
                    ensureTargetItemsSelected()
                    actions.viewModel.copySelected(to: dest.url)
                }
            }
            Divider()
            Button("Elegir carpeta…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Copiar aquí"
                if panel.runModal() == .OK, let targetDir = panel.url {
                    ensureTargetItemsSelected()
                    actions.viewModel.copySelected(to: targetDir)
                }
            }
        }

        Menu("Mover a") {
            ForEach(destinations) { dest in
                Button(dest.name) {
                    ensureTargetItemsSelected()
                    actions.viewModel.moveSelected(to: dest.url)
                }
            }
            Divider()
            Button("Elegir carpeta…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Mover aquí"
                if panel.runModal() == .OK, let targetDir = panel.url {
                    ensureTargetItemsSelected()
                    actions.viewModel.moveSelected(to: targetDir)
                }
            }
        }
    }

    @ViewBuilder
    private var gitVersionControlMenu: some View {
        Menu("Control de versiones (Git)") {
            if let branch = actions.viewModel.gitBranchName {
                Text("Rama: \(branch)")
                Divider()
            }
            Button("Añadir al área de preparación (git add)") {
                actions.viewModel.gitStageItems(targetItems)
            }
            Button("Quitar del área de preparación (git restore --staged)") {
                actions.viewModel.gitUnstageItems(targetItems)
            }
            Button("Descartar cambios locales (git checkout --)", role: .destructive) {
                actions.viewModel.gitDiscardChanges(targetItems)
            }
            if let onShowGitRepoSheet = actions.onShowGitRepoSheet {
                Divider()
                Button("Ver diferencias, historial y crear commit…") {
                    onShowGitRepoSheet(targetItems)
                }
            }
        }
    }

    @ViewBuilder
    private var colorTagMenu: some View {
        Menu("Etiqueta de color") {
            ForEach(FinderColorTag.allCases) { tag in
                Button {
                    actions.viewModel.setColorTag(tag, for: targetItems)
                } label: {
                    HStack {
                        Text(tag.title)
                        if let singleItem, singleItem.colorTag == tag {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderIconMenu(for folderURL: URL) -> some View {
        Menu("Icono de carpeta") {
            ForEach(FolderIconPreset.allCases) { preset in
                Button {
                    actions.viewModel.setFolderIcon(preset, for: folderURL)
                } label: {
                    if let badge = preset.badgeSymbol {
                        Label(preset.title, systemImage: badge)
                    } else {
                        Label(preset.title, systemImage: "folder")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hideItemActionButtons: some View {
        let nonDotTargets = targetItems.filter { !$0.name.hasPrefix(".") }
        if !nonDotTargets.isEmpty {
            let anyHidden = nonDotTargets.contains(where: \.isHiddenInDotHidden)
            let anyVisible = nonDotTargets.contains { !$0.isHiddenInDotHidden }
            if anyVisible {
                Button("Ocultar (en .hidden)") {
                    actions.viewModel.hideItemsInDotHidden(nonDotTargets)
                }
            }
            if anyHidden {
                Button("Mostrar (quitar de .hidden)") {
                    actions.viewModel.unhideItemsInDotHidden(nonDotTargets)
                }
            }
        }
    }

    private func ensureTargetItemsSelected() {
        let ids = Set(targetItems.map(\.id))
        if actions.viewModel.selectedIDs != ids {
            actions.viewModel.setSelection(ids)
        }
    }

    @ViewBuilder
    private var createNewMenu: some View {
        Menu("Crear nuevo") {
            Button("Carpeta…") {
                actions.onNewFolderPrompt()
            }
            if let onNewSymbolicLinkPrompt = actions.onNewSymbolicLinkPrompt {
                Button("Enlace simbólico…") {
                    onNewSymbolicLinkPrompt()
                }
            }
            Divider()
            Button("Archivo de texto…") {
                actions.onNewFilePrompt("Nuevo archivo.txt")
            }
            Button("Documento Markdown…") {
                actions.onNewFilePrompt("Nota.md")
            }
            Button("Script de Shell…") {
                actions.onNewFilePrompt("script.sh")
            }
            Button("Archivo Swift…") {
                actions.onNewFilePrompt("Archivo.swift")
            }
            Button("Documento JSON…") {
                actions.onNewFilePrompt("datos.json")
            }
            Button("Página HTML…") {
                actions.onNewFilePrompt("index.html")
            }
        }
    }

    @ViewBuilder
    private func openWithMenu(for url: URL) -> some View {
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if !appURLs.isEmpty {
            Menu("Abrir con") {
                ForEach(appURLs, id: \.self) { appURL in
                    let appName = appURL.deletingPathExtension().lastPathComponent
                    Button(appName) {
                        NSWorkspace.shared.open(
                            [url],
                            withApplicationAt: appURL,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                    }
                }
            }
        }
    }
}

struct DotphinViewportContextMenu: View {
    let actions: BrowserContextMenuActions

    var body: some View {
        if actions.viewModel.isBrowsingTrash {
            Button("Vaciar la Papelera…", role: .destructive) {
                actions.viewModel.emptyTrash()
            }
            .disabled(actions.viewModel.items.isEmpty)
            Divider()
        } else {
            Menu("Crear nuevo") {
                Button("Carpeta…") {
                    actions.onNewFolderPrompt()
                }
                if let onNewSymbolicLinkPrompt = actions.onNewSymbolicLinkPrompt {
                    Button("Enlace simbólico…") {
                        onNewSymbolicLinkPrompt()
                    }
                }
                Divider()
                Button("Archivo de texto…") {
                    actions.onNewFilePrompt("Nuevo archivo.txt")
                }
                Button("Documento Markdown…") {
                    actions.onNewFilePrompt("Nota.md")
                }
                Button("Script de Shell…") {
                    actions.onNewFilePrompt("script.sh")
                }
                Button("Archivo Swift…") {
                    actions.onNewFilePrompt("Archivo.swift")
                }
                Button("Documento JSON…") {
                    actions.onNewFilePrompt("datos.json")
                }
                Button("Página HTML…") {
                    actions.onNewFilePrompt("index.html")
                }
            }
        }

        if actions.viewModel.canPaste {
            Button("Pegar") {
                actions.viewModel.paste()
            }
        }

        Divider()

        Menu("Modo de vista") {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    actions.viewModel.setViewMode(mode)
                } label: {
                    HStack {
                        Text(mode.title)
                        if actions.viewModel.viewProperties.mode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Ordenar por") {
            ForEach(SortField.allCases, id: \.self) { field in
                Button {
                    let isSameField = actions.viewModel.viewProperties.sortField == field
                    let nextAscending = isSameField
                        ? !actions.viewModel.viewProperties.ascending
                        : field.defaultAscending
                    actions.viewModel.setSort(field: field, ascending: nextAscending)
                } label: {
                    HStack {
                        Text(field.title)
                        if actions.viewModel.viewProperties.sortField == field {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(actions.viewModel.viewProperties.ascending ? "Ascendente ✓" : "Descendente ✓") {
                actions.viewModel.setSort(
                    field: actions.viewModel.viewProperties.sortField,
                    ascending: !actions.viewModel.viewProperties.ascending
                )
            }
            Divider()
            Button(actions.viewModel.viewProperties.sortFoldersFirst ? "Carpetas primero ✓" : "Carpetas primero") {
                actions.viewModel.toggleSortFoldersFirst()
            }
            Button(actions.viewModel.viewProperties.sortHiddenLast ? "Archivos ocultos al final ✓" : "Archivos ocultos al final") {
                actions.viewModel.toggleSortHiddenLast()
            }
            Divider()
            Button(actions.viewModel.viewProperties.showInGroups ? "Mostrar en grupos ✓" : "Mostrar en grupos") {
                actions.viewModel.toggleShowInGroups()
            }
        }

        Menu("Agrupar por") {
            let props = actions.viewModel.viewProperties
            Button {
                actions.viewModel.setGroupBy(showInGroups: false, groupFieldOverride: nil)
            } label: {
                HStack {
                    Text("Ninguno")
                    if !props.showInGroups {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                actions.viewModel.setGroupBy(showInGroups: true, groupFieldOverride: nil)
            } label: {
                HStack {
                    Text("Igual que el criterio de ordenación")
                    if props.showInGroups && props.groupByFieldOverride == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(SortField.allCases, id: \.self) { field in
                Button {
                    actions.viewModel.setGroupBy(showInGroups: true, groupFieldOverride: field)
                } label: {
                    HStack {
                        Text(field.title)
                        if props.showInGroups && props.groupByFieldOverride == field {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        if actions.viewModel.viewProperties.mode == .details {
            Menu("Columnas visibles") {
                ForEach(DetailsColumn.allCases) { col in
                    let isVisible = actions.viewModel.viewProperties.visibleDetailsColumns.contains(col)
                    Button {
                        actions.viewModel.toggleDetailsColumn(col)
                    } label: {
                        HStack {
                            Text(col.title)
                            if isVisible {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        Button(actions.viewModel.viewProperties.showPreviews ? "Mostrar vistas previas ✓" : "Mostrar vistas previas") {
            actions.viewModel.toggleShowPreviews()
        }

        Button(actions.viewModel.effectiveShowsHiddenFiles ? "Mostrar archivos ocultos ✓" : "Mostrar archivos ocultos") {
            actions.viewModel.toggleShowsHiddenFiles()
        }

        if let onShowViewPropertiesDialog = actions.onShowViewPropertiesDialog {
            Button("Estilo de visualización de vista…") {
                onShowViewPropertiesDialog()
            }
        }

        Button("Restablecer valores de vista predeterminados") {
            actions.viewModel.resetViewPropertiesToDefault()
        }

        Divider()

        Button(actions.viewModel.isSelectionModeActive ? "Salir del modo de selección" : "Modo de selección") {
            actions.viewModel.isSelectionModeActive.toggle()
        }
        Button("Seleccionar todo") {
            actions.viewModel.selectAll()
        }
        if let onSelectByPatternPrompt = actions.onSelectByPatternPrompt {
            Button("Seleccionar ítems por patrón…") {
                onSelectByPatternPrompt()
            }
        }
        Button("Invertir selección") {
            actions.viewModel.invertSelection()
        }

        Divider()

        let placesProvider = PlacesProvider()
        if placesProvider.isBookmarked(actions.viewModel.currentURL) {
            Button("Quitar carpeta actual de Lugares") {
                placesProvider.removeBookmark(for: actions.viewModel.currentURL)
            }
        } else {
            Button("Añadir carpeta actual a Lugares") {
                placesProvider.addBookmark(for: actions.viewModel.currentURL)
            }
        }

        Button("Copiar ubicación") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(actions.viewModel.currentURL.path, forType: .string)
        }
        Button("Mostrar carpeta en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([actions.viewModel.currentURL])
        }
        if let onOpenTerminal = actions.onOpenTerminal {
            Button("Abrir Terminal aquí") {
                onOpenTerminal(actions.viewModel.currentURL)
            }
        }
        if actions.viewModel.isGitRepository, let onShowGitRepoSheet = actions.onShowGitRepoSheet {
            Button("Control de versiones Git (\(actions.viewModel.gitBranchName ?? "repo"))…") {
                onShowGitRepoSheet([])
            }
        }

        Divider()

        Button("Propiedades…") {
            actions.onShowProperties(actions.viewModel.currentURL)
        }
    }
}
