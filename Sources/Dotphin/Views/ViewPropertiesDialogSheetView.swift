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
                    Text(String(localized: "Estilo de visualización de vista", bundle: #bundle))
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
                Section(String(localized: "Propiedades de visualización", bundle: #bundle)) {
                    Picker(String(localized: "Modo de vista:", bundle: #bundle), selection: $draft.mode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }

                    Picker(String(localized: "Ordenar por:", bundle: #bundle), selection: $draft.sortField) {
                        ForEach(SortField.allCases, id: \.self) { field in
                            Text(field.title).tag(field)
                        }
                    }

                    Picker(String(localized: "Dirección de orden:", bundle: #bundle), selection: $draft.ascending) {
                        Text(String(localized: "Ascendente (A → Z / Menor a mayor)", bundle: #bundle)).tag(true)
                        Text(String(localized: "Descendente (Z → A / Mayor a menor)", bundle: #bundle)).tag(false)
                    }

                    HStack {
                        Text(String(localized: "Nivel de zoom:", bundle: #bundle))
                        Slider(value: $draft.zoomLevel, in: 0.5...2.0, step: 0.1)
                        Text(String(localized: "\(Int(round(draft.zoomLevel * 100)))%", bundle: #bundle))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Section(String(localized: "Opciones de vista", bundle: #bundle)) {
                    Toggle(String(localized: "Mostrar en grupos", bundle: #bundle), isOn: $draft.showInGroups)
                    Toggle(String(localized: "Mostrar carpetas primero", bundle: #bundle), isOn: $draft.sortFoldersFirst)
                    Toggle(String(localized: "Mostrar vistas previas (miniaturas)", bundle: #bundle), isOn: $draft.showPreviews)
                    Toggle(String(localized: "Mostrar archivos ocultos", bundle: #bundle), isOn: showsHiddenBinding)
                    Toggle(String(localized: "Mostrar archivos ocultos al final", bundle: #bundle), isOn: $draft.sortHiddenLast)
                }

                Section(String(localized: "Información adicional (columnas en modo Detalles)", bundle: #bundle)) {
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

                Section(String(localized: "Aplicar propiedades de vista a", bundle: #bundle)) {
                    Picker(String(localized: "Alcance:", bundle: #bundle), selection: $scope) {
                        ForEach(ViewPropertiesApplyScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Toggle(String(localized: "Usar estas propiedades como predeterminadas para carpetas nuevas", bundle: #bundle), isOn: $useAsDefault)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Restablecer valores", bundle: #bundle)) {
                    draft = ViewProperties()
                }
                Spacer()
                Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Aplicar", bundle: #bundle)) {
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
