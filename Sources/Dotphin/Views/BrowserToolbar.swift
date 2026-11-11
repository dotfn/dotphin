import SwiftUI

/// Toolbar nativa de la ventana: ítems de `NSToolbar` de verdad.
///
/// El sistema se ocupa de agruparlos, de mandar al menú "»" los que no entran
/// y de la personalización (clic derecho → "Personalizar barra de
/// herramientas…", que además recuerda el orden elegido). Reemplaza a la
/// toolbar dibujada a mano dentro de un único ítem.
struct BrowserToolbar: CustomizableToolbarContent {
    let viewModel: BrowserViewModel?
    let onNewFolder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onEmptyTrash: () -> Void
    let onToggleTerminal: () -> Void
    let onToggleSplit: () -> Void
    let onNewTab: () -> Void
    let onToggleInfoPanel: () -> Void

    private var isBrowsingTrash: Bool {
        viewModel?.isBrowsingTrash ?? false
    }

    private var hasSelection: Bool {
        !(viewModel?.selectedIDs.isEmpty ?? true)
    }

    var body: some CustomizableToolbarContent {
        navigationItems
        viewItems
        // Los espaciadores separan los grupos: cada tramo comparte su fondo de vidrio.
        ToolbarSpacer(.fixed)
        fileItems
        trashItems
        ToolbarSpacer(.fixed)
        windowItems
        // Empuja el buscador al borde derecho. Además SwiftUI descarta la
        // personalización guardada si tiene más copias de un espaciador que la
        // barra por defecto: con este, se pueden usar dos espacios flexibles.
        ToolbarSpacer(.flexible)
    }

    @ToolbarContentBuilder
    private var navigationItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarActionItem.back.rawValue, placement: .navigation) {
            button(.back) { viewModel?.goBack() }
                .disabled(!(viewModel?.canGoBack ?? false))
        }
        ToolbarItem(id: ToolbarActionItem.forward.rawValue, placement: .navigation) {
            button(.forward) { viewModel?.goForward() }
                .disabled(!(viewModel?.canGoForward ?? false))
        }
        ToolbarItem(id: ToolbarActionItem.up.rawValue, placement: .navigation) {
            button(.up) { viewModel?.goUp() }
                .disabled(viewModel == nil || viewModel?.currentURL.path == "/")
        }
    }

    @ToolbarContentBuilder
    private var viewItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarActionItem.viewMode.rawValue) {
            Picker(
                ToolbarActionItem.viewMode.title,
                selection: Binding(
                    get: { viewModel?.viewProperties.mode ?? .list },
                    set: { viewModel?.setViewMode($0) }
                )
            ) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                        .help(mode.title)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .disabled(viewModel == nil)
        }
        ToolbarItem(id: ToolbarActionItem.sort.rawValue) {
            sortMenu
        }
    }

    @ToolbarContentBuilder
    private var fileItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarActionItem.newFolder.rawValue) {
            button(.newFolder, action: onNewFolder)
                .disabled(viewModel == nil || isBrowsingTrash)
        }
        ToolbarItem(id: ToolbarActionItem.rename.rawValue) {
            button(.rename, action: onRename)
                .disabled(!hasSelection)
        }
        ToolbarItem(id: ToolbarActionItem.delete.rawValue) {
            button(.delete, action: onDelete)
                .disabled(!hasSelection)
        }
        // Menú Compartir del sistema (AirDrop, Mail, Mensajes…).
        ToolbarItem(id: "share") {
            ShareLink(items: viewModel?.selectedItems.map(\.url) ?? []) {
                Label(String(localized: "Compartir", bundle: #bundle), systemImage: "square.and.arrow.up")
            }
            .help(String(localized: "Compartir", bundle: #bundle))
            .disabled(!hasSelection)
        }
    }

    /// Solo aparecen mientras se navega la Papelera.
    @ToolbarContentBuilder
    private var trashItems: some CustomizableToolbarContent {
        ToolbarItem(id: "restoreFromTrash") {
            Button {
                viewModel?.restoreSelected()
            } label: {
                Label(String(localized: "Restaurar", bundle: #bundle), systemImage: "arrow.uturn.backward")
            }
            .help(String(localized: "Restaurar", bundle: #bundle))
            .disabled(viewModel?.selectedItem == nil)
        }
        .hidden(!isBrowsingTrash)
        ToolbarItem(id: "emptyTrash") {
            Button(action: onEmptyTrash) {
                Label(String(localized: "Vaciar", bundle: #bundle), systemImage: "trash.slash")
            }
            .help(String(localized: "Vaciar la papelera", bundle: #bundle))
        }
        .hidden(!isBrowsingTrash)
    }

    @ToolbarContentBuilder
    private var windowItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarActionItem.split.rawValue) {
            button(.split, action: onToggleSplit)
        }
        ToolbarItem(id: ToolbarActionItem.newTab.rawValue) {
            button(.newTab, action: onNewTab)
        }
        ToolbarItem(id: ToolbarActionItem.terminal.rawValue) {
            button(.terminal, action: onToggleTerminal)
        }
        ToolbarItem(id: ToolbarActionItem.infoPanel.rawValue) {
            button(.infoPanel, action: onToggleInfoPanel)
        }
    }

    private func button(_ item: ToolbarActionItem, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(item.title, systemImage: item.systemImage)
        }
        .help(item.title)
    }

    /// Menú "Ordenar" con `Picker`s de SwiftUI (antes un `NSMenu` armado a mano).
    private var sortMenu: some View {
        Menu {
            Picker(
                String(localized: "Ordenar por", bundle: #bundle),
                selection: Binding(
                    get: { viewModel?.viewProperties.sortField ?? .name },
                    set: { field in viewModel?.setSort(field: field, ascending: field.defaultAscending) }
                )
            ) {
                ForEach(SortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            .pickerStyle(.inline)

            Picker(
                String(localized: "Dirección", bundle: #bundle),
                selection: Binding(
                    get: { viewModel?.viewProperties.ascending ?? true },
                    set: { ascending in
                        guard let viewModel else { return }
                        viewModel.setSort(field: viewModel.viewProperties.sortField, ascending: ascending)
                    }
                )
            ) {
                Label(String(localized: "Ascendente", bundle: #bundle), systemImage: "arrow.up").tag(true)
                Label(String(localized: "Descendente", bundle: #bundle), systemImage: "arrow.down").tag(false)
            }
            .pickerStyle(.inline)

            Toggle(
                String(localized: "Mostrar en grupos", bundle: #bundle),
                isOn: Binding(
                    get: { viewModel?.viewProperties.showInGroups ?? false },
                    set: { _ in viewModel?.toggleShowInGroups() }
                )
            )
        } label: {
            Label(ToolbarActionItem.sort.title, systemImage: ToolbarActionItem.sort.systemImage)
        }
        .help(String(localized: "Ordenar", bundle: #bundle))
        .disabled(viewModel == nil)
    }
}
