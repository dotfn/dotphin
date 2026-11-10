import AppKit
import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel
    var otherPaneURL: URL? = nil
    var onFilesMoved: (() -> Void)?
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)? = nil

    @Environment(\.undoManager) private var undoManager
    @Environment(\.fileViewInteraction) private var paneInteraction
    @State private var pendingDelete: FileItem?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsBatchRenameSheet = false
    @State private var showsNewFolderPrompt = false
    @State private var showsMoveToNewFolderPrompt = false
    @State private var showsNewFilePrompt = false
    @State private var showsSelectByPatternPrompt = false
    @State private var patternInput = "*.*"
    @State private var newItemNameInput = ""
    @State private var pendingTemplateSourceURL: URL?
    @State private var propertiesTargetURL: URL?
    @State private var comparePair: (left: URL, right: URL)?
    @State private var showsViewPropertiesDialog = false
    @State private var showsGitRepoSheet = false
    @State private var gitRepoTargetItems: [FileItem] = []
    @State private var showsNewSymlinkPrompt = false
    @State private var symlinkTargetInput = ""
    @State private var pendingPermanentDeleteItems: [FileItem] = []
    @State private var showsPermanentDeleteConfirmation = false
    @State private var inspectedArchiveItem: FileItem? = nil

    private var selection: Binding<Set<FileItem.ID>> {
        Binding(
            get: { viewModel.selectedIDs },
            set: { viewModel.setSelection($0) }
        )
    }

    /// Teclado y edición en línea de las vistas de archivos de AppKit. Parte de
    /// lo que publica el panel (`onActivate`) y le suma lo propio de esta vista.
    private var fileViewInteraction: FileViewInteraction {
        var interaction = paneInteraction
        interaction.renamingItemID = viewModel.renamingItemID
        interaction.onQuickLook = {
            QuickLookPreviewController.shared.toggle(for: viewModel)
        }
        interaction.onRequestRename = {
            if viewModel.selectedItems.count > 1 {
                showsBatchRenameSheet = true
            } else if let item = viewModel.selectedItem {
                viewModel.renamingItemID = item.id
            }
        }
        interaction.onTypeAhead = { characters in
            _ = viewModel.selectItemByTypeAhead(characters)
        }
        interaction.onCopyDropped = { urls, directory in
            viewModel.copyDroppedItems(urls, into: directory)
        }
        interaction.onEndRename = { id, newName in
            viewModel.endRenaming(id, newName: newName)
        }
        return interaction
    }

    var body: some View {
        let currentSettings = AppSettingsModel.shared.settings
        VStack(spacing: 0) {
            if !viewModel.isCurrentDirectoryWritable && !viewModel.isBrowsingTrash && viewModel.error == nil {
                readOnlyDirectoryBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            if viewModel.isSelectionModeActive {
                SelectionModeTopBarView(
                    onSelectByPattern: {
                        showsSelectByPatternPrompt = true
                    },
                    onExitSelectionMode: {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.isSelectionModeActive = false
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            if viewModel.isFilterBarVisible {
                FilterBarView(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            if !viewModel.searchQuery.isEmpty || !viewModel.filterText.isEmpty || viewModel.hasActiveFacets {
                searchTypeFilterBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            let onDelete: (FileItem) -> Void = { item in
                if currentSettings.confirmMoveToTrash {
                    pendingDelete = item
                    showsDeleteConfirmation = true
                } else {
                    viewModel.delete(item)
                }
            }
            let onDeleteSelection: () -> Void = {
                if currentSettings.confirmMoveToTrash {
                    showsDeleteSelectionConfirmation = true
                } else {
                    viewModel.deleteSelectedItems()
                }
            }
            let onRename: (FileItem) -> Void = { item in
                viewModel.select(item)
                viewModel.renamingItemID = item.id
            }
            let onBatchRename: () -> Void = {
                showsBatchRenameSheet = true
            }
            let onOpen: (FileItem) -> Void = { item in
                if item.isDirectory {
                    withAnimation(.snappy(duration: 0.18)) {
                        viewModel.navigate(to: item.url)
                    }
                } else if ArchiveService.isArchive(item.url) && currentSettings.browseThroughArchives {
                    inspectedArchiveItem = item
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
            let menuActions = BrowserContextMenuActions(
                viewModel: viewModel,
                otherPaneURL: otherPaneURL,
                onCrossPaneTransferCompleted: onFilesMoved,
                onOpen: onOpen,
                onOpenInNewTab: onOpenInNewTab,
                onOpenInSplitView: onOpenInSplitView,
                onCompareItems: { left, right in
                    comparePair = (left, right)
                },
                onNewFolderPrompt: {
                    newItemNameInput = String(localized: "Nueva carpeta", bundle: #bundle)
                    showsNewFolderPrompt = true
                },
                onMoveToNewFolderPrompt: {
                    newItemNameInput = String(localized: "Nueva carpeta", bundle: #bundle)
                    showsMoveToNewFolderPrompt = true
                },
                onNewFilePrompt: promptNewFile(named:),
                onNewFileFromTemplatePrompt: promptNewFile(fromTemplate:),
                onMountDiskImage: mountDiskImage(_:),
                onNewSymbolicLinkPrompt: {
                    newItemNameInput = String(localized: "Nuevo enlace", bundle: #bundle)
                    symlinkTargetInput = viewModel.selectedItem?.url.path ?? ""
                    showsNewSymlinkPrompt = true
                },
                onRename: onRename,
                onBatchRename: onBatchRename,
                onDelete: onDelete,
                onDeleteSelection: onDeleteSelection,
                onDeletePermanently: { targets in
                    guard !targets.isEmpty else { return }
                    if AppSettingsModel.shared.settings.confirmPermanentDelete {
                        pendingPermanentDeleteItems = targets
                        showsPermanentDeleteConfirmation = true
                    } else {
                        viewModel.deletePermanently(targets)
                    }
                },
                onShowProperties: { url in propertiesTargetURL = url },
                onShowViewPropertiesDialog: { showsViewPropertiesDialog = true },
                onSelectByPatternPrompt: { showsSelectByPatternPrompt = true },
                onShowGitRepoSheet: { items in
                    gitRepoTargetItems = items
                    showsGitRepoSheet = true
                },
                onInspectArchive: { item in
                    inspectedArchiveItem = item
                },
                onOpenTerminal: onOpenTerminal
            )

            if let error = viewModel.error {
                switch error {
                case .permissionDenied(let url):
                    PermissionDeniedView(url: url)
                case .notFound(let url):
                    ContentUnavailableView(
                        String(localized: "Carpeta no encontrada", bundle: #bundle),
                        systemImage: "folder.badge.questionmark",
                        description: Text(String(localized: "No se encontró \(url.path)", bundle: #bundle))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .other(let message):
                    ContentUnavailableView(
                        String(localized: "Error al abrir la carpeta", bundle: #bundle),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !viewModel.searchQuery.isEmpty {
                if viewModel.searchResults.isEmpty && viewModel.isSearching {
                    ProgressView(String(localized: "Buscando «\(viewModel.searchQuery)»…", bundle: #bundle))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchQuery)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileListView(
                        items: viewModel.searchResults,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selection: selection,
                        gitStatuses: [:],
                        currentURL: nil,
                        onOpen: { item in
                            if item.isDirectory {
                                viewModel.navigate(to: item.url)
                            } else {
                                viewModel.navigate(to: item.url.deletingLastPathComponent())
                            }
                        },
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        contextMenuActions: menuActions
                    )
                }
            } else if viewModel.filteredItems.isEmpty && (!viewModel.filterText.isEmpty || viewModel.hasActiveFacets) {
                ContentUnavailableView.search(text: viewModel.filterText.isEmpty ? String(localized: "filtros activos", bundle: #bundle) : viewModel.filterText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.viewProperties.mode {
                case .icons:
                    FileGridView(
                        style: .icons,
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        showPreviews: viewModel.viewProperties.showPreviews,
                        isSelectionModeActive: viewModel.isSelectionModeActive,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selection: selection,
                        gitStatuses: viewModel.gitStatuses,
                        currentURL: viewModel.currentURL,
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        contextMenuActions: menuActions
                    )
                    .transition(.opacity)
                case .compact:
                    FileGridView(
                        style: .compact,
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        isSelectionModeActive: viewModel.isSelectionModeActive,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selection: selection,
                        gitStatuses: viewModel.gitStatuses,
                        currentURL: viewModel.currentURL,
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        contextMenuActions: menuActions
                    )
                    .transition(.opacity)
                case .list:
                    FileListView(
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selection: selection,
                        gitStatuses: viewModel.gitStatuses,
                        currentURL: viewModel.currentURL,
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        contextMenuActions: menuActions
                    )
                    .transition(.opacity)
                case .details:
                    DetailsListView(
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        visibleColumns: viewModel.viewProperties.visibleDetailsColumns,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selection: selection,
                        gitStatuses: viewModel.gitStatuses,
                        currentURL: viewModel.currentURL,
                        sortField: viewModel.viewProperties.sortField,
                        ascending: viewModel.viewProperties.ascending,
                        onChangeSort: { field, asc in viewModel.setSort(field: field, ascending: asc) },
                        onToggleColumn: { viewModel.toggleDetailsColumn($0) },
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        contextMenuActions: menuActions
                    )
                    .transition(.opacity)
                }
            }

            if let transfer = viewModel.activeTransfer, transfer.isLongRunning {
                Divider()
                FileTransferBarView(transfer: transfer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.isSelectionModeActive {
                Divider()
                SelectionModeBottomBarView(
                    viewModel: viewModel,
                    otherPaneURL: otherPaneURL,
                    onRename: {
                        if viewModel.selectedItems.count > 1 {
                            showsBatchRenameSheet = true
                        } else if let item = viewModel.selectedItem {
                            viewModel.renamingItemID = item.id
                        }
                    },
                    onMoveToNewFolder: {
                        newItemNameInput = String(localized: "Nueva carpeta", bundle: #bundle)
                        showsMoveToNewFolderPrompt = true
                    },
                    onDelete: {
                        if viewModel.selectedItems.count > 1 {
                            onDeleteSelection()
                        } else if let item = viewModel.selectedItem {
                            onDelete(item)
                        }
                    },
                    onSelectByPattern: {
                        showsSelectByPatternPrompt = true
                    },
                    onCompareSelected: {
                        let sel = viewModel.selectedItems
                        if sel.count == 2 {
                            comparePair = (sel[0].url, sel[1].url)
                        }
                    },
                    onCrossPaneTransferCompleted: onFilesMoved
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if currentSettings.showPasteBarAfterCopying,
                      viewModel.isCurrentDirectoryWritable,
                      !viewModel.isBrowsingTrash,
                      let clip = viewModel.clipboardSummary {
                Divider()
                PasteAfterCopyingBarView(
                    itemCount: clip.count,
                    isCut: clip.isCut,
                    firstFileName: clip.firstFileName,
                    destinationFolderName: viewModel.currentURL.lastPathComponent.isEmpty ? "/" : viewModel.currentURL.lastPathComponent,
                    onPasteHere: {
                        viewModel.paste()
                    },
                    onCancelClipboard: {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.clearClipboard()
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: viewModel.viewProperties.mode)
        .animation(.snappy(duration: 0.18), value: viewModel.isSelectionModeActive)
        .animation(.snappy(duration: 0.18), value: viewModel.isFilterBarVisible)
        .animation(.snappy(duration: 0.18), value: viewModel.hasActiveFacets)
        .animation(.snappy(duration: 0.16), value: viewModel.typeAheadBuffer.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.fileViewInteraction, fileViewInteraction)
        .onChange(of: ObjectIdentifier(viewModel), initial: true) { _, _ in
            viewModel.undoManager = undoManager
            // Esta vista puede mostrar el diálogo de nombres repetidos.
            viewModel.presentsConflictPrompts = true
            viewModel.watchesCurrentDirectory = true
        }
        .modifier(FileConflictDialogModifier(transfer: viewModel.activeTransfer))
        .onChange(of: undoManager) { _, newValue in
            viewModel.undoManager = newValue
        }
        .onChange(of: viewModel.selectedIDs) { _, _ in
            QuickLookPreviewController.shared.updateIfVisible(for: viewModel)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.typeAheadBuffer.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.typeAheadBuffer)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .padding(12)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .sheet(isPresented: $showsBatchRenameSheet) {
            BatchRenameSheetView(items: viewModel.selectedItems) { pattern, startIndex in
                viewModel.batchRenameSelected(pattern: pattern, startIndex: startIndex)
            }
        }
        .sheet(isPresented: $showsViewPropertiesDialog) {
            ViewPropertiesDialogSheetView(
                folderURL: viewModel.currentURL,
                draft: viewModel.viewProperties,
                globalShowsHiddenFiles: AppSettingsModel.shared.settings.showsHiddenFiles
            ) { updated, scope, useAsDefault in
                viewModel.applyViewProperties(updated, scope: scope, useAsDefault: useAsDefault)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { propertiesTargetURL != nil },
                set: { if !$0 { propertiesTargetURL = nil } }
            )
        ) {
            if let url = propertiesTargetURL {
                FilePropertiesSheetView(url: url) { resolvedTarget in
                    let parentDir = resolvedTarget.deletingLastPathComponent()
                    viewModel.navigate(to: parentDir)
                    if let targetItem = viewModel.items.first(where: { $0.url.standardizedFileURL == resolvedTarget.standardizedFileURL }) {
                        viewModel.select(targetItem)
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { comparePair != nil },
                set: { if !$0 { comparePair = nil } }
            )
        ) {
            if let pair = comparePair {
                FileCompareSheetView(leftURL: pair.left, rightURL: pair.right)
            }
        }
        .sheet(isPresented: $showsGitRepoSheet) {
            GitRepoSheetView(viewModel: viewModel, targetItems: gitRepoTargetItems)
        }
        .sheet(item: $inspectedArchiveItem) { archiveItem in
            ArchiveContentsSheetView(
                archiveItem: archiveItem,
                onExtractAndOpen: {
                    viewModel.extractArchive(archiveItem)
                    if let extracted = viewModel.selectedItem, extracted.isDirectory {
                        viewModel.navigate(to: extracted.url)
                    }
                }
            )
        }
        .alert(String(localized: "Nueva carpeta", bundle: #bundle), isPresented: $showsNewFolderPrompt) {
            TextField(String(localized: "Nombre", bundle: #bundle), text: $newItemNameInput)
            Button(String(localized: "Crear", bundle: #bundle)) { viewModel.createFolder(named: newItemNameInput) }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        }
        .alert(String(localized: "Mover selección a carpeta nueva", bundle: #bundle), isPresented: $showsMoveToNewFolderPrompt) {
            TextField(String(localized: "Nombre de la carpeta", bundle: #bundle), text: $newItemNameInput)
            Button(String(localized: "Crear y mover", bundle: #bundle)) { viewModel.moveSelectedToNewFolder(named: newItemNameInput) }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: {
            Text(String(localized: "Se creará la carpeta y se moverán los \(viewModel.selectedIDs.count) ítems seleccionados dentro de ella.", bundle: #bundle))
        }
        .alert(String(localized: "Seleccionar ítems por patrón", bundle: #bundle), isPresented: $showsSelectByPatternPrompt) {
            TextField(String(localized: "Patrón (ej. *.swift, *.png, foto_*)", bundle: #bundle), text: $patternInput)
            Button(String(localized: "Seleccionar", bundle: #bundle)) { viewModel.selectItems(matchingPattern: patternInput, additive: false) }
            Button(String(localized: "Añadir a selección", bundle: #bundle)) { viewModel.selectItems(matchingPattern: patternInput, additive: true) }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: {
            Text(String(localized: "Usa comodines * y ? o texto parcial para seleccionar archivos en la carpeta actual.", bundle: #bundle))
        }
        .alert(String(localized: "Nuevo archivo", bundle: #bundle), isPresented: $showsNewFilePrompt) {
            TextField(String(localized: "Nombre", bundle: #bundle), text: $newItemNameInput)
            Button(String(localized: "Crear", bundle: #bundle), action: createFileFromPrompt)
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) { pendingTemplateSourceURL = nil }
        }
        .alert(String(localized: "Nuevo enlace simbólico", bundle: #bundle), isPresented: $showsNewSymlinkPrompt) {
            TextField(String(localized: "Nombre del enlace", bundle: #bundle), text: $newItemNameInput)
            TextField(String(localized: "Ruta de destino", bundle: #bundle), text: $symlinkTargetInput)
            Button(String(localized: "Crear enlace", bundle: #bundle)) {
                viewModel.createSymbolicLink(named: newItemNameInput, pointingTo: symlinkTargetInput)
            }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: {
            Text(String(localized: "Introduce el nombre del enlace simbólico y la ruta hacia el archivo o carpeta de destino.", bundle: #bundle))
        }
        .alert(
            pendingPermanentDeleteItems.count == 1
                ? String(localized: "¿Eliminar permanentemente «\(pendingPermanentDeleteItems[0].name)»?", bundle: #bundle)
                : String(localized: "¿Eliminar permanentemente \(pendingPermanentDeleteItems.count) ítems?", bundle: #bundle),
            isPresented: $showsPermanentDeleteConfirmation
        ) {
            Button(String(localized: "Eliminar permanentemente", bundle: #bundle), role: .destructive) {
                viewModel.deletePermanently(pendingPermanentDeleteItems)
                pendingPermanentDeleteItems = []
            }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {
                pendingPermanentDeleteItems = []
            }
        } message: {
            Text(String(localized: "Esta acción borrará los elementos del disco sin pasar por la Papelera y no se puede deshacer.", bundle: #bundle))
        }
        .alert(
            String(localized: "¿Eliminar este ítem?", bundle: #bundle),
            isPresented: $showsDeleteConfirmation,
            presenting: pendingDelete
        ) { item in
            Button(String(localized: "Eliminar", bundle: #bundle), role: .destructive) { viewModel.delete(item) }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: { item in
            Text(String(localized: "Se moverá «\(item.name)» a la Papelera.", bundle: #bundle))
        }
        .alert(
            String(localized: "¿Eliminar \(viewModel.selectedIDs.count) ítems?", bundle: #bundle),
            isPresented: $showsDeleteSelectionConfirmation
        ) {
            Button(String(localized: "Eliminar", bundle: #bundle), role: .destructive) { viewModel.deleteSelectedItems() }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: {
            Text(String(localized: "Se moverán a la Papelera.", bundle: #bundle))
        }
        .alert(
            String(localized: "No se pudo completar la operación", bundle: #bundle),
            isPresented: Binding(
                get: { viewModel.operationError != nil },
                set: { if !$0 { viewModel.clearOperationError() } }
            )
        ) {
            Button(String(localized: "OK", bundle: #bundle)) { viewModel.clearOperationError() }
        } message: {
            Text(operationErrorMessage)
        }
    }

    private var searchTypeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !viewModel.searchQuery.isEmpty {
                    // Dolphin Search Bar (`src/search/bar.cpp`): Location Scope + Filename/Content mode
                    ForEach(SearchLocationScope.allCases) { scope in
                        let isSelected = viewModel.searchLocationScope == scope
                        facetButton(
                            title: scope.title,
                            systemImage: scope.systemImage,
                            isSelected: isSelected
                        ) {
                            viewModel.searchLocationScope = scope
                        }
                    }

                    Divider()
                        .frame(height: 14)

                    ForEach(SearchMatchMode.allCases) { mode in
                        let isSelected = viewModel.searchMatchMode == mode
                        facetButton(
                            title: mode.title,
                            systemImage: mode.systemImage,
                            isSelected: isSelected
                        ) {
                            viewModel.searchMatchMode = mode
                        }
                    }

                    Divider()
                        .frame(height: 14)
                }

                Text(String(localized: "Tipo:", bundle: #bundle))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(SearchTypeFilter.allCases) { filter in
                    let isSelected = viewModel.searchTypeFilter == filter
                    facetButton(
                        title: filter.title,
                        systemImage: filter.systemImage,
                        isSelected: isSelected
                    ) {
                        viewModel.searchTypeFilter = filter
                    }
                }

                Divider()
                    .frame(height: 14)

                // Date filter chip (`modifiedSinceDate` in Dolphin)
                Menu {
                    Picker(selection: Bindable(viewModel).searchDateFilter) {
                        ForEach(SearchDateFilter.allCases) { dateFilter in
                            Text(dateFilter.title).tag(dateFilter)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchDateFilter == .any ? String(localized: "Fecha", bundle: #bundle) : viewModel.searchDateFilter.title)
                            .font(.system(size: 11, weight: viewModel.searchDateFilter != .any ? .semibold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(viewModel.searchDateFilter != .any ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(viewModel.searchDateFilter != .any ? Color.accentColor : Color.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Size filter chip
                Menu {
                    Picker(selection: Bindable(viewModel).searchSizeFilter) {
                        ForEach(SearchSizeFilter.allCases) { sizeFilter in
                            Text(sizeFilter.title).tag(sizeFilter)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchSizeFilter == .any ? String(localized: "Tamaño", bundle: #bundle) : viewModel.searchSizeFilter.title)
                            .font(.system(size: 11, weight: viewModel.searchSizeFilter != .any ? .semibold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(viewModel.searchSizeFilter != .any ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(viewModel.searchSizeFilter != .any ? Color.accentColor : Color.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Color tag filter chip (`TagsSelector` in `src/search/selectors/tagsselector.cpp`)
                Menu {
                    Picker(selection: Bindable(viewModel).searchColorTagFilter) {
                        ForEach(FinderColorTag.allCases) { tag in
                            Text(tag.title).tag(tag)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchColorTagFilter == .none ? String(localized: "Etiqueta", bundle: #bundle) : viewModel.searchColorTagFilter.title)
                            .font(.system(size: 11, weight: viewModel.searchColorTagFilter != .none ? .semibold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(viewModel.searchColorTagFilter != .none ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(viewModel.searchColorTagFilter != .none ? Color.accentColor : Color.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if viewModel.hasActiveFacets || !viewModel.searchQuery.isEmpty {
                    Button {
                        _ = viewModel.saveCurrentSearch()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bookmark.badge.plus")
                                .font(.system(size: 10, weight: .medium))
                            Text(String(localized: "Guardar", bundle: #bundle))
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Guardar esta búsqueda en el panel Lugares", bundle: #bundle))
                }

                if viewModel.hasActiveFacets || !viewModel.filterText.isEmpty || !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.resetSearchAndFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Restablecer todos los filtros y búsqueda", bundle: #bundle))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    private func facetButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var readOnlyDirectoryBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(String(localized: "Carpeta de solo lectura", bundle: #bundle))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text(String(localized: "— No tienes permisos de escritura en «\(viewModel.currentURL.lastPathComponent.isEmpty ? "/" : viewModel.currentURL.lastPathComponent)».", bundle: #bundle))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(String(localized: "Propiedades…", bundle: #bundle)) {
                propertiesTargetURL = viewModel.currentURL
            }
            .controlSize(.small)
            Button(String(localized: "Mostrar en Finder", bundle: #bundle)) {
                NSWorkspace.shared.activateFileViewerSelecting([viewModel.currentURL])
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func promptNewFile(named defaultName: String) {
        newItemNameInput = defaultName
        pendingTemplateSourceURL = nil
        showsNewFilePrompt = true
    }

    private func promptNewFile(fromTemplate templateURL: URL) {
        newItemNameInput = templateURL.lastPathComponent
        pendingTemplateSourceURL = templateURL
        showsNewFilePrompt = true
    }

    private func mountDiskImage(_ item: FileItem) {
        Task { await viewModel.mountDiskImage(item) }
    }

    private func createFileFromPrompt() {
        guard let templateURL = pendingTemplateSourceURL else {
            viewModel.createFile(named: newItemNameInput)
            return
        }
        pendingTemplateSourceURL = nil
        guard let contents = try? Data(contentsOf: templateURL) else {
            viewModel.reportOperationError(String(localized: "No se pudo leer la plantilla «\(templateURL.lastPathComponent)».", bundle: #bundle))
            return
        }
        viewModel.createFile(named: newItemNameInput, contents: contents)
    }

    private var operationErrorMessage: String {
        viewModel.operationError?.message ?? ""
    }
}
