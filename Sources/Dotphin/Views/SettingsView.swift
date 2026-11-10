import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable private var model = AppSettingsModel.shared

    var body: some View {
        TabView {
            Form {
                Section("Ubicación de inicio") {
                    Picker("Inicio", selection: $model.settings.startupLocation) {
                        Text("Carpeta de inicio").tag(StartupLocation.home)
                        Text("Escritorio").tag(StartupLocation.desktop)
                        Text("Carpeta personalizada").tag(StartupLocation.custom)
                    }
                    if model.settings.startupLocation == .custom {
                        HStack {
                            Text(model.settings.customStartupPath ?? "Ninguna carpeta elegida")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button("Elegir carpeta…") {
                                chooseCustomStartupFolder()
                            }
                        }
                    }
                    Toggle("Iniciar ventanas o pestañas en vista dividida (F3)", isOn: $model.settings.startInSplitView)
                }

                Section("Pestañas y barra de ubicaciones") {
                    Toggle("Recordar carpetas y pestañas abiertas de la sesión anterior", isOn: $model.settings.rememberOpenedTabs)
                    Toggle("Mostrar siempre la barra de pestañas", isOn: $model.settings.alwaysShowTabBar)
                    Toggle("Abrir nuevas pestañas al final de la barra", isOn: $model.settings.openNewTabAfterLastTab)
                    Toggle("Mostrar ruta editable como texto por defecto", isOn: $model.settings.editableLocationByDefault)
                    Toggle("Mostrar ruta completa en la barra de título", isOn: $model.settings.showFullPathInTitlebar)
                    Toggle("Mostrar barra rápida para pegar tras copiar o cortar", isOn: $model.settings.showPasteBarAfterCopying)
                }

                Section("Barra de estado") {
                    Picker("Estilo de barra de estado", selection: $model.settings.statusBarMode) {
                        ForEach(StatusBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle("Mostrar deslizador de zoom en la barra de estado", isOn: $model.settings.showZoomSliderInStatusBar)
                        .disabled(model.settings.statusBarMode != .fullWidth)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Comportamiento de visualización") {
                    Picker("Vista por defecto", selection: $model.settings.defaultViewMode) {
                        Text("Iconos").tag(ViewMode.icons)
                        Text("Compacta").tag(ViewMode.compact)
                        Text("Lista").tag(ViewMode.list)
                        Text("Detalles").tag(ViewMode.details)
                    }
                    Toggle("Mostrar archivos ocultos por defecto", isOn: $model.settings.showsHiddenFiles)
                    Toggle("Carpetas desplegables en modo Detalles", isOn: $model.settings.expandableFoldersInDetails)
                    Toggle("Abrir archivos comprimidos como carpetas (BrowseThroughArchives)", isOn: $model.settings.browseThroughArchives)
                }

                Section("Presentación de contenido (ContentDisplay)") {
                    Picker("Tamaño de carpetas en listas", selection: $model.settings.directorySizeMode) {
                        ForEach(DirectorySizeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Formato de permisos POSIX", selection: $model.settings.permissionsFormat) {
                        ForEach(PermissionsDisplayFormat.allCases) { fmt in
                            Text(fmt.title).tag(fmt)
                        }
                    }
                    Toggle("Usar fechas relativas cortas (Hoy, Ayer…)", isOn: $model.settings.useRelativeDates)
                }

                Section("Ordenación de archivos (SortingChoice)") {
                    Picker("Orden de nombres", selection: $model.settings.sortingChoice) {
                        ForEach(SortingChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Modos de vista", systemImage: "square.grid.2x2")
            }

            Form {
                Section("Confirmaciones de operaciones destructivas") {
                    Toggle("Pedir confirmación antes de mover archivos a la Papelera", isOn: $model.settings.confirmMoveToTrash)
                    Toggle("Pedir confirmación antes de vaciar la Papelera", isOn: $model.settings.confirmEmptyTrash)
                    Toggle("Pedir confirmación antes de eliminar permanentemente (⇧⌘⌫)", isOn: $model.settings.confirmPermanentDelete)
                }

                Section("Menú contextual") {
                    Toggle("Mostrar comando «Eliminar permanentemente» en el menú contextual", isOn: $model.settings.showPermanentDeleteCommand)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Confirmaciones", systemImage: "checkmark.shield")
            }
        }
        .frame(width: 720, height: 500)
    }

    private func chooseCustomStartupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.settings.customStartupPath = url.path
        }
    }
}
