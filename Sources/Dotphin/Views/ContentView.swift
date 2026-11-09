import AppKit
import SwiftUI

struct ContentView: View {
    @State private var appSettings = AppSettingsStore().settings()
    @State private var tabsViewModel = TabsViewModel(
        startingAt: AppSettingsStore().settings().startupURL,
        startInSplitView: AppSettingsStore().settings().startInSplitView,
        rememberOpenedTabs: AppSettingsStore().settings().rememberOpenedTabs
    )
    @State private var places = PlacesProvider().allPlaces()
    @State private var savedSearches = PlacesProvider().savedSearches()
    @State private var showsInfoPanel = false
    @State private var infoPanelWidth: CGFloat = 245
    @State private var infoPanelDragStartWidth: CGFloat? = nil
    @State private var showsEmbeddedTerminal = false
    @State private var terminalPanelHeight: CGFloat = EmbeddedTerminalPanelView.defaultHeight
    @State private var embeddedTerminalSession = EmbeddedTerminalSession()
    @State private var showsSearchBar = false
    @State private var showsToolbarConfigSheet = false
    @State private var showsTabOverview = false
    @State private var availableToolbarWidth: CGFloat = 680
    @State private var pendingDelete: FileItem?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsPermanentDeleteSelectionConfirmation = false
    @State private var showsRenamePrompt = false
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

    private var focusedViewModel: BrowserViewModel? {
        tabsViewModel.selectedTab?.focused
    }

    private var isSearchOrFilterVisible: Bool {
        if showsSearchBar { return true }
        guard let focused = focusedViewModel else { return false }
        return !focused.filterText.isEmpty || !focused.searchQuery.isEmpty
    }

    private var windowTitle: String {
        guard let url = focusedViewModel?.currentURL else { return "Dotphin" }
        if appSettings.showFullPathInTitlebar {
            return url.path
        }
        let name = url.lastPathComponent
        return (name.isEmpty || name == "/") ? "/" : name
    }

