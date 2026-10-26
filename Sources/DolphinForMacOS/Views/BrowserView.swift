import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel

    @State private var pendingDelete: FileItem?
    @State private var showsDeleteConfirmation = false
    @State private var showsRenamePrompt = false
    @State private var showsNewFolderPrompt = false
    @State private var showsEmptyTrashConfirmation = false
    @State private var nameInput = ""
    @State private var terminalError: String?

    private var isBrowsingTrash: Bool {
        viewModel.isBrowsingTrash
    }

    private var selectedID: Binding<FileItem.ID?> {
        Binding(
            get: { viewModel.selectedItem?.id },
            set: { id in
                let candidates = viewModel.items + viewModel.searchResults
                viewModel.select(candidates.first { $0.id == id })
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BreadcrumbView(url: viewModel.currentURL, onNavigate: viewModel.navigate)

                Spacer()

                Button {
                    do {
                        try TerminalLauncher().openTerminal(at: viewModel.currentURL)
                    } catch {
                        terminalError = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "terminal")
                }

                Button {
                    nameInput = "Nueva carpeta"
                    showsNewFolderPrompt = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }

                Button {
                    nameInput = viewModel.selectedItem?.name ?? ""
                    showsRenamePrompt = true
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(viewModel.selectedItem == nil)

                Button {
                    pendingDelete = viewModel.selectedItem
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.selectedItem == nil)

                if isBrowsingTrash {
                    Button {
                        viewModel.restoreSelected()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(viewModel.selectedItem == nil)

                    Button {
                        showsEmptyTrashConfirmation = true
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                }

                if viewModel.viewProperties.mode == .icons {
                    Slider(
                        value: Binding(
                            get: { viewModel.viewProperties.zoomLevel },
                            set: { viewModel.setZoomLevel($0) }
                        ),
                        in: 0.5...2.0
                    )
                    .frame(width: 100)
                }

                Menu {
                    ForEach([SortField.name, .size, .modificationDate], id: \.self) { field in
                        Button(sortLabel(field)) {
                            viewModel.setSort(field: field, ascending: viewModel.viewProperties.ascending)
                        }
                    }
                    Divider()
                    Button(viewModel.viewProperties.ascending ? "Descendente" : "Ascendente") {
                        viewModel.setSort(field: viewModel.viewProperties.sortField, ascending: !viewModel.viewProperties.ascending)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }

                ViewModePicker(mode: Binding(
                    get: { viewModel.viewProperties.mode },
                    set: { viewModel.setViewMode($0) }
                ))
            }
            .padding(8)

            Divider()

            HStack {
                FilterBarView(text: Binding(
                    get: { viewModel.filterText },
                    set: { viewModel.filterText = $0 }
                ))
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar en subcarpetas...", text: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.searchQuery = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .task(id: viewModel.searchQuery) {
                        // ponytail: debounce nada más — la caminata sigue siendo
                        // síncrona en el main actor por llamada; si una carpeta
                        // enorme sigue sintiéndose lenta, el próximo paso es
                        // moverla a un actor de background con cancelación real.
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        viewModel.performSearch()
                    }
                }
                .padding(6)
            }

            Divider()

            let onDelete: (FileItem) -> Void = { item in
                pendingDelete = item
                showsDeleteConfirmation = true
            }

            if let error = viewModel.error {
                switch error {
                case .permissionDenied(let url):
                    PermissionDeniedView(url: url)
                case .notFound(let url):
                    Text("No se encontró \(url.path)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .other(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !viewModel.searchQuery.isEmpty {
                if viewModel.searchResults.isEmpty {
                    Text("Sin resultados")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileListView(
                        items: viewModel.searchResults,
                        selectedID: selectedID,
                        gitStatuses: [:], // los resultados vienen de carpetas distintas; gitStatuses es solo de currentURL
                        onOpen: { item in viewModel.navigate(to: item.url.deletingLastPathComponent()) },
                        onDelete: onDelete
                    )
                }
            } else if viewModel.filteredItems.isEmpty && !viewModel.filterText.isEmpty {
                Text("Sin resultados")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let onOpen: (FileItem) -> Void = { item in
                    if item.isDirectory {
                        viewModel.navigate(to: item.url)
                    }
                }
                switch viewModel.viewProperties.mode {
                case .icons:
                    IconGridView(
                        items: viewModel.filteredItems,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selectedItem: viewModel.selectedItem,
                        onSelect: viewModel.select,
                        onOpen: onOpen,
                        onDelete: onDelete,
                        gitStatuses: viewModel.gitStatuses
                    )
                case .list:
                    FileListView(
                        items: viewModel.filteredItems,
                        selectedID: selectedID,
                        gitStatuses: viewModel.gitStatuses,
                        onOpen: onOpen,
                        onDelete: onDelete
                    )
                case .details:
                    DetailsListView(
                        items: viewModel.filteredItems,
                        selectedID: selectedID,
                        gitStatuses: viewModel.gitStatuses,
                        onOpen: onOpen,
                        onDelete: onDelete
                    )
                }
            }

            Divider()

            StatusBarView(
                itemCount: viewModel.filteredItems.count,
                totalCount: viewModel.items.count,
                availableCapacity: VolumeInfoProvider().availableCapacity(for: viewModel.currentURL)
            )
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
        .alert("Renombrar", isPresented: $showsRenamePrompt) {
            TextField("Nombre", text: $nameInput)
            Button("Renombrar") { viewModel.renameSelected(to: nameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Nueva carpeta", isPresented: $showsNewFolderPrompt) {
            TextField("Nombre", text: $nameInput)
            Button("Crear") { viewModel.createFolder(named: nameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("¿Vaciar la papelera?", isPresented: $showsEmptyTrashConfirmation) {
            Button("Vaciar", role: .destructive) { viewModel.emptyTrash() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esto borra el contenido de la papelera de forma permanente. No se puede deshacer.")
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
        .alert(
            "No se pudo abrir la Terminal",
            isPresented: Binding(
                get: { terminalError != nil },
                set: { if !$0 { terminalError = nil } }
            )
        ) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError ?? "")
        }
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

    private func sortLabel(_ field: SortField) -> String {
        switch field {
        case .name: return "Nombre"
        case .size: return "Tamaño"
        case .modificationDate: return "Fecha"
        }
    }
}
