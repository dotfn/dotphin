import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel

    @State private var showsInfoPanel = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BreadcrumbView(url: viewModel.currentURL, onNavigate: viewModel.navigate)

                Spacer()

                Button {
                    showsInfoPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
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
            } else {
                let onOpen: (FileItem) -> Void = { item in
                    if item.isDirectory {
                        viewModel.navigate(to: item.url)
                    }
                }
                switch viewModel.viewProperties.mode {
                case .icons:
                    IconGridView(
                        items: viewModel.items,
                        zoomLevel: viewModel.viewProperties.zoomLevel,
                        selectedItem: viewModel.selectedItem,
                        onSelect: viewModel.select,
                        onOpen: onOpen
                    )
                case .list:
                    FileListView(
                        items: viewModel.items,
                        selectedItem: viewModel.selectedItem,
                        onSelect: viewModel.select,
                        onOpen: onOpen
                    )
                case .details:
                    DetailsListView(
                        items: viewModel.items,
                        selectedItem: viewModel.selectedItem,
                        onSelect: viewModel.select,
                        onOpen: onOpen
                    )
                }
            }
        }
        .inspector(isPresented: $showsInfoPanel) {
            InfoPanelView(item: viewModel.selectedItem)
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
