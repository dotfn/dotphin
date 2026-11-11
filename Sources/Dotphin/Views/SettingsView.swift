import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable private var model = AppSettingsModel.shared

    var body: some View {
        TabView {
            Form {
                Section(String(localized: "Ubicación de inicio", bundle: #bundle)) {
                    Picker(String(localized: "Inicio", bundle: #bundle), selection: $model.settings.startupLocation) {
                        Text(String(localized: "Carpeta de inicio", bundle: #bundle)).tag(StartupLocation.home)
                        Text(String(localized: "Escritorio", bundle: #bundle)).tag(StartupLocation.desktop)
                        Text(String(localized: "Carpeta personalizada", bundle: #bundle)).tag(StartupLocation.custom)
                    }
                    if model.settings.startupLocation == .custom {
                        HStack {
                            Text(model.settings.customStartupPath ?? String(localized: "Ninguna carpeta elegida", bundle: #bundle))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button(String(localized: "Elegir carpeta…", bundle: #bundle)) {
                                chooseCustomStartupFolder()
                            }
                        }
                    }
                    Toggle(String(localized: "Iniciar ventanas o pestañas en vista dividida (F3)", bundle: #bundle), isOn: $model.settings.startInSplitView)
                }

                Section(String(localized: "Pestañas y barra de ubicaciones", bundle: #bundle)) {
                    Toggle(String(localized: "Recordar carpetas y pestañas abiertas de la sesión anterior", bundle: #bundle), isOn: $model.settings.rememberOpenedTabs)
                    Toggle(String(localized: "Mostrar siempre la barra de pestañas", bundle: #bundle), isOn: $model.settings.alwaysShowTabBar)
                    Toggle(String(localized: "Abrir nuevas pestañas al final de la barra", bundle: #bundle), isOn: $model.settings.openNewTabAfterLastTab)
                    Toggle(String(localized: "Mostrar ruta editable como texto por defecto", bundle: #bundle), isOn: $model.settings.editableLocationByDefault)
                    Toggle(String(localized: "Mostrar ruta completa en la barra de título", bundle: #bundle), isOn: $model.settings.showFullPathInTitlebar)
                    Toggle(String(localized: "Mostrar barra rápida para pegar tras copiar o cortar", bundle: #bundle), isOn: $model.settings.showPasteBarAfterCopying)
                }

                Section(String(localized: "Barra de estado", bundle: #bundle)) {
                    Picker(String(localized: "Estilo de barra de estado", bundle: #bundle), selection: $model.settings.statusBarMode) {
                        ForEach(StatusBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle(String(localized: "Mostrar deslizador de zoom en la barra de estado", bundle: #bundle), isOn: $model.settings.showZoomSliderInStatusBar)
                        .disabled(model.settings.statusBarMode != .fullWidth)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label(String(localized: "General", bundle: #bundle), systemImage: "gearshape")
            }

            Form {
                Section(String(localized: "Comportamiento de visualización", bundle: #bundle)) {
                    Picker(String(localized: "Vista por defecto", bundle: #bundle), selection: $model.settings.defaultViewMode) {
                        Text(String(localized: "Iconos", bundle: #bundle)).tag(ViewMode.icons)
                        Text(String(localized: "Compacta", bundle: #bundle)).tag(ViewMode.compact)
                        Text(String(localized: "Lista", bundle: #bundle)).tag(ViewMode.list)
                        Text(String(localized: "Detalles", bundle: #bundle)).tag(ViewMode.details)
                    }
                    Toggle(String(localized: "Mostrar archivos ocultos por defecto", bundle: #bundle), isOn: $model.settings.showsHiddenFiles)
                    Toggle(String(localized: "Carpetas desplegables en modo Detalles", bundle: #bundle), isOn: $model.settings.expandableFoldersInDetails)
                    Toggle(String(localized: "Abrir archivos comprimidos como carpetas (BrowseThroughArchives)", bundle: #bundle), isOn: $model.settings.browseThroughArchives)
                }

                Section(String(localized: "Presentación de contenido (ContentDisplay)", bundle: #bundle)) {
                    Picker(String(localized: "Tamaño de carpetas en listas", bundle: #bundle), selection: $model.settings.directorySizeMode) {
                        ForEach(DirectorySizeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker(String(localized: "Formato de permisos POSIX", bundle: #bundle), selection: $model.settings.permissionsFormat) {
                        ForEach(PermissionsDisplayFormat.allCases) { fmt in
                            Text(fmt.title).tag(fmt)
                        }
                    }
                    Toggle(String(localized: "Usar fechas relativas cortas (Hoy, Ayer…)", bundle: #bundle), isOn: $model.settings.useRelativeDates)
                }

                Section(String(localized: "Ordenación de archivos (SortingChoice)", bundle: #bundle)) {
                    Picker(String(localized: "Orden de nombres", bundle: #bundle), selection: $model.settings.sortingChoice) {
                        ForEach(SortingChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label(String(localized: "Modos de vista", bundle: #bundle), systemImage: "square.grid.2x2")
            }

            Form {
                Section(String(localized: "Confirmaciones de operaciones destructivas", bundle: #bundle)) {
                    Toggle(String(localized: "Pedir confirmación antes de mover archivos a la Papelera", bundle: #bundle), isOn: $model.settings.confirmMoveToTrash)
                    Toggle(String(localized: "Pedir confirmación antes de vaciar la Papelera", bundle: #bundle), isOn: $model.settings.confirmEmptyTrash)
                    Toggle(String(localized: "Pedir confirmación antes de eliminar permanentemente (⇧⌘⌫)", bundle: #bundle), isOn: $model.settings.confirmPermanentDelete)
                }

                Section(String(localized: "Menú contextual", bundle: #bundle)) {
                    Toggle(String(localized: "Mostrar íconos en los menús", bundle: #bundle), isOn: $model.settings.showsMenuIcons)
                    Toggle(String(localized: "Mostrar comando «Eliminar permanentemente» en el menú contextual", bundle: #bundle), isOn: $model.settings.showPermanentDeleteCommand)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label(String(localized: "Confirmaciones", bundle: #bundle), systemImage: "checkmark.shield")
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
