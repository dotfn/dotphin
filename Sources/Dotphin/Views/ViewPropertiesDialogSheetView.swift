import SwiftUI

/// Mirrors KDE Dolphin's `ViewPropertiesDialog` (`src/settings/viewpropertiesdialog.cpp`):
/// "Adjust View Display Style" dialog for configuring view mode, sorting, grouping, previews,
/// details columns, and applying to current folder, subfolders, or all folders.
struct ViewPropertiesDialogSheetView: View {
    let folderURL: URL
    @State var draft: ViewProperties
    let globalShowsHiddenFiles: Bool
    let onApply: (ViewProperties, ViewPropertiesApplyScope, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scope: ViewPropertiesApplyScope = .currentFolder
    @State private var useAsDefault: Bool = false

    private var showsHiddenBinding: Binding<Bool> {
        Binding(
            get: { draft.showsHiddenFilesOverride ?? globalShowsHiddenFiles },
            set: { draft.showsHiddenFilesOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estilo de visualización de vista")
                        .font(.headline)
                    Text(folderURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Divider()

            Form {
                Section("Propiedades de visualización") {
                    Picker("Modo de vista:", selection: $draft.mode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }

                    Picker("Ordenar por:", selection: $draft.sortField) {
                        ForEach(SortField.allCases, id: \.self) { field in
                            Text(field.title).tag(field)
                        }
                    }

                    Picker("Dirección de orden:", selection: $draft.ascending) {
                        Text("Ascendente (A → Z / Menor a mayor)").tag(true)
                        Text("Descendente (Z → A / Mayor a menor)").tag(false)
                    }

                    HStack {
                        Text("Nivel de zoom:")
                        Slider(value: $draft.zoomLevel, in: 0.5...2.0, step: 0.1)
                        Text("\(Int(round(draft.zoomLevel * 100)))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Section("Opciones de vista") {
                    Toggle("Mostrar en grupos", isOn: $draft.showInGroups)
                    Toggle("Mostrar carpetas primero", isOn: $draft.sortFoldersFirst)
                    Toggle("Mostrar vistas previas (miniaturas)", isOn: $draft.showPreviews)
                    Toggle("Mostrar archivos ocultos", isOn: showsHiddenBinding)
                    Toggle("Mostrar archivos ocultos al final", isOn: $draft.sortHiddenLast)
                }

                Section("Información adicional (columnas en modo Detalles)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 8) {
                        ForEach(DetailsColumn.allCases) { col in
                            Toggle(
                                col.title,
                                isOn: Binding(
                                    get: { draft.visibleDetailsColumns.contains(col) },
                                    set: { isOn in
                                        if isOn {
                                            if !draft.visibleDetailsColumns.contains(col) {
                                                draft.visibleDetailsColumns.append(col)
                                            }
                                        } else if draft.visibleDetailsColumns.count > 1 {
                                            draft.visibleDetailsColumns.removeAll { $0 == col }
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Section("Aplicar propiedades de vista a") {
                    Picker("Alcance:", selection: $scope) {
                        ForEach(ViewPropertiesApplyScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Toggle("Usar estas propiedades como predeterminadas para carpetas nuevas", isOn: $useAsDefault)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Restablecer valores") {
                    draft = ViewProperties()
                }
                Spacer()
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Aplicar") {
                    onApply(draft, scope, useAsDefault)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520, height: 560)
    }
}
