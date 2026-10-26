import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel

    @State private var showsDeleteConfirmation = false
    @State private var showsRenamePrompt = false
    @State private var showsNewFolderPrompt = false
    @State private var nameInput = ""

    private var selectedID: Binding<FileItem.ID?> {
        Binding(
            get: { viewModel.selectedItem?.id },
            set: { id in viewModel.select(viewModel.items.first { $0.id == id }) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BreadcrumbView(url: viewModel.currentURL, onNavigate: viewModel.navigate)

                Spacer()

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
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.selectedItem == nil)

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

            FilterBarView(text: Binding(
                get: { viewModel.filterText },
                set: { viewModel.filterText = $0 }
            ))

            Divider()

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
                let onDelete: (FileItem) -> Void = { item in
                    viewModel.select(item)
                    showsDeleteConfirmation = true
                }
                switch viewModel.viewProperties.mode {
                case .icons:
                    IconGridView(
                        items: viewModel.filteredItems,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selectedItem: viewModel.selectedItem,
                        onSelect: viewModel.select,
                        onOpen: onOpen,
                        onDelete: onDelete
                    )
                case .list:
                    FileListView(
                        items: viewModel.filteredItems,
                        selectedID: selectedID,
                        onOpen: onOpen,
                        onDelete: onDelete
                    )
                case .details:
                    DetailsListView(
                        items: viewModel.filteredItems,
                        selectedID: selectedID,
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
        .alert("¿Eliminar este ítem?", isPresented: $showsDeleteConfirmation) {
            Button("Eliminar", role: .destructive) { viewModel.deleteSelected() }
            Button("Cancelar", role: .cancel) {}
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
