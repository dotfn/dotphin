import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable private var settingsModel = AppSettingsModel.shared
    @State private var tabsViewModel = TabsViewModel(
        startingAt: AppSettingsStore().settings().startupURL,
        startInSplitView: AppSettingsStore().settings().startInSplitView,
        rememberOpenedTabs: AppSettingsStore().settings().rememberOpenedTabs,
        restoresSession: false
    )
    /// Identifica la sesión de pestañas de esta ventana; si el sistema
    /// restaura la ventana, vuelve con el mismo valor.
    @SceneStorage("tabSessionID") private var tabSessionID: String?
    @State private var didBeginTabSession = false
    @State private var places = PlacesProvider().allPlaces()
    @State private var savedSearches = PlacesProvider().savedSearches()
    @State private var showsInfoPanel = false
    @State private var showsEmbeddedTerminal = false
    nonisolated static let minimumWidth: CGFloat = 840
    nonisolated static let minimumWidthWithInfoPanel: CGFloat = 1000
    @State private var embeddedTerminalSession = EmbeddedTerminalSession()
    @State private var showsTabOverview = false
    @State private var pendingDelete: FileItem?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsPermanentDeleteSelectionConfirmation = false
    @State private var showsBatchRenameSheet = false
    @State private var showsNewFolderPrompt = false
    @State private var showsMoveToNewFolderPrompt = false
    @State private var showsSelectByPatternPrompt = false
    @State private var patternInput = "*.*"
    @State private var showsEmptyTrashConfirmation = false
    @State private var showsViewPropertiesDialog = false
    @State private var showsDiskUsageAnalyzer = false
    @State private var showsBookmarksEditorSheet = false
    @State private var nameInput = ""
    @State private var terminalError: String?
    @State private var propertiesTargetURL: URL?
    @State private var comparePair: (left: URL, right: URL)?
    @State private var commands = WindowCommands()
    @State private var locationEditRequest = 0
    @State private var isSearchPresented = false

    private var focusedViewModel: BrowserViewModel? {
        tabsViewModel.selectedTab?.focused
    }

    private var windowTitle: String {
        guard let url = focusedViewModel?.currentURL else { return "Dotphin" }
        if settingsModel.settings.showFullPathInTitlebar {
            return url.path
        }
        let name = url.lastPathComponent
        return (name.isEmpty || name == "/") ? "/" : name
    }

    var body: some View {
        let _ = connectCommands()
        NavigationSplitView {
            PlacesSidebarView(
                places: places,
                savedSearches: savedSearches,
                currentURL: focusedViewModel?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser,
                onSelect: { place in
                    focusedViewModel?.navigate(to: place.url)
                },
                onSelectSavedSearch: { saved in
                    focusedViewModel?.applySavedSearch(saved)
                },
                onOpenInNewTab: { url in
                    tabsViewModel.addTab(
                        startingAt: url,
                        afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                        splitView: settingsModel.settings.startInSplitView
                    )
                },
                onOpenInSplitView: { url in
                    if let tab = tabsViewModel.selectedTab {
                        tabsViewModel.openInSplitView(url, for: tab.id)
                    }
                },
                onSelectFolder: { url in
                    focusedViewModel?.navigate(to: url)
                }
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 250)
        } detail: {
            detailColumn
        }
        // Los mínimos de los paneles dentro de los divisores no llegan al mínimo de
        // la ventana: con el panel de información abierto, en menos de ~1000 pt el
        // contenido no entraba y se cortaba en los dos bordes.
        .frame(minWidth: showsInfoPanel ? Self.minimumWidthWithInfoPanel : Self.minimumWidth, minHeight: 540)
        .focusedSceneValue(\.browserViewModel, focusedViewModel)
        .focusedSceneValue(\.windowCommands, commands)
        .environment(\.locationEditRequest, locationEditRequest)
        .background(WindowCommandsRegistrar(commands: commands))
        .onReceive(NotificationCenter.default.publisher(for: .placesBookmarksDidChange)) { _ in
            places = PlacesProvider().allPlaces()
            savedSearches = PlacesProvider().savedSearches()
        }
        // Discos conectados, expulsados o renombrados: el panel Lugares se
        // actualiza solo (antes era una foto del momento del arranque).
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            places = PlacesProvider().allPlaces()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            places = PlacesProvider().allPlaces()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            places = PlacesProvider().allPlaces()
            leaveUnmountedVolumes()
        }
        .onAppear {
            guard !didBeginTabSession else { return }
            didBeginTabSession = true
            let restoredID = tabSessionID
            let id = restoredID ?? tabsViewModel.sessionID
            tabSessionID = id
            // Sin sesión propia, solo la primera ventana retoma la última usada.
            tabsViewModel.beginSession(
                id: id,
                fallingBackToLastSession: TabSessionStore.claimLaunchSession()
            )
        }
        // Cerrar la ventana termina su shell (y los trabajos en segundo plano).
        .onDisappear {
            embeddedTerminalSession.stop()
            tabsViewModel.closeAllPanes()
        }
    }

    private var detailColumn: some View {
        detailWithAlerts
            .navigationTitle(windowTitle)
            .toolbar(removing: .title)
            .toolbar(id: "dotphin.browser") {
                BrowserToolbar(
                    viewModel: focusedViewModel,
                    onNewFolder: {
                        nameInput = String(localized: "Nueva carpeta", bundle: #bundle)
                        showsNewFolderPrompt = true
                    },
                    onRename: { handle(.renameSelectedFiles) },
                    onDelete: { handle(.deleteSelectedFiles) },
                    onEmptyTrash: { showsEmptyTrashConfirmation = true },
                    onToggleTerminal: { handle(.toggleEmbeddedTerminal) },
                    onToggleSplit: { handle(.toggleSplit) },
                    onNewTab: { handle(.addTab) },
                    onToggleInfoPanel: { handle(.toggleInfoPanel) }
                )
            }
            // Campo de búsqueda nativo de la toolbar: filtra al tipear y busca con Intro.
            .searchable(text: searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: String(localized: "Buscar o filtrar…", bundle: #bundle))
            .onSubmit(of: .search) {
                guard let focused = focusedViewModel else { return }
                let query = focused.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    focused.searchQuery = query
                    focused.performSearch()
                }
            }
    }

    private var searchText: Binding<String> {
        Binding(
            get: { focusedViewModel?.filterText ?? "" },
            set: { newValue in
                guard let focused = focusedViewModel else { return }
                focused.filterText = newValue
                if newValue.isEmpty {
                    focused.searchQuery = ""
                }
            }
        )
    }

    private var detailWithAlerts: some View {
        detailWithPromptAlerts
            .alert(
                String(localized: "¿Eliminar este ítem?", bundle: #bundle),
                isPresented: $showsDeleteConfirmation,
                presenting: pendingDelete
            ) { item in
                Button(String(localized: "Eliminar", bundle: #bundle), role: .destructive) { focusedViewModel?.delete(item) }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            } message: { item in
                Text(String(localized: "Se moverá «\(item.name)» a la Papelera.", bundle: #bundle))
            }
            .alert(
                deleteSelectionAlertTitle,
                isPresented: $showsDeleteSelectionConfirmation
            ) {
                Button(String(localized: "Eliminar", bundle: #bundle), role: .destructive) { focusedViewModel?.deleteSelectedItems() }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            } message: {
                Text(String(localized: "Se moverán a la Papelera.", bundle: #bundle))
            }
            .alert(
                String(localized: "¿Eliminar permanentemente \(focusedViewModel?.selectedIDs.count ?? 0) ítem(s)?", bundle: #bundle),
                isPresented: $showsPermanentDeleteSelectionConfirmation
            ) {
                Button(String(localized: "Eliminar permanentemente", bundle: #bundle), role: .destructive) {
                    focusedViewModel?.deleteSelectedPermanently()
                }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            } message: {
                Text(String(localized: "Esta acción borrará los elementos del disco sin pasar por la Papelera y no se puede deshacer.", bundle: #bundle))
            }
            .alert(String(localized: "¿Vaciar la papelera?", bundle: #bundle), isPresented: $showsEmptyTrashConfirmation) {
                Button(String(localized: "Vaciar", bundle: #bundle), role: .destructive) { focusedViewModel?.emptyTrash() }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            } message: {
                Text(String(localized: "Esto borra el contenido de la papelera de forma permanente. No se puede deshacer.", bundle: #bundle))
            }
            .alert(
                String(localized: "No se pudo abrir la Terminal", bundle: #bundle),
                isPresented: Binding<Bool>(
                    get: { terminalError != nil },
                    set: { if !$0 { terminalError = nil } }
                )
            ) {
                Button(String(localized: "OK", bundle: #bundle)) { terminalError = nil }
            } message: {
                Text(terminalError ?? "")
            }
    }

    private var detailWithPromptAlerts: some View {
        detailWithSheets
            .alert(String(localized: "Nueva carpeta", bundle: #bundle), isPresented: $showsNewFolderPrompt) {
                TextField(String(localized: "Nombre", bundle: #bundle), text: $nameInput)
                Button(String(localized: "Crear", bundle: #bundle)) { focusedViewModel?.createFolder(named: nameInput) }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            }
            .alert(String(localized: "Mover selección a carpeta nueva", bundle: #bundle), isPresented: $showsMoveToNewFolderPrompt) {
                TextField(String(localized: "Nombre de la carpeta", bundle: #bundle), text: $nameInput)
                Button(String(localized: "Crear y mover", bundle: #bundle)) { focusedViewModel?.moveSelectedToNewFolder(named: nameInput) }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            }
            .alert(String(localized: "Seleccionar ítems por patrón", bundle: #bundle), isPresented: $showsSelectByPatternPrompt) {
                TextField(String(localized: "Patrón (ej. *.swift, *.png)", bundle: #bundle), text: $patternInput)
                Button(String(localized: "Seleccionar", bundle: #bundle)) { focusedViewModel?.selectItems(matchingPattern: patternInput, additive: false) }
                Button(String(localized: "Añadir a selección", bundle: #bundle)) { focusedViewModel?.selectItems(matchingPattern: patternInput, additive: true) }
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
            }
    }

    /// Los paneles que estaban dentro de un disco que se expulsó vuelven a la
    /// carpeta personal en vez de quedar mostrando un error.
    private func leaveUnmountedVolumes() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for tab in tabsViewModel.tabs {
            for pane in [tab.primary, tab.secondary].compactMap({ $0 })
            where !FileManager.default.fileExists(atPath: pane.currentURL.path) {
                pane.navigate(to: home)
            }
        }
    }

    /// `commands` es estable (un objeto por ventana); acá solo se le refrescan
    /// los closures para que vean el estado actual de la vista.
    private func connectCommands() {
        commands.handler = { command in handle(command) }
        commands.focusedViewModel = { focusedViewModel }
    }

    /// Comandos de menú de esta ventana (ver `WindowCommands`).
    private func handle(_ command: WindowCommand) {
        switch command {
        case .renameSelectedFiles:
            guard let focused = focusedViewModel else { return }
            if focused.selectedItems.count > 1 {
                showsBatchRenameSheet = true
            } else if let item = focused.selectedItem {
                focused.renamingItemID = item.id
            }
        case .createNewFolder:
            nameInput = String(localized: "Nueva carpeta", bundle: #bundle)
            showsNewFolderPrompt = true
        case .moveToNewFolder:
            guard let focused = focusedViewModel, !focused.selectedIDs.isEmpty else { return }
            nameInput = String(localized: "Nueva carpeta", bundle: #bundle)
            showsMoveToNewFolderPrompt = true
        case .selectByPattern:
            showsSelectByPatternPrompt = true
        case .deleteSelectedFiles:
            guard let focused = focusedViewModel else { return }
            if focused.selectedItems.count > 1 {
                if settingsModel.settings.confirmMoveToTrash {
                    showsDeleteSelectionConfirmation = true
                } else {
                    focused.deleteSelectedItems()
                }
            } else if let item = focused.selectedItem {
                if settingsModel.settings.confirmMoveToTrash {
                    pendingDelete = item
                    showsDeleteConfirmation = true
                } else {
                    focused.delete(item)
                }
            }
        case .permanentDeleteSelectedFiles:
            guard let focused = focusedViewModel, !focused.selectedItems.isEmpty else { return }
            if settingsModel.settings.confirmPermanentDelete {
                showsPermanentDeleteSelectionConfirmation = true
            } else {
                focused.deleteSelectedPermanently()
            }
        case .compareFiles:
            if let focused = focusedViewModel, focused.selectedItems.count == 2 {
                comparePair = (focused.selectedItems[0].url, focused.selectedItems[1].url)
            } else if let tab = tabsViewModel.selectedTab,
                      let leftItem = tab.primary.selectedItem,
                      let rightItem = tab.secondary?.selectedItem {
                comparePair = (leftItem.url, rightItem.url)
            }
        case .quickLookSelectedFiles:
            guard let focused = focusedViewModel else { return }
            QuickLookPreviewController.shared.toggle(for: focused)
        case .copyToOtherSplitPane:
            guard let tab = tabsViewModel.selectedTab, tab.isSplit,
                  let focused = focusedViewModel else { return }
            let otherPane = (tab.focusedPaneIndex == 0) ? tab.secondary : tab.primary
            guard let destURL = otherPane?.currentURL else { return }
            focused.copySelected(to: destURL)
            otherPane?.refresh()
        case .moveToOtherSplitPane:
            guard let tab = tabsViewModel.selectedTab, tab.isSplit,
                  let focused = focusedViewModel else { return }
            let otherPane = (tab.focusedPaneIndex == 0) ? tab.secondary : tab.primary
            guard let destURL = otherPane?.currentURL else { return }
            focused.moveSelected(to: destURL)
            otherPane?.refresh()
        case .showProperties:
            guard let focused = focusedViewModel else { return }
            propertiesTargetURL = focused.selectedItem?.url ?? focused.currentURL
        case .showViewPropertiesDialog:
            showsViewPropertiesDialog = true
        case .showDiskUsageAnalyzer:
            showsDiskUsageAnalyzer = true
        case .addTab:
            let url = focusedViewModel?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
            tabsViewModel.addTab(
                startingAt: url,
                afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                splitView: settingsModel.settings.startInSplitView
            )
        case .duplicateTab:
            if let tab = tabsViewModel.selectedTab {
                tabsViewModel.duplicateTab(tab.id)
            }
        case .closeTab:
            if let tab = tabsViewModel.selectedTab, tabsViewModel.tabs.count > 1 {
                tabsViewModel.closeTab(tab.id)
            }
        case .closeOtherTabs:
            if let tab = tabsViewModel.selectedTab {
                tabsViewModel.closeOtherTabs(keeping: tab.id)
            }
        case .reopenClosedTab:
            tabsViewModel.reopenLastClosedTab()
        case .selectNextTab:
            tabsViewModel.selectNextTab()
        case .selectPrevTab:
            tabsViewModel.selectPreviousTab()
        case .toggleSplit:
            if let tab = tabsViewModel.selectedTab {
                withAnimation(.snappy(duration: 0.22)) {
                    tabsViewModel.toggleSplit(for: tab.id)
                }
            }
        case .focusOtherSplitPane:
            if let tab = tabsViewModel.selectedTab {
                withAnimation(.snappy(duration: 0.18)) {
                    tabsViewModel.focusOtherPane(for: tab.id)
                }
            }
        case .moveSplitToTabs:
            if let tab = tabsViewModel.selectedTab {
                withAnimation(.snappy(duration: 0.22)) {
                    tabsViewModel.moveSplitViewToTabs(for: tab.id)
                }
            }
        case .swapSplitPanes:
            if let tab = tabsViewModel.selectedTab {
                withAnimation(.snappy(duration: 0.22)) {
                    tabsViewModel.swapSplitPanes(for: tab.id)
                }
            }
        case .toggleInfoPanel:
            withAnimation(.snappy(duration: 0.22)) {
                showsInfoPanel.toggle()
            }
        case .toggleFilterBar:
            guard let focused = focusedViewModel else { return }
            withAnimation(.snappy(duration: 0.18)) {
                focused.isFilterBarVisible.toggle()
                if !focused.isFilterBarVisible {
                    focused.filterText = ""
                    focused.isFilterLocked = false
                }
            }
        case .bookmarkAllTabs:
            let tabURLs = tabsViewModel.tabs.map { $0.primary.currentURL }
            PlacesProvider().addBookmarks(for: tabURLs)
        case .openAllBookmarksInTabs:
            let custom = PlacesProvider().customBookmarks()
            for item in custom {
                tabsViewModel.addTab(
                    startingAt: item.url,
                    afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                    splitView: settingsModel.settings.startInSplitView
                )
            }
        case .editBookmarks:
            showsBookmarksEditorSheet = true
        case .toggleEmbeddedTerminal:
            withAnimation(.snappy(duration: 0.2)) {
                showsEmbeddedTerminal.toggle()
            }
        case .openTerminal:
            guard let focused = focusedViewModel else { return }
            do {
                try TerminalLauncher().openTerminal(at: focused.currentURL)
            } catch {
                terminalError = error.localizedDescription
            }
        case .toggleTabOverview:
            withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                showsTabOverview.toggle()
            }
        case .editLocationBar:
            locationEditRequest += 1
        case .focusSearch:
            isSearchPresented = true
        }
    }

    private var deleteSelectionAlertTitle: String {
        let count = focusedViewModel?.selectedIDs.count ?? 0
        return String(localized: "¿Eliminar \(count) ítems?", bundle: #bundle)
    }

    private var detailWithSheets: some View {
        detailMainStack
            .navigationSplitViewColumnWidth(min: 600, ideal: 760)
            .overlay {
                tabOverviewOverlay
            }
            .background(gestureMonitor)
            .sheet(isPresented: $showsBatchRenameSheet) {
                if let focused = focusedViewModel {
                    BatchRenameSheetView(items: focused.selectedItems) { pattern, startIndex in
                        focused.batchRenameSelected(pattern: pattern, startIndex: startIndex)
                    }
                }
            }
            .sheet(isPresented: $showsViewPropertiesDialog) {
                if let focused = focusedViewModel {
                    ViewPropertiesDialogSheetView(
                        folderURL: focused.currentURL,
                        draft: focused.viewProperties,
                        globalShowsHiddenFiles: settingsModel.settings.showsHiddenFiles
                    ) { updated, scope, useAsDefault in
                        focused.applyViewProperties(updated, scope: scope, useAsDefault: useAsDefault)
                    }
                }
            }
            .sheet(isPresented: $showsDiskUsageAnalyzer) {
                if let focused = focusedViewModel {
                    DiskUsageAnalyzerSheetView(
                        directoryURL: focused.currentURL,
                        onNavigateToFolder: { folderURL in
                            focused.navigate(to: folderURL)
                        }
                    )
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
                        guard let focused = focusedViewModel else { return }
                        let parentDir = resolvedTarget.deletingLastPathComponent()
                        focused.navigate(to: parentDir, selecting: resolvedTarget)
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
            .sheet(isPresented: $showsBookmarksEditorSheet) {
                BookmarksEditorSheetView { urls in
                    for url in urls {
                        tabsViewModel.addTab(
                            startingAt: url,
                            afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                            splitView: settingsModel.settings.startInSplitView
                        )
                    }
                }
            }
    }

    private var detailMainStack: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                // Como Safari: con una sola pestaña no hay barra (reabrir una cerrada
                // sigue en Archivo y con ⇧⌘T).
                if settingsModel.settings.alwaysShowTabBar || tabsViewModel.tabs.count > 1 {
                    TabBarView(
                        viewModel: tabsViewModel,
                        onShowTabOverview: {
                            withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                                showsTabOverview.toggle()
                            }
                        }
                    )
                }
                if let focused = focusedViewModel, tabsViewModel.selectedTab?.isSplit != true {
                    HStack(spacing: 8) {
                        BreadcrumbView(
                            url: focused.currentURL,
                            editableByDefault: settingsModel.settings.editableLocationByDefault,
                            onNavigate: { focused.navigate(to: $0) },
                            onOpenInNewTab: { url in
                                tabsViewModel.addTab(
                                    startingAt: url,
                                    afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                                    splitView: settingsModel.settings.startInSplitView
                                )
                            },
                            onOpenInSplitView: { url in
                                if let tab = tabsViewModel.selectedTab {
                                    tabsViewModel.openInSplitView(url, for: tab.id)
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
            .background(.bar)

            Divider()

            // Divisores nativos (`NSSplitView`): panel de información a la
            // derecha y terminal integrada abajo.
            HSplitView {
                    VSplitView {
                    if let tab = tabsViewModel.selectedTab {
                        SplitBrowserView(
                            tab: tab,
                            onOpenInNewTab: { url in
                                tabsViewModel.addTab(
                                    startingAt: url,
                                    afterCurrentTab: !settingsModel.settings.openNewTabAfterLastTab,
                                    splitView: settingsModel.settings.startInSplitView
                                )
                            },
                            onOpenInSplitView: { url in
                                tabsViewModel.openInSplitView(url, for: tab.id)
                            },
                            onOpenTerminal: { url in
                                focusedViewModel?.navigate(to: url)
                                withAnimation(.snappy(duration: 0.2)) {
                                    showsEmbeddedTerminal = true
                                }
                            }
                        ) { index in
                            tabsViewModel.setFocusedPane(index, for: tab.id)
                        }
                        .frame(minHeight: 180, maxHeight: .infinity)
                    }

                    if showsEmbeddedTerminal, let focused = focusedViewModel {
                        EmbeddedTerminalPanelView(
                            session: embeddedTerminalSession,
                            currentDirectory: focused.currentURL,
                            onDirectoryChanged: { newDir in
                                focusedViewModel?.navigate(to: newDir)
                            },
                            onOpenExternalTerminal: {
                                do {
                                    try TerminalLauncher().openTerminal(at: focused.currentURL)
                                } catch {
                                    terminalError = error.localizedDescription
                                }
                            },
                            onClose: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    showsEmbeddedTerminal = false
                                }
                            }
                        )
                        .frame(
                            minHeight: EmbeddedTerminalPanelView.minHeight,
                            idealHeight: EmbeddedTerminalPanelView.defaultHeight,
                            maxHeight: EmbeddedTerminalPanelView.maxHeight
                        )
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                if showsInfoPanel {
                    InfoPanelView(
                        item: focusedViewModel?.selectedItem,
                        selectedCount: focusedViewModel?.selectedItems.count ?? 0,
                        selectedTotalBytes: focusedViewModel?.selectedItems.compactMap(\.size).reduce(0, +),
                        onShowProperties: { url in
                            propertiesTargetURL = url
                        },
                        onColorTagChanged: { _ in
                            focusedViewModel?.refresh()
                        }
                    )
                    .frame(minWidth: 190, idealWidth: 245, maxWidth: 380, maxHeight: .infinity)
                    .background(.bar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let focused = focusedViewModel, settingsModel.settings.statusBarMode != .disabled {
                Divider()
                let volumeInfo = VolumeInfoProvider().info(for: focused.currentURL)
                StatusBarView(
                    itemCount: focused.filteredItems.count,
                    totalCount: focused.items.count,
                    selectedCount: focused.selectedItems.count,
                    selectedTotalBytes: focused.selectedItems.compactMap(\.size).reduce(0, +),
                    singleSelectedItem: focused.selectedItem,
                    availableCapacity: focused.availableCapacity,
                    totalCapacity: volumeInfo.totalCapacity,
                    displayMode: settingsModel.settings.statusBarMode,
                    zoomLevel: settingsModel.settings.showZoomSliderInStatusBar ? Binding<Double>(
                        get: { focused.viewProperties.zoomLevel },
                        set: { focused.setZoomLevel($0) }
                    ) : nil,
                    isSelectionModeActive: Binding<Bool>(
                        get: { focused.isSelectionModeActive },
                        set: { focused.isSelectionModeActive = $0 }
                    ),
                    onOpenDiskUsageAnalyzer: {
                        showsDiskUsageAnalyzer = true
                    },
                    onEmptyTrash: focused.isBrowsingTrash ? {
                        if settingsModel.settings.confirmEmptyTrash {
                            showsEmptyTrashConfirmation = true
                        } else {
                            focused.emptyTrash()
                        }
                    } : nil,
                    onToggleZoomSlider: {
                        settingsModel.settings.showZoomSliderInStatusBar.toggle()
                    },
                    onChangeDisplayMode: { newMode in
                        settingsModel.settings.statusBarMode = newMode
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var tabOverviewOverlay: some View {
        if showsTabOverview {
            TabOverviewView(
                viewModel: tabsViewModel,
                places: places,
                onSelectTab: { tabID in
                    tabsViewModel.selectTab(tabID)
                    withAnimation(.spring(duration: 0.26, bounce: 0.04)) {
                        showsTabOverview = false
                    }
                },
                onAddTab: {
                    let url = focusedViewModel?.currentURL
                        ?? FileManager.default.homeDirectoryForCurrentUser
                    tabsViewModel.addTab(startingAt: url)
                    withAnimation(.spring(duration: 0.26, bounce: 0.04)) {
                        showsTabOverview = false
                    }
                },
                onCloseOverview: {
                    withAnimation(.spring(duration: 0.26, bounce: 0.04)) {
                        showsTabOverview = false
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var gestureMonitor: some View {
        ZStack {
            TabOverviewPinchGestureView(
                isOverviewVisible: showsTabOverview,
                onShowOverview: {
                    withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                        showsTabOverview = true
                    }
                },
                onHideOverview: {
                    withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                        showsTabOverview = false
                    }
                }
            )
        }
        .onChange(of: focusedViewModel?.currentURL) { _, _ in
            tabsViewModel.saveSessionSnapshot()
        }
    }
}
