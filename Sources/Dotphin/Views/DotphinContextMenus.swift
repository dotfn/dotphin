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
    var onNewFileFromTemplatePrompt: ((URL) -> Void)? = nil
    var onMountDiskImage: ((FileItem) -> Void)? = nil
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
    /// Ícono del archivo que se tocó, para abrir Compartir apuntándolo.
    var shareAnchor: ShareAnchor? = nil
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
        Button(targetItems.count > 1 ? String(localized: "Restaurar de la Papelera (\(targetItems.count) ítems)", bundle: #bundle) : String(localized: "Restaurar de la Papelera", bundle: #bundle), menuIcon: "arrow.uturn.backward") {
            actions.viewModel.restoreItemsFromTrash(targetItems)
        }
        Divider()
        Button(String(localized: "Cortar", bundle: #bundle), menuIcon: "scissors") {
            ensureTargetItemsSelected()
            actions.viewModel.cutSelected()
        }
        Button(String(localized: "Copiar", bundle: #bundle), menuIcon: "doc.on.doc") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelected()
        }
        Divider()
        Button(
            targetItems.count > 1
                ? String(localized: "Eliminar permanentemente \(targetItems.count) ítems…", bundle: #bundle)
                : String(localized: "Eliminar permanentemente…", bundle: #bundle),
            menuIcon: "trash.slash",
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
            Button(String(localized: "Propiedades…", bundle: #bundle), menuIcon: "info.circle") {
                actions.onShowProperties(item.url)
            }
        }
    }

    @ViewBuilder
    private var standardItemMenuBody: some View {
        if let item = singleItem {
            Button(String(localized: "Abrir", bundle: #bundle), menuIcon: "arrow.up.forward.square") {
                actions.onOpen(item)
            }
            if item.isDirectory, let onOpenInNewTab = actions.onOpenInNewTab {
                Button(String(localized: "Abrir en una pestaña nueva", bundle: #bundle), menuIcon: "plus.square.on.square") {
                    onOpenInNewTab(item.url)
                }
            }
            if item.isDirectory, let onOpenInSplitView = actions.onOpenInSplitView {
                Button(String(localized: "Abrir en vista dividida", bundle: #bundle), menuIcon: "rectangle.split.2x1") {
                    onOpenInSplitView(item.url)
                }
            }
            let parentFolder = item.url.deletingLastPathComponent()
            if parentFolder.standardizedFileURL.path != actions.viewModel.currentURL.standardizedFileURL.path {
                Button(String(localized: "Abrir ubicación contenedora", bundle: #bundle), menuIcon: "folder") {
                    actions.viewModel.openContainingFolder(of: item)
                }
                if let onOpenInNewTab = actions.onOpenInNewTab {
                    Button(String(localized: "Abrir ubicación contenedora en pestaña nueva", bundle: #bundle), menuIcon: "folder.badge.plus") {
                        onOpenInNewTab(parentFolder)
                    }
                }
            }
            if item.isSymbolicLink {
                Button(String(localized: "Mostrar destino del enlace", bundle: #bundle), menuIcon: "arrowshape.turn.up.right") {
                    actions.viewModel.showSymbolicLinkTarget(item)
                }
            }
            openWithMenu(for: item.url)

            if !item.isDirectory, DiskImageMountService.isDiskImage(item.url), let onMountDiskImage = actions.onMountDiskImage {
                Button(String(localized: "Montar imagen de disco", bundle: #bundle), menuIcon: "externaldrive.badge.plus") {
                    onMountDiskImage(item)
                }
            }

            Button(String(localized: "Vista rápida de «\(item.name)»", bundle: #bundle), menuIcon: "eye") {
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
                Button(String(localized: "Abrir en pestañas nuevas", bundle: #bundle), menuIcon: "plus.square.on.square") {
                    for dir in targetItems {
                        onOpenInNewTab(dir.url)
                    }
                }
            }
            if targetItems.count == 2, let onCompareItems = actions.onCompareItems {
                Button(String(localized: "Comparar «\(targetItems[0].name)» y «\(targetItems[1].name)»…", bundle: #bundle), menuIcon: "arrow.left.arrow.right") {
                    onCompareItems(targetItems[0].url, targetItems[1].url)
                }
            }
            Button(String(localized: "Vista rápida de \(targetItems.count) ítems", bundle: #bundle), menuIcon: "eye") {
                ensureTargetItemsSelected()
                QuickLookPreviewController.shared.show(for: actions.viewModel)
            }
            Divider()
        }

        Button(String(localized: "Cortar", bundle: #bundle), menuIcon: "scissors") {
            ensureTargetItemsSelected()
            actions.viewModel.cutSelected()
        }
        Button(String(localized: "Copiar", bundle: #bundle), menuIcon: "doc.on.doc") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelected()
        }
        Button(targetItems.count > 1 ? String(localized: "Copiar ubicaciones", bundle: #bundle) : String(localized: "Copiar ubicación", bundle: #bundle), menuIcon: "link") {
            ensureTargetItemsSelected()
            actions.viewModel.copySelectedPathsToPasteboard()
        }
        if let item = singleItem, item.isDirectory, actions.viewModel.canPaste {
            Button(String(localized: "Pegar dentro de la carpeta", bundle: #bundle), menuIcon: "doc.on.clipboard") {
                actions.viewModel.paste(into: item.url)
            }
        } else if actions.viewModel.canPaste {
            Button(String(localized: "Pegar", bundle: #bundle), menuIcon: "doc.on.clipboard") {
                actions.viewModel.paste()
            }
        }

        if let otherPaneURL = actions.otherPaneURL {
            Divider()
            Button(String(localized: "Copiar al otro panel dividido", bundle: #bundle), menuIcon: "doc.on.doc") {
                ensureTargetItemsSelected()
                actions.viewModel.copySelected(to: otherPaneURL)
                actions.onCrossPaneTransferCompleted?()
            }
            Button(String(localized: "Mover al otro panel dividido", bundle: #bundle), menuIcon: "arrow.right.square") {
                ensureTargetItemsSelected()
                actions.viewModel.moveSelected(to: otherPaneURL)
                actions.onCrossPaneTransferCompleted?()
            }
        }

        copyOrMoveToDestinationsMenus

        Divider()

        Button(String(localized: "Duplicar aquí", bundle: #bundle), menuIcon: "square.on.square") {
            ensureTargetItemsSelected()
            actions.viewModel.duplicateSelected()
        }

        Button(targetItems.count > 1 ? String(localized: "Crear enlaces simbólicos aquí", bundle: #bundle) : String(localized: "Crear enlace simbólico aquí", bundle: #bundle), menuIcon: "link.badge.plus") {
            ensureTargetItemsSelected()
            actions.viewModel.createSymbolicLinkToSelected()
        }

        if let onMoveToNewFolderPrompt = actions.onMoveToNewFolderPrompt,
           !(targetItems.count == 1 && (singleItem?.isDirectory ?? false)) {
            Button(String(localized: "Mover a una carpeta nueva…", bundle: #bundle), menuIcon: "folder.badge.plus") {
                ensureTargetItemsSelected()
                onMoveToNewFolderPrompt()
            }
        }

        Button(
            targetItems.count > 1
                ? String(localized: "Comprimir \(targetItems.count) ítems en ZIP", bundle: #bundle)
                : String(localized: "Comprimir «\(singleItem?.name ?? "")» en ZIP", bundle: #bundle),
            menuIcon: "archivebox"
        ) {
            ensureTargetItemsSelected()
            actions.viewModel.compressSelected()
        }

        if let item = singleItem, !item.isDirectory, ArchiveService.isArchive(item.url) {
            if let onInspectArchive = actions.onInspectArchive {
                Button(String(localized: "Inspeccionar contenido del archivo comprimido…", bundle: #bundle), menuIcon: "doc.text.magnifyingglass") {
                    onInspectArchive(item)
                }
            }
            Button(String(localized: "Extraer archivo aquí", bundle: #bundle), menuIcon: "arrow.up.doc") {
                actions.viewModel.extractArchive(item)
            }
        }

        if targetItems.count > 1 {
            Button(String(localized: "Renombrar \(targetItems.count) ítems…", bundle: #bundle), menuIcon: "pencil") {
                ensureTargetItemsSelected()
                actions.onBatchRename()
            }
        } else if let item = singleItem {
            Button(String(localized: "Renombrar…", bundle: #bundle), menuIcon: "pencil") {
                actions.onRename(item)
            }
        }

        Divider()

        // Como Finder: Compartir (AirDrop, Mail, Mensajes…) y la fila de colores.
        Button(String(localized: "Compartir…", bundle: #bundle), menuIcon: "square.and.arrow.up") {
            SharePresenter.share(targetItems.map(\.url), anchor: actions.shareAnchor)
        }
        colorTagPalette

        Divider()

        // Dolphin Item Actions: Folder Icons, Hide/Unhide (.hidden), Bookmarks

        if let item = singleItem, item.isDirectory {
            folderIconMenu(for: item.url)

            let placesProvider = PlacesProvider()
            if placesProvider.isBookmarked(item.url) {
                Button(String(localized: "Quitar de Lugares", bundle: #bundle), menuIcon: "bookmark.slash") {
                    placesProvider.removeBookmark(for: item.url)
                }
            } else {
                Button(String(localized: "Añadir a Lugares", bundle: #bundle), menuIcon: "bookmark") {
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
            Button(String(localized: "Mostrar en Finder", bundle: #bundle), menuIcon: "macwindow") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.isDirectory, let onOpenTerminal = actions.onOpenTerminal {
                Button(String(localized: "Abrir Terminal aquí", bundle: #bundle), menuIcon: "terminal") {
                    onOpenTerminal(item.url)
                }
            }
            Divider()
        }

        if targetItems.count > 1 {
            Button(String(localized: "Mover \(targetItems.count) ítems a la Papelera", bundle: #bundle), menuIcon: "trash", role: .destructive) {
                ensureTargetItemsSelected()
                actions.onDeleteSelection()
            }
        } else if let item = singleItem {
            Button(String(localized: "Mover a la Papelera", bundle: #bundle), menuIcon: "trash", role: .destructive) {
                actions.onDelete(item)
            }
        }

        if AppSettingsModel.shared.settings.showPermanentDeleteCommand {
            Button(
                targetItems.count > 1
                    ? String(localized: "Eliminar permanentemente \(targetItems.count) ítems…", bundle: #bundle)
                    : String(localized: "Eliminar permanentemente…", bundle: #bundle),
                menuIcon: "trash.slash",
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
            Button(String(localized: "Propiedades…", bundle: #bundle), menuIcon: "info.circle") {
                actions.onShowProperties(item.url)
            }
        }
    }

    @ViewBuilder
    private var copyOrMoveToDestinationsMenus: some View {
        let provider = PlacesProvider()
        let destinations = (provider.staticBookmarks().filter { $0.name != "Trash" } + provider.customBookmarks())
        Menu(String(localized: "Copiar a", bundle: #bundle), menuIcon: "doc.on.doc") {
            ForEach(destinations) { dest in
                Button(dest.name) {
                    ensureTargetItemsSelected()
                    actions.viewModel.copySelected(to: dest.url)
                }
            }
            Divider()
            Button(String(localized: "Elegir carpeta…", bundle: #bundle), menuIcon: "folder") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = String(localized: "Copiar aquí", bundle: #bundle)
                if panel.runModal() == .OK, let targetDir = panel.url {
                    ensureTargetItemsSelected()
                    actions.viewModel.copySelected(to: targetDir)
                }
            }
        }

        Menu(String(localized: "Mover a", bundle: #bundle), menuIcon: "arrow.right.square") {
            ForEach(destinations) { dest in
                Button(dest.name) {
                    ensureTargetItemsSelected()
                    actions.viewModel.moveSelected(to: dest.url)
                }
            }
            Divider()
            Button(String(localized: "Elegir carpeta…", bundle: #bundle), menuIcon: "folder") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = String(localized: "Mover aquí", bundle: #bundle)
                if panel.runModal() == .OK, let targetDir = panel.url {
                    ensureTargetItemsSelected()
                    actions.viewModel.moveSelected(to: targetDir)
                }
            }
        }
    }

    @ViewBuilder
    private var gitVersionControlMenu: some View {
        Menu(String(localized: "Control de versiones (Git)", bundle: #bundle), menuIcon: "arrow.triangle.branch") {
            if let branch = actions.viewModel.gitBranchName {
                Text(String(localized: "Rama: \(branch)", bundle: #bundle))
                Divider()
            }
            Button(String(localized: "Añadir al área de preparación (git add)", bundle: #bundle), menuIcon: "plus.circle") {
                actions.viewModel.gitStageItems(targetItems)
            }
            Button(String(localized: "Quitar del área de preparación (git restore --staged)", bundle: #bundle), menuIcon: "minus.circle") {
                actions.viewModel.gitUnstageItems(targetItems)
            }
            Button(String(localized: "Descartar cambios locales (git checkout --)", bundle: #bundle), menuIcon: "arrow.uturn.backward", role: .destructive) {
                actions.viewModel.gitDiscardChanges(targetItems)
            }
            if let onShowGitRepoSheet = actions.onShowGitRepoSheet {
                Divider()
                Button(String(localized: "Ver diferencias, historial y crear commit…", bundle: #bundle), menuIcon: "clock.arrow.circlepath") {
                    onShowGitRepoSheet(targetItems)
                }
            }
        }
    }

    /// La fila de círculos de colores de Finder (`.palette`). Con varios ítems no
    /// hay una etiqueta "actual": ninguno va marcado. Los círculos se tiñen con
    /// `tint` en un `Label`: con `foregroundStyle` el menú los dibuja grises.
    @ViewBuilder
    private var colorTagPalette: some View {
        let current = singleItem?.colorTag
        let anyTagged = targetItems.contains { $0.colorTag != .none }
        Picker(selection: Binding<FinderColorTag?>(
            get: { current == FinderColorTag.none ? nil : current },
            set: { tag in
                guard let tag else { return }
                actions.viewModel.setColorTag(FinderColorTag.tagToApply(choosing: tag, current: current), for: targetItems)
            }
        )) {
            ForEach(FinderColorTag.finderPaletteOrder) { tag in
                SwiftUI.Label(tag.title, systemImage: "circle.fill")
                    .tint(Color(nsColor: tag.nsColor ?? .systemGray))
                    .tag(Optional(tag))
            }
            if anyTagged {
                SwiftUI.Label(FinderColorTag.none.title, systemImage: "xmark.circle")
                    .tag(Optional(FinderColorTag.none))
            }
        } label: {
            Text(String(localized: "Etiqueta de color", bundle: #bundle))
        }
        .pickerStyle(.palette)
    }

    @ViewBuilder
    private func folderIconMenu(for folderURL: URL) -> some View {
        Menu(String(localized: "Icono de carpeta", bundle: #bundle), menuIcon: "folder.badge.gearshape") {
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
                Button(String(localized: "Ocultar (en .hidden)", bundle: #bundle), menuIcon: "eye.slash") {
                    actions.viewModel.hideItemsInDotHidden(nonDotTargets)
                }
            }
            if anyHidden {
                Button(String(localized: "Mostrar (quitar de .hidden)", bundle: #bundle), menuIcon: "eye") {
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
        Menu(String(localized: "Crear nuevo", bundle: #bundle), menuIcon: "plus") {
            Button(String(localized: "Carpeta…", bundle: #bundle), menuIcon: "folder.badge.plus") {
                actions.onNewFolderPrompt()
            }
            if let onNewSymbolicLinkPrompt = actions.onNewSymbolicLinkPrompt {
                Button(String(localized: "Enlace simbólico…", bundle: #bundle), menuIcon: "link") {
                    onNewSymbolicLinkPrompt()
                }
            }
            Divider()
            Button(String(localized: "Archivo de texto…", bundle: #bundle), menuIcon: "doc.text") {
                actions.onNewFilePrompt(String(localized: "Nuevo archivo.txt", bundle: #bundle))
            }
            Button(String(localized: "Documento Markdown…", bundle: #bundle), menuIcon: "doc.richtext") {
                actions.onNewFilePrompt("Nota.md")
            }
            Button(String(localized: "Script de Shell…", bundle: #bundle), menuIcon: "apple.terminal") {
                actions.onNewFilePrompt("script.sh")
            }
            Button(String(localized: "Archivo Swift…", bundle: #bundle), menuIcon: "swift") {
                actions.onNewFilePrompt("Archivo.swift")
            }
            Button(String(localized: "Documento JSON…", bundle: #bundle), menuIcon: "curlybraces") {
                actions.onNewFilePrompt("datos.json")
            }
            Button(String(localized: "Página HTML…", bundle: #bundle), menuIcon: "chevron.left.forwardslash.chevron.right") {
                actions.onNewFilePrompt("index.html")
            }
            templateMenuItems
        }
    }

    /// Custom `~/Templates` entries plus the "open that folder" affordance.
    @ViewBuilder
    private var templateMenuItems: some View {
        let templates = TemplateProvider().customTemplates()
        if !templates.isEmpty, let onTemplate = actions.onNewFileFromTemplatePrompt {
            Divider()
            ForEach(templates, id: \.self) { templateURL in
                Button(templateURL.lastPathComponent) {
                    onTemplate(templateURL)
                }
            }
        }
        Divider()
        Button(String(localized: "Abrir carpeta de plantillas…", bundle: #bundle), menuIcon: "folder") {
            TemplateProvider().revealOrCreateTemplatesDirectory()
        }
    }

    @ViewBuilder
    private func openWithMenu(for url: URL) -> some View {
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if !appURLs.isEmpty {
            Menu(String(localized: "Abrir con", bundle: #bundle), menuIcon: "arrow.up.forward.app") {
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
            Button(String(localized: "Vaciar la Papelera…", bundle: #bundle), menuIcon: "xmark.bin", role: .destructive) {
                actions.viewModel.emptyTrash()
            }
            .disabled(actions.viewModel.items.isEmpty)
            Divider()
        } else {
            Menu(String(localized: "Crear nuevo", bundle: #bundle), menuIcon: "plus") {
                Button(String(localized: "Carpeta…", bundle: #bundle), menuIcon: "folder.badge.plus") {
                    actions.onNewFolderPrompt()
                }
                if let onNewSymbolicLinkPrompt = actions.onNewSymbolicLinkPrompt {
                    Button(String(localized: "Enlace simbólico…", bundle: #bundle), menuIcon: "link") {
                        onNewSymbolicLinkPrompt()
                    }
                }
                Divider()
                Button(String(localized: "Archivo de texto…", bundle: #bundle), menuIcon: "doc.text") {
                    actions.onNewFilePrompt(String(localized: "Nuevo archivo.txt", bundle: #bundle))
                }
                Button(String(localized: "Documento Markdown…", bundle: #bundle), menuIcon: "doc.richtext") {
                    actions.onNewFilePrompt("Nota.md")
                }
                Button(String(localized: "Script de Shell…", bundle: #bundle), menuIcon: "apple.terminal") {
                    actions.onNewFilePrompt("script.sh")
                }
                Button(String(localized: "Archivo Swift…", bundle: #bundle), menuIcon: "swift") {
                    actions.onNewFilePrompt("Archivo.swift")
                }
                Button(String(localized: "Documento JSON…", bundle: #bundle), menuIcon: "curlybraces") {
                    actions.onNewFilePrompt("datos.json")
                }
                Button(String(localized: "Página HTML…", bundle: #bundle), menuIcon: "chevron.left.forwardslash.chevron.right") {
                    actions.onNewFilePrompt("index.html")
                }
                templateMenuItems
            }
        }

        if actions.viewModel.canPaste {
            Button(String(localized: "Pegar", bundle: #bundle), menuIcon: "doc.on.clipboard") {
                actions.viewModel.paste()
            }
        }

        Divider()

        Menu(String(localized: "Modo de vista", bundle: #bundle), menuIcon: "square.grid.2x2") {
            Picker(selection: Binding(
                get: { actions.viewModel.viewProperties.mode },
                set: { actions.viewModel.setViewMode($0) }
            )) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }

        Menu(String(localized: "Ordenar por", bundle: #bundle), menuIcon: "arrow.up.arrow.down") {
            let viewModel = actions.viewModel
            Picker(selection: Binding(
                get: { viewModel.viewProperties.sortField },
                set: { viewModel.setSort(field: $0, ascending: $0.defaultAscending) }
            )) {
                ForEach(SortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            Divider()
            Picker(selection: Binding(
                get: { viewModel.viewProperties.ascending },
                set: { viewModel.setSort(field: viewModel.viewProperties.sortField, ascending: $0) }
            )) {
                Text(String(localized: "Ascendente", bundle: #bundle)).tag(true)
                Text(String(localized: "Descendente", bundle: #bundle)).tag(false)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(String(localized: "Carpetas primero", bundle: #bundle), isOn: Binding(
                get: { viewModel.viewProperties.sortFoldersFirst },
                set: { _ in viewModel.toggleSortFoldersFirst() }
            ))
            Toggle(String(localized: "Archivos ocultos al final", bundle: #bundle), isOn: Binding(
                get: { viewModel.viewProperties.sortHiddenLast },
                set: { _ in viewModel.toggleSortHiddenLast() }
            ))
            Divider()
            Toggle(String(localized: "Mostrar en grupos", bundle: #bundle), isOn: Binding(
                get: { viewModel.viewProperties.showInGroups },
                set: { _ in viewModel.toggleShowInGroups() }
            ))
        }

        Menu(String(localized: "Agrupar por", bundle: #bundle), menuIcon: "rectangle.3.group") {
            GroupByPicker(selection: Binding(
                get: { actions.viewModel.groupByChoice },
                set: { actions.viewModel.groupByChoice = $0 }
            ))
        }

        if actions.viewModel.viewProperties.mode == .details {
            Menu(String(localized: "Columnas visibles", bundle: #bundle), menuIcon: "tablecells") {
                ForEach(DetailsColumn.allCases) { col in
                    Toggle(col.title, isOn: Binding(
                        get: { actions.viewModel.viewProperties.visibleDetailsColumns.contains(col) },
                        set: { _ in actions.viewModel.toggleDetailsColumn(col) }
                    ))
                }
            }
        }

        Toggle(String(localized: "Mostrar vistas previas", bundle: #bundle), isOn: Binding(
            get: { actions.viewModel.viewProperties.showPreviews },
            set: { _ in actions.viewModel.toggleShowPreviews() }
        ))

        Toggle(String(localized: "Mostrar archivos ocultos", bundle: #bundle), isOn: Binding(
            get: { actions.viewModel.effectiveShowsHiddenFiles },
            set: { _ in actions.viewModel.toggleShowsHiddenFiles() }
        ))

        if let onShowViewPropertiesDialog = actions.onShowViewPropertiesDialog {
            Button(String(localized: "Estilo de visualización de vista…", bundle: #bundle), menuIcon: "slider.horizontal.3") {
                onShowViewPropertiesDialog()
            }
        }

        Button(String(localized: "Restablecer valores de vista predeterminados", bundle: #bundle), menuIcon: "arrow.counterclockwise") {
            actions.viewModel.resetViewPropertiesToDefault()
        }

        Divider()

        Button(actions.viewModel.isSelectionModeActive ? String(localized: "Salir del modo de selección", bundle: #bundle) : String(localized: "Modo de selección", bundle: #bundle), menuIcon: "checkmark.circle") {
            actions.viewModel.isSelectionModeActive.toggle()
        }
        Button(String(localized: "Seleccionar todo", bundle: #bundle), menuIcon: "checklist") {
            actions.viewModel.selectAll()
        }
        if let onSelectByPatternPrompt = actions.onSelectByPatternPrompt {
            Button(String(localized: "Seleccionar ítems por patrón…", bundle: #bundle), menuIcon: "text.magnifyingglass") {
                onSelectByPatternPrompt()
            }
        }
        Button(String(localized: "Invertir selección", bundle: #bundle), menuIcon: "circle.lefthalf.filled") {
            actions.viewModel.invertSelection()
        }

        Divider()

        let placesProvider = PlacesProvider()
        if placesProvider.isBookmarked(actions.viewModel.currentURL) {
            Button(String(localized: "Quitar carpeta actual de Lugares", bundle: #bundle), menuIcon: "bookmark.slash") {
                placesProvider.removeBookmark(for: actions.viewModel.currentURL)
            }
        } else {
            Button(String(localized: "Añadir carpeta actual a Lugares", bundle: #bundle), menuIcon: "bookmark") {
                placesProvider.addBookmark(for: actions.viewModel.currentURL)
            }
        }

        Button(String(localized: "Copiar ubicación", bundle: #bundle), menuIcon: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(actions.viewModel.currentURL.path, forType: .string)
        }
        Button(String(localized: "Mostrar carpeta en Finder", bundle: #bundle), menuIcon: "macwindow") {
            NSWorkspace.shared.activateFileViewerSelecting([actions.viewModel.currentURL])
        }
        if let onOpenTerminal = actions.onOpenTerminal {
            Button(String(localized: "Abrir Terminal aquí", bundle: #bundle), menuIcon: "terminal") {
                onOpenTerminal(actions.viewModel.currentURL)
            }
        }
        if actions.viewModel.isGitRepository, let onShowGitRepoSheet = actions.onShowGitRepoSheet {
            Button(String(localized: "Control de versiones Git (\(actions.viewModel.gitBranchName ?? "repo"))…", bundle: #bundle), menuIcon: "arrow.triangle.branch") {
                onShowGitRepoSheet([])
            }
        }

        Divider()

        Button(String(localized: "Propiedades…", bundle: #bundle), menuIcon: "info.circle") {
            actions.onShowProperties(actions.viewModel.currentURL)
        }
    }

    /// Custom `~/Templates` entries plus the "open that folder" affordance.
    @ViewBuilder
    private var templateMenuItems: some View {
        let templates = TemplateProvider().customTemplates()
        if !templates.isEmpty, let onTemplate = actions.onNewFileFromTemplatePrompt {
            Divider()
            ForEach(templates, id: \.self) { templateURL in
                Button(templateURL.lastPathComponent) {
                    onTemplate(templateURL)
                }
            }
        }
        Divider()
        Button(String(localized: "Abrir carpeta de plantillas…", bundle: #bundle), menuIcon: "folder") {
            TemplateProvider().revealOrCreateTemplatesDirectory()
        }
    }
}