    var body: some View {
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
                    showsSearchBar = true
                },
                onOpenInNewTab: { url in
                    tabsViewModel.addTab(
                        startingAt: url,
                        afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                        splitView: appSettings.startInSplitView
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
        .frame(minWidth: 840, minHeight: 540)
        .focusedSceneValue(\.browserViewModel, focusedViewModel)
        .onReceive(NotificationCenter.default.publisher(for: .placesBookmarksDidChange)) { _ in
            places = PlacesProvider().allPlaces()
            savedSearches = PlacesProvider().savedSearches()
        }
    }

    private var detailColumn: some View {
        detailWithAlerts
            .navigationTitle(windowTitle)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                if let focused = focusedViewModel {
                    ToolbarItem(placement: .navigation) {
                        toolbarLeadingView(for: focused)
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarSpacer(.flexible)

                    ToolbarItem(placement: .primaryAction) {
                        toolbarTrailingView(for: focused)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .onChange(of: appSettings) { _, newValue in
                AppSettingsStore().setSettings(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let latest = AppSettingsStore().settings()
                if latest != appSettings {
                    appSettings = latest
                }
            }
    }

    private var detailWithAlerts: some View {
        detailWithPromptAlerts
            .alert(
                "¿Eliminar este ítem?",
                isPresented: $showsDeleteConfirmation,
                presenting: pendingDelete
            ) { item in
                Button("Eliminar", role: .destructive) { focusedViewModel?.delete(item) }
                Button("Cancelar", role: .cancel) {}
            } message: { item in
                Text("Se moverá «\(item.name)» a la Papelera.")
            }
            .alert(
                deleteSelectionAlertTitle,
                isPresented: $showsDeleteSelectionConfirmation
            ) {
                Button("Eliminar", role: .destructive) { focusedViewModel?.deleteSelectedItems() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se moverán a la Papelera.")
            }
            .alert(
                "¿Eliminar permanentemente \(focusedViewModel?.selectedIDs.count ?? 0) ítem(s)?",
                isPresented: $showsPermanentDeleteSelectionConfirmation
            ) {
                Button("Eliminar permanentemente", role: .destructive) {
                    focusedViewModel?.deleteSelectedPermanently()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción borrará los elementos del disco sin pasar por la Papelera y no se puede deshacer.")
            }
            .alert("¿Vaciar la papelera?", isPresented: $showsEmptyTrashConfirmation) {
                Button("Vaciar", role: .destructive) { focusedViewModel?.emptyTrash() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esto borra el contenido de la papelera de forma permanente. No se puede deshacer.")
            }
            .alert(
                "No se pudo abrir la Terminal",
                isPresented: Binding<Bool>(
                    get: { terminalError != nil },
                    set: { if !$0 { terminalError = nil } }
                )
            ) {
                Button("OK") { terminalError = nil }
            } message: {
                Text(terminalError ?? "")
            }
    }

    private var detailWithPromptAlerts: some View {
        detailWithNavigationShortcuts
            .alert("Renombrar", isPresented: $showsRenamePrompt) {
                TextField("Nombre", text: $nameInput)
                Button("Renombrar") { focusedViewModel?.renameSelected(to: nameInput) }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Nueva carpeta", isPresented: $showsNewFolderPrompt) {
                TextField("Nombre", text: $nameInput)
                Button("Crear") { focusedViewModel?.createFolder(named: nameInput) }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Mover selección a carpeta nueva", isPresented: $showsMoveToNewFolderPrompt) {
                TextField("Nombre de la carpeta", text: $nameInput)
                Button("Crear y mover") { focusedViewModel?.moveSelectedToNewFolder(named: nameInput) }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Seleccionar ítems por patrón", isPresented: $showsSelectByPatternPrompt) {
                TextField("Patrón (ej. *.swift, *.png)", text: $patternInput)
                Button("Seleccionar") { focusedViewModel?.selectItems(matchingPattern: patternInput, additive: false) }
                Button("Añadir a selección") { focusedViewModel?.selectItems(matchingPattern: patternInput, additive: true) }
                Button("Cancelar", role: .cancel) {}
            }
    }

    private var deleteSelectionAlertTitle: String {
        let count = focusedViewModel?.selectedIDs.count ?? 0
        return "¿Eliminar \(count) ítems?"
    }

    private var detailWithSheets: some View {
        detailMainStack
            .navigationSplitViewColumnWidth(min: 600, ideal: 760)
            .overlay {
                tabOverviewOverlay
            }
            .background(gestureMonitor)
            .sheet(isPresented: $showsToolbarConfigSheet) {
                ToolbarConfigurationSheetView(settings: $appSettings)
            }
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
                        globalShowsHiddenFiles: appSettings.showsHiddenFiles
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
                        focused.navigate(to: parentDir)
                        if let targetItem = focused.items.first(where: { $0.url.standardizedFileURL == resolvedTarget.standardizedFileURL }) {
                            focused.select(targetItem)
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
            .sheet(isPresented: $showsBookmarksEditorSheet) {
                BookmarksEditorSheetView { urls in
                    for url in urls {
                        tabsViewModel.addTab(
                            startingAt: url,
                            afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                            splitView: appSettings.startInSplitView
                        )
                    }
                }
            }
    }

    private var detailWithFileShortcuts: some View {
        detailWithSheets
            .onReceive(NotificationCenter.default.publisher(for: .openToolbarConfiguration)) { _ in
                showsToolbarConfigSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameSelectedFiles)) { _ in
                guard let focused = focusedViewModel else { return }
                if focused.selectedItems.count > 1 {
                    showsBatchRenameSheet = true
                } else if let item = focused.selectedItem {
                    nameInput = item.name
                    showsRenamePrompt = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .createNewFolderShortcut)) { _ in
                nameInput = "Nueva carpeta"
                showsNewFolderPrompt = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveToNewFolderShortcut)) { _ in
                guard let focused = focusedViewModel, !focused.selectedIDs.isEmpty else { return }
                nameInput = "Nueva carpeta"
                showsMoveToNewFolderPrompt = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectByPatternShortcut)) { _ in
                showsSelectByPatternPrompt = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedFilesShortcut)) { _ in
                guard let focused = focusedViewModel else { return }
                if focused.selectedItems.count > 1 {
                    if appSettings.confirmMoveToTrash {
                        showsDeleteSelectionConfirmation = true
                    } else {
                        focused.deleteSelectedItems()
                    }
                } else if let item = focused.selectedItem {
                    if appSettings.confirmMoveToTrash {
                        pendingDelete = item
                        showsDeleteConfirmation = true
                    } else {
                        focused.delete(item)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .permanentDeleteSelectedFilesShortcut)) { _ in
                guard let focused = focusedViewModel, !focused.selectedItems.isEmpty else { return }
                if appSettings.confirmPermanentDelete {
                    showsPermanentDeleteSelectionConfirmation = true
                } else {
                    focused.deleteSelectedPermanently()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareFilesShortcut)) { _ in
                if let focused = focusedViewModel, focused.selectedItems.count == 2 {
                    comparePair = (focused.selectedItems[0].url, focused.selectedItems[1].url)
                } else if let tab = tabsViewModel.selectedTab,
                          let leftItem = tab.primary.selectedItem,
                          let rightItem = tab.secondary?.selectedItem {
                    comparePair = (leftItem.url, rightItem.url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickLookSelectedFilesShortcut)) { _ in
                guard let focused = focusedViewModel else { return }
                QuickLookPreviewController.shared.toggle(for: focused)
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyToOtherSplitPaneShortcut)) { _ in
                guard let tab = tabsViewModel.selectedTab, tab.isSplit,
                      let focused = focusedViewModel else { return }
                let otherPane = (tab.focusedPaneIndex == 0) ? tab.secondary : tab.primary
                guard let destURL = otherPane?.currentURL else { return }
                focused.copySelected(to: destURL)
                otherPane?.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveToOtherSplitPaneShortcut)) { _ in
                guard let tab = tabsViewModel.selectedTab, tab.isSplit,
                      let focused = focusedViewModel else { return }
                let otherPane = (tab.focusedPaneIndex == 0) ? tab.secondary : tab.primary
                guard let destURL = otherPane?.currentURL else { return }
                focused.moveSelected(to: destURL)
                otherPane?.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPropertiesShortcut)) { _ in
                guard let focused = focusedViewModel else { return }
                propertiesTargetURL = focused.selectedItem?.url ?? focused.currentURL
            }
            .onReceive(NotificationCenter.default.publisher(for: .showViewPropertiesDialogShortcut)) { _ in
                showsViewPropertiesDialog = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showDiskUsageAnalyzerShortcut)) { _ in
                showsDiskUsageAnalyzer = true
            }
    }

    private var detailWithTabAndSplitShortcuts: some View {
        detailWithFileShortcuts
            .onReceive(NotificationCenter.default.publisher(for: .addTabShortcut)) { _ in
                let url = focusedViewModel?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
                tabsViewModel.addTab(
                    startingAt: url,
                    afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                    splitView: appSettings.startInSplitView
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicateTabShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    tabsViewModel.duplicateTab(tab.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTabShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab, tabsViewModel.tabs.count > 1 {
                    tabsViewModel.closeTab(tab.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeOtherTabsShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    tabsViewModel.closeOtherTabs(keeping: tab.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reopenClosedTabShortcut)) { _ in
                tabsViewModel.reopenLastClosedTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectNextTabShortcut)) { _ in
                tabsViewModel.selectNextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectPrevTabShortcut)) { _ in
                tabsViewModel.selectPreviousTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSplitShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    withAnimation(.snappy(duration: 0.22)) {
                        tabsViewModel.toggleSplit(for: tab.id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusOtherSplitPaneShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    withAnimation(.snappy(duration: 0.18)) {
                        tabsViewModel.focusOtherPane(for: tab.id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveSplitToTabsShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    withAnimation(.snappy(duration: 0.22)) {
                        tabsViewModel.moveSplitViewToTabs(for: tab.id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .swapSplitPanesShortcut)) { _ in
                if let tab = tabsViewModel.selectedTab {
                    withAnimation(.snappy(duration: 0.22)) {
                        tabsViewModel.swapSplitPanes(for: tab.id)
                    }
                }
            }
    }

    private var detailWithNavigationShortcuts: some View {
        detailWithTabAndSplitShortcuts
            .onReceive(NotificationCenter.default.publisher(for: .toggleInfoPanelShortcut)) { _ in
                withAnimation(.snappy(duration: 0.22)) {
                    showsInfoPanel.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFilterBarShortcut)) { _ in
                guard let focused = focusedViewModel else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    focused.isFilterBarVisible.toggle()
                    if !focused.isFilterBarVisible {
                        focused.filterText = ""
                        focused.isFilterLocked = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookmarkAllTabsShortcut)) { _ in
                let tabURLs = tabsViewModel.tabs.map { $0.primary.currentURL }
                PlacesProvider().addBookmarks(for: tabURLs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAllBookmarksInTabsShortcut)) { _ in
                let custom = PlacesProvider().customBookmarks()
                for item in custom {
                    tabsViewModel.addTab(
                        startingAt: item.url,
                        afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                        splitView: appSettings.startInSplitView
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editBookmarksShortcut)) { _ in
                showsBookmarksEditorSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEmbeddedTerminalShortcut)) { _ in
                withAnimation(.snappy(duration: 0.2)) {
                    showsEmbeddedTerminal.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTerminalShortcut)) { _ in
                guard let focused = focusedViewModel else { return }
                do {
                    try TerminalLauncher().openTerminal(at: focused.currentURL)
                } catch {
                    terminalError = error.localizedDescription
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTabOverview)) { _ in
                withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                    showsTabOverview.toggle()
                }
            }
    }

    private var detailMainStack: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                if appSettings.alwaysShowTabBar || tabsViewModel.tabs.count > 1 || !tabsViewModel.recentlyClosedTabs.isEmpty {
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
                            editableByDefault: appSettings.editableLocationByDefault,
                            onNavigate: focused.navigate,
                            onOpenInNewTab: { url in
                                tabsViewModel.addTab(
                                    startingAt: url,
                                    afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                                    splitView: appSettings.startInSplitView
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
            .background(
                WindowToolbarEnforcer { newWidth in
                    if abs(newWidth - availableToolbarWidth) >= 1 {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            availableToolbarWidth = newWidth
                        }
                    }
                }
            )

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if let tab = tabsViewModel.selectedTab {
                        SplitBrowserView(
                            tab: tab,
                            onOpenInNewTab: { url in
                                tabsViewModel.addTab(
                                    startingAt: url,
                                    afterCurrentTab: !appSettings.openNewTabAfterLastTab,
                                    splitView: appSettings.startInSplitView
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
                            panelHeight: $terminalPanelHeight,
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
                        .frame(height: terminalPanelHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInfoPanel {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 6)
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: 1)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = infoPanelDragStartWidth ?? infoPanelWidth
                                if infoPanelDragStartWidth == nil {
                                    infoPanelDragStartWidth = start
                                }
                                let proposed = start - value.translation.width
                                infoPanelWidth = min(380, max(190, proposed))
                            }
                            .onEnded { _ in
                                infoPanelDragStartWidth = nil
                            }
                    )

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
                    .frame(width: infoPanelWidth)
                    .frame(maxHeight: .infinity)
                    .background(.bar)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: showsInfoPanel)
            .animation(.snappy(duration: 0.2), value: showsEmbeddedTerminal)
            if let focused = focusedViewModel, appSettings.statusBarMode != .disabled {
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
                    displayMode: appSettings.statusBarMode,
                    zoomLevel: appSettings.showZoomSliderInStatusBar ? Binding<Double>(
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
                        if appSettings.confirmEmptyTrash {
                            showsEmptyTrashConfirmation = true
                        } else {
                            focused.emptyTrash()
                        }
                    } : nil,
                    onToggleZoomSlider: {
                        appSettings.showZoomSliderInStatusBar.toggle()
                    },
                    onChangeDisplayMode: { newMode in
                        appSettings.statusBarMode = newMode
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
            TrackpadTabGestureMonitorView(
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
                },
                onToggleOverview: {
                    withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
                        showsTabOverview.toggle()
                    }
                }
            )
            QuickLookKeyMonitorView(
                onSpacebar: {
                    guard let focused = focusedViewModel else { return false }
                    if QuickLookPreviewController.shared.isVisible {
                        QuickLookPreviewController.shared.close()
                        return true
                    }
                    let visible = focused.searchQuery.isEmpty ? focused.filteredItems : focused.searchResults
                    guard !focused.selectedItems.isEmpty || !visible.isEmpty else { return false }
                    QuickLookPreviewController.shared.toggle(for: focused)
                    return true
                },
                onArrowDirection: { direction, extendSelection in
                    guard let focused = focusedViewModel else { return false }
                    guard !showsTabOverview else { return false }
                    if QuickLookPreviewController.shared.isVisible {
                        if QuickLookPreviewController.shared.isMultiSelectionPreview {
                            switch direction {
                            case .left, .up:
                                QuickLookPreviewController.shared.showPrevious()
                            case .right, .down:
                                QuickLookPreviewController.shared.showNext()
                            }
                        } else {
                            focused.navigateSelection(direction: direction, extendSelection: extendSelection)
                            QuickLookPreviewController.shared.updateIfVisible(for: focused)
                        }
                        return true
                    }
                    focused.navigateSelection(direction: direction, extendSelection: extendSelection)
                    return true
                },
                onReturnRename: {
                    guard let focused = focusedViewModel, !focused.selectedIDs.isEmpty else { return false }
                    NotificationCenter.default.post(name: .renameSelectedFiles, object: nil)
                    return true
                },
                onTypeAheadCharacters: { chars in
                    guard let focused = focusedViewModel else { return false }
                    guard !showsTabOverview else { return false }
                    let matched = focused.selectItemByTypeAhead(chars)
                    if matched != nil {
                        QuickLookPreviewController.shared.updateIfVisible(for: focused)
                    }
                    return true
                }
            )
        }
        .onChange(of: focusedViewModel?.selectedIDs) { _, _ in
            if let focused = focusedViewModel {
                QuickLookPreviewController.shared.updateIfVisible(for: focused)
            }
        }
        .onChange(of: focusedViewModel?.currentURL) { _, _ in
            tabsViewModel.saveSessionSnapshot()
        }
    }

    private func toolbarLeadingView(for focused: BrowserViewModel) -> some View {
        CustomizableToolbarView(
            focusedViewModel: focused,
            settings: $appSettings,
            isSearchOrFilterVisible: isSearchOrFilterVisible,
            availableToolbarWidth: availableToolbarWidth,
            placementRole: .leading,
            onNewFolder: {
                nameInput = "Nueva carpeta"
                showsNewFolderPrompt = true
            },
            onRename: {
                if focused.selectedItems.count > 1 {
                    showsBatchRenameSheet = true
                } else if let item = focused.selectedItem {
                    nameInput = item.name
                    showsRenamePrompt = true
                }
            },
            onDelete: {
                if focused.selectedItems.count > 1 {
                    showsDeleteSelectionConfirmation = true
                } else if let item = focused.selectedItem {
                    pendingDelete = item
                    showsDeleteConfirmation = true
                }
            },
            onRestore: {
                focused.restoreSelected()
            },
            onEmptyTrash: {
                showsEmptyTrashConfirmation = true
            },
            onOpenTerminal: {
                withAnimation(.snappy(duration: 0.2)) {
                    showsEmbeddedTerminal.toggle()
                }
            },
            onToggleSplit: {
                if let tab = tabsViewModel.selectedTab {
                    tabsViewModel.toggleSplit(for: tab.id)
                }
            },
            onNewTab: {
                tabsViewModel.addTab(startingAt: focused.currentURL)
            },
            onToggleInfoPanel: {
                showsInfoPanel.toggle()
            },
            onToggleSearch: {
                if isSearchOrFilterVisible {
                    focused.filterText = ""
                    focused.searchQuery = ""
                    showsSearchBar = false
                } else {
                    showsSearchBar = true
                }
            },
            onOpenConfigureToolbar: {
                showsToolbarConfigSheet = true
            }
        )
    }

    private func toolbarTrailingView(for focused: BrowserViewModel) -> some View {
        CustomizableToolbarView(
            focusedViewModel: focused,
            settings: $appSettings,
            isSearchOrFilterVisible: isSearchOrFilterVisible,
            availableToolbarWidth: availableToolbarWidth,
            placementRole: .trailing,
            onNewFolder: {
                nameInput = "Nueva carpeta"
                showsNewFolderPrompt = true
            },
            onRename: {
                if focused.selectedItems.count > 1 {
                    showsBatchRenameSheet = true
                } else if let item = focused.selectedItem {
                    nameInput = item.name
                    showsRenamePrompt = true
                }
            },
            onDelete: {
                if focused.selectedItems.count > 1 {
                    showsDeleteSelectionConfirmation = true
                } else if let item = focused.selectedItem {
                    pendingDelete = item
                    showsDeleteConfirmation = true
                }
            },
            onRestore: {
                focused.restoreSelected()
            },
            onEmptyTrash: {
                showsEmptyTrashConfirmation = true
            },
            onOpenTerminal: {
                withAnimation(.snappy(duration: 0.2)) {
                    showsEmbeddedTerminal.toggle()
                }
            },
            onToggleSplit: {
                if let tab = tabsViewModel.selectedTab {
                    tabsViewModel.toggleSplit(for: tab.id)
                }
            },
            onNewTab: {
                tabsViewModel.addTab(startingAt: focused.currentURL)
            },
            onToggleInfoPanel: {
                showsInfoPanel.toggle()
            },
            onToggleSearch: {
                if isSearchOrFilterVisible {
                    focused.filterText = ""
                    focused.searchQuery = ""
                    showsSearchBar = false
                } else {
                    showsSearchBar = true
                }
            },
            onOpenConfigureToolbar: {
                showsToolbarConfigSheet = true
            }
        )
    }
}

private struct WindowToolbarEnforcer: NSViewRepresentable {
    var onAvailableWidthChange: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> EnforcerNSView {
        let view = EnforcerNSView()
        view.onAvailableWidthChange = onAvailableWidthChange
        return view
    }

    func updateNSView(_ nsView: EnforcerNSView, context: Context) {
        nsView.onAvailableWidthChange = onAvailableWidthChange
        nsView.enforceToolbarVisible()
    }

    final class EnforcerNSView: NSView {
        var onAvailableWidthChange: ((CGFloat) -> Void)?
        private var lastReportedWidth: CGFloat = 0
        nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            if let window {
                window.contentMinSize = NSSize(width: 840, height: 540)
                window.minSize = NSSize(width: 840, height: 540)
                if window.frame.height < 540 || window.frame.width < 840 {
                    var restored = window.frame
                    let newHeight = max(restored.height, 640)
                    restored.origin.y -= (newHeight - restored.height)
                    restored.size.height = newHeight
                    restored.size.width = max(restored.width, 980)
                    window.setFrame(restored, display: true)
                }
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reportWidthIfNeeded()
                    }
                }
            }
            enforceToolbarVisible()
            reportWidthIfNeeded()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportWidthIfNeeded()
        }

        func enforceToolbarVisible() {
            guard let window else { return }
            if window.tabbingMode != .disallowed {
                window.tabbingMode = .disallowed
            }
            let minTarget = NSSize(width: 840, height: 540)
            if window.contentMinSize != minTarget {
                window.contentMinSize = minTarget
            }
            if window.minSize != minTarget {
                window.minSize = minTarget
            }
            guard let toolbar = window.toolbar else { return }
            if !toolbar.isVisible {
                toolbar.isVisible = true
            }
            if toolbar.displayMode != .iconOnly {
                toolbar.displayMode = .iconOnly
            }
            if toolbar.allowsUserCustomization {
                toolbar.allowsUserCustomization = false
            }
            // Never let NSToolbar evict our custom toolbar item into its native ">>" menu;
            // overflow is handled by our own "…" menu.
            for item in toolbar.items {
                if item.visibilityPriority != .user {
                    item.visibilityPriority = .user
                }
                if let itemView = item.view {
                    if itemView.contentCompressionResistancePriority(for: .horizontal) != .defaultLow {
                        itemView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                    }
                    if itemView.contentHuggingPriority(for: .horizontal) != .defaultLow {
                        itemView.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    }
                }
            }
        }

        private func reportWidthIfNeeded() {
            guard let window else { return }
            var detailWidth = bounds.width
            let windowWidth = max(window.contentLayoutRect.width, window.frame.width)
            if detailWidth <= 100 && windowWidth > 300 {
                detailWidth = max(400, windowWidth - 205)
            }
            guard detailWidth > 100 else { return }
            let isSidebarCollapsed = (windowWidth - detailWidth) < 150
            // Reserve comfortable margin for NSToolbar leading/trailing padding and the flexible
            // ToolbarSpacer so our own "…" overflow pill absorbs actions smoothly before NSToolbar clips.
            let margin: CGFloat = isSidebarCollapsed ? 160 : 80
            let usable = max(260, floor(detailWidth - margin))
            guard abs(usable - lastReportedWidth) >= 1 else { return }
            lastReportedWidth = usable
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onAvailableWidthChange?(self.lastReportedWidth)
            }
        }
    }
}

/// Local keyboard monitor for native macOS Finder & KDE Dolphin shortcuts:
/// - Spacebar (`keyCode == 49`): toggles Quick Look (`Vista rápida`)
/// - Arrow keys (`←`, `→`, `↑`, `↓`): navigates items in Icon/Compact views and while Quick Look is open
/// - Return (`keyCode == 36`): renames the selected item(s)
/// - Printable characters: type-ahead jump selection (`KItemListController::typeAheadUsed`)
private struct QuickLookKeyMonitorView: NSViewRepresentable {
    let onSpacebar: () -> Bool
    let onArrowDirection: (ArrowDirection, Bool) -> Bool
    let onReturnRename: () -> Bool
    var onTypeAheadCharacters: ((String) -> Bool)? = nil

    func makeNSView(context: Context) -> MonitorNSView {
        let view = MonitorNSView()
        view.onSpacebar = onSpacebar
        view.onArrowDirection = onArrowDirection
        view.onReturnRename = onReturnRename
        view.onTypeAheadCharacters = onTypeAheadCharacters
        return view
    }

    func updateNSView(_ nsView: MonitorNSView, context: Context) {
        nsView.onSpacebar = onSpacebar
        nsView.onArrowDirection = onArrowDirection
        nsView.onReturnRename = onReturnRename
        nsView.onTypeAheadCharacters = onTypeAheadCharacters
    }

    final class MonitorNSView: NSView {
        var onSpacebar: (() -> Bool)?
        var onArrowDirection: ((ArrowDirection, Bool) -> Bool)?
        var onReturnRename: (() -> Bool)?
        var onTypeAheadCharacters: ((String) -> Bool)?
        nonisolated(unsafe) private var keyMonitor: Any?

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            guard window != nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let keyCode = event.keyCode
                let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let chars = event.charactersIgnoringModifiers ?? ""
                let consumed = MainActor.assumeIsolated {
                    self.handleKeyCode(keyCode, rawModifierFlags: rawFlags, characters: chars)
                }
                return consumed ? nil : event
            }
        }

        @MainActor
        private func handleKeyCode(_ keyCode: UInt16, rawModifierFlags: UInt, characters: String) -> Bool {
            if let firstResponder = NSApp?.keyWindow?.firstResponder {
                if firstResponder is NSText {
                    return false
                }
                if String(describing: type(of: firstResponder)).contains("Terminal") {
                    return false
                }
            }
            if let keyWin = NSApp?.keyWindow, !keyWin.sheets.isEmpty {
                return false
            }
            let modifiers = NSEvent.ModifierFlags(rawValue: rawModifierFlags)
            let hasCommandOrControlOrOption = !modifiers.intersection([.command, .control, .option]).isEmpty
            guard !hasCommandOrControlOrOption else { return false }

            switch keyCode {
            case 49: // Spacebar
                return onSpacebar?() == true
            case 53: // Escape closes Quick Look if visible
                if QuickLookPreviewController.shared.isVisible {
                    QuickLookPreviewController.shared.close()
                    return true
                }
                return false
            case 123: // Left arrow (←)
                return onArrowDirection?(.left, modifiers.contains(.shift)) == true
            case 124: // Right arrow (→)
                return onArrowDirection?(.right, modifiers.contains(.shift)) == true
            case 125: // Down arrow (↓)
                return onArrowDirection?(.down, modifiers.contains(.shift)) == true
            case 126: // Up arrow (↑)
                return onArrowDirection?(.up, modifiers.contains(.shift)) == true
            case 36: // Return (Finder-style rename)
                return onReturnRename?() == true
            default:
                // Printable alphanumeric / punctuation characters for type-ahead selection
                if let scalar = characters.unicodeScalars.first,
                   characters.count == 1,
                   (CharacterSet.alphanumerics.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar)) {
                    return onTypeAheadCharacters?(characters) == true
                }
                return false
            }
        }
    }
}
