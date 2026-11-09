import AppKit
import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel
    var otherPaneURL: URL? = nil
    var onFilesMoved: (() -> Void)?
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)? = nil

    @State private var pendingDelete: FileItem?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsRenamePrompt = false
    @State private var renameInput = ""
    @State private var showsBatchRenameSheet = false
    @State private var showsNewFolderPrompt = false
    @State private var showsMoveToNewFolderPrompt = false
    @State private var showsNewFilePrompt = false
    @State private var showsSelectByPatternPrompt = false
    @State private var patternInput = "*.*"
    @State private var newItemNameInput = ""
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

    var body: some View {
        let currentSettings = AppSettingsStore().settings()
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
                renameInput = item.name
                showsRenamePrompt = true
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
                    newItemNameInput = "Nueva carpeta"
                    showsNewFolderPrompt = true
                },
                onMoveToNewFolderPrompt: {
                    newItemNameInput = "Nueva carpeta"
                    showsMoveToNewFolderPrompt = true
                },
                onNewFilePrompt: { defaultName in
                    newItemNameInput = defaultName
                    showsNewFilePrompt = true
                },
                onNewSymbolicLinkPrompt: {
                    newItemNameInput = "Nuevo enlace"
                    symlinkTargetInput = viewModel.selectedItem?.url.path ?? ""
                    showsNewSymlinkPrompt = true
                },
                onRename: onRename,
                onBatchRename: onBatchRename,
                onDelete: onDelete,
                onDeleteSelection: onDeleteSelection,
                onDeletePermanently: { targets in
                    guard !targets.isEmpty else { return }
                    if AppSettingsStore().settings().confirmPermanentDelete {
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
                        "Carpeta no encontrada",
                        systemImage: "folder.badge.questionmark",
                        description: Text("No se encontró \(url.path)")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .other(let message):
                    ContentUnavailableView(
                        "Error al abrir la carpeta",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !viewModel.searchQuery.isEmpty {
                if viewModel.searchResults.isEmpty {
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
                ContentUnavailableView.search(text: viewModel.filterText.isEmpty ? "filtros activos" : viewModel.filterText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.viewProperties.mode {
                case .icons:
                    IconGridView(
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        showPreviews: viewModel.viewProperties.showPreviews,
                        isSelectionModeActive: viewModel.isSelectionModeActive,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selectedIDs: viewModel.selectedIDs,
                        currentURL: viewModel.currentURL,
                        onSelect: { item, modifier in
                            switch modifier {
                            case .none: viewModel.select(item)
                            case .toggle: viewModel.toggleSelection(item)
                            case .range: viewModel.extendSelection(to: item)
                            }
                        },
                        onClearSelection: { viewModel.setSelection([]) },
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        gitStatuses: viewModel.gitStatuses,
                        contextMenuActions: menuActions,
                        onColumnCountChange: { count in
                            viewModel.gridColumnsCount = count
                        }
                    )
                    .transition(.opacity)
                case .compact:
                    CompactGridView(
                        items: viewModel.filteredItems,
                        groups: viewModel.groupedFilteredItems,
                        showInGroups: viewModel.viewProperties.showInGroups,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selectedIDs: viewModel.selectedIDs,
                        currentURL: viewModel.currentURL,
                        isSelectionModeActive: viewModel.isSelectionModeActive,
                        onSelect: { item, modifier in
                            switch modifier {
                            case .none: viewModel.select(item)
                            case .toggle: viewModel.toggleSelection(item)
                            case .range: viewModel.extendSelection(to: item)
                            }
                        },
                        onClearSelection: { viewModel.setSelection([]) },
                        onOpen: onOpen,
                        onRename: onRename,
                        onBatchRename: onBatchRename,
                        onDelete: onDelete,
                        onDeleteSelection: { showsDeleteSelectionConfirmation = true },
                        onMoveDropped: { urls, directory in
                            viewModel.moveDroppedItems(urls, into: directory)
                            onFilesMoved?()
                        },
                        gitStatuses: viewModel.gitStatuses,
                        contextMenuActions: menuActions,
                        onColumnCountChange: { count in
                            viewModel.gridColumnsCount = count
                        }
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

            if viewModel.isSelectionModeActive {
                Divider()
                SelectionModeBottomBarView(
                    viewModel: viewModel,
                    otherPaneURL: otherPaneURL,
                    onRename: {
                        if viewModel.selectedItems.count > 1 {
                            showsBatchRenameSheet = true
                        } else if let item = viewModel.selectedItem {
                            renameInput = item.name
                            showsRenamePrompt = true
                        }
                    },
                    onMoveToNewFolder: {
                        newItemNameInput = "Nueva carpeta"
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
                globalShowsHiddenFiles: AppSettingsStore().settings().showsHiddenFiles
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
        .alert("Nueva carpeta", isPresented: $showsNewFolderPrompt) {
            TextField("Nombre", text: $newItemNameInput)
            Button("Crear") { viewModel.createFolder(named: newItemNameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Mover selección a carpeta nueva", isPresented: $showsMoveToNewFolderPrompt) {
            TextField("Nombre de la carpeta", text: $newItemNameInput)
            Button("Crear y mover") { viewModel.moveSelectedToNewFolder(named: newItemNameInput) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se creará la carpeta y se moverán los \(viewModel.selectedIDs.count) ítems seleccionados dentro de ella.")
        }
        .alert("Seleccionar ítems por patrón", isPresented: $showsSelectByPatternPrompt) {
            TextField("Patrón (ej. *.swift, *.png, foto_*)", text: $patternInput)
            Button("Seleccionar") { viewModel.selectItems(matchingPattern: patternInput, additive: false) }
            Button("Añadir a selección") { viewModel.selectItems(matchingPattern: patternInput, additive: true) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Usa comodines * y ? o texto parcial para seleccionar archivos en la carpeta actual.")
        }
        .alert("Nuevo archivo", isPresented: $showsNewFilePrompt) {
            TextField("Nombre", text: $newItemNameInput)
            Button("Crear") { viewModel.createFile(named: newItemNameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Nuevo enlace simbólico", isPresented: $showsNewSymlinkPrompt) {
            TextField("Nombre del enlace", text: $newItemNameInput)
            TextField("Ruta de destino", text: $symlinkTargetInput)
            Button("Crear enlace") {
                viewModel.createSymbolicLink(named: newItemNameInput, pointingTo: symlinkTargetInput)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Introduce el nombre del enlace simbólico y la ruta hacia el archivo o carpeta de destino.")
        }
        .alert(
            pendingPermanentDeleteItems.count == 1
                ? "¿Eliminar permanentemente «\(pendingPermanentDeleteItems[0].name)»?"
                : "¿Eliminar permanentemente \(pendingPermanentDeleteItems.count) ítems?",
            isPresented: $showsPermanentDeleteConfirmation
        ) {
            Button("Eliminar permanentemente", role: .destructive) {
                viewModel.deletePermanently(pendingPermanentDeleteItems)
                pendingPermanentDeleteItems = []
            }
            Button("Cancelar", role: .cancel) {
                pendingPermanentDeleteItems = []
            }
        } message: {
            Text("Esta acción borrará los elementos del disco sin pasar por la Papelera y no se puede deshacer.")
        }
        .alert("Renombrar", isPresented: $showsRenamePrompt) {
            TextField("Nombre", text: $renameInput)
            Button("Renombrar") { viewModel.renameSelected(to: renameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert(
            "¿Eliminar este ítem?",
            isPresented: $showsDeleteConfirmation,
            presenting: pendingDelete
        ) { item in
            Button("Eliminar", role: .destructive) { viewModel.delete(item) }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text("Se moverá «\(item.name)» a la Papelera.")
        }
        .alert(
            "¿Eliminar \(viewModel.selectedIDs.count) ítems?",
            isPresented: $showsDeleteSelectionConfirmation
        ) {
            Button("Eliminar", role: .destructive) { viewModel.deleteSelectedItems() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se moverán a la Papelera.")
        }
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { viewModel.operationError != nil },
                set: { if !$0 { viewModel.clearOperationError() } }
            )
        ) {
            Button("OK") { viewModel.clearOperationError() }
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

                Text("Tipo:")
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
                    ForEach(SearchDateFilter.allCases) { dateFilter in
                        Button {
                            viewModel.searchDateFilter = dateFilter
                        } label: {
                            HStack {
                                Text(dateFilter.title)
                                if viewModel.searchDateFilter == dateFilter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchDateFilter == .any ? "Fecha" : viewModel.searchDateFilter.title)
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
                    ForEach(SearchSizeFilter.allCases) { sizeFilter in
                        Button {
                            viewModel.searchSizeFilter = sizeFilter
                        } label: {
                            HStack {
                                Text(sizeFilter.title)
                                if viewModel.searchSizeFilter == sizeFilter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchSizeFilter == .any ? "Tamaño" : viewModel.searchSizeFilter.title)
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
                    ForEach(FinderColorTag.allCases) { tag in
                        Button {
                            viewModel.searchColorTagFilter = tag
                        } label: {
                            HStack {
                                Text(tag.title)
                                if viewModel.searchColorTagFilter == tag {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .medium))
                        Text(viewModel.searchColorTagFilter == .none ? "Etiqueta" : viewModel.searchColorTagFilter.title)
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
                            Text("Guardar")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Guardar esta búsqueda en el panel Lugares")
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
                    .help("Restablecer todos los filtros y búsqueda")
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
            Text("Carpeta de solo lectura")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text("— No tienes permisos de escritura en «\(viewModel.currentURL.lastPathComponent.isEmpty ? "/" : viewModel.currentURL.lastPathComponent)».")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Propiedades…") {
                propertiesTargetURL = viewModel.currentURL
            }
            .controlSize(.small)
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([viewModel.currentURL])
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var operationErrorMessage: String {
        switch viewModel.operationError {
        case .nameAlreadyExists:
            return "Ya existe un ítem con ese nombre."
        case .invalidName:
            return "El nombre no es válido."
        case .other(let message):
            return message
        case nil:
            return ""
        }
    }
}
