import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettingsStore().settings()
    private let store = AppSettingsStore()

    var body: some View {
        TabView {
            Form {
                Section("Ubicación de inicio") {
                    Picker("Inicio", selection: $settings.startupLocation) {
                        Text("Carpeta de inicio").tag(StartupLocation.home)
                        Text("Escritorio").tag(StartupLocation.desktop)
                        Text("Carpeta personalizada").tag(StartupLocation.custom)
                    }
                    if settings.startupLocation == .custom {
                        HStack {
                            Text(settings.customStartupPath ?? "Ninguna carpeta elegida")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button("Elegir carpeta…") {
                                chooseCustomStartupFolder()
                            }
                        }
                    }
                    Toggle("Iniciar ventanas o pestañas en vista dividida (F3)", isOn: $settings.startInSplitView)
                }

                Section("Pestañas y barra de ubicaciones") {
                    Toggle("Recordar carpetas y pestañas abiertas de la sesión anterior", isOn: $settings.rememberOpenedTabs)
                    Toggle("Mostrar siempre la barra de pestañas", isOn: $settings.alwaysShowTabBar)
                    Toggle("Abrir nuevas pestañas al final de la barra", isOn: $settings.openNewTabAfterLastTab)
                    Toggle("Mostrar ruta editable como texto por defecto", isOn: $settings.editableLocationByDefault)
                    Toggle("Mostrar ruta completa en la barra de título", isOn: $settings.showFullPathInTitlebar)
                    Toggle("Mostrar barra rápida para pegar tras copiar o cortar", isOn: $settings.showPasteBarAfterCopying)
                }

                Section("Barra de estado") {
                    Picker("Estilo de barra de estado", selection: $settings.statusBarMode) {
                        ForEach(StatusBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle("Mostrar deslizador de zoom en la barra de estado", isOn: $settings.showZoomSliderInStatusBar)
                        .disabled(settings.statusBarMode != .fullWidth)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Comportamiento de visualización") {
                    Picker("Vista por defecto", selection: $settings.defaultViewMode) {
                        Text("Iconos").tag(ViewMode.icons)
                        Text("Compacta").tag(ViewMode.compact)
                        Text("Lista").tag(ViewMode.list)
                        Text("Detalles").tag(ViewMode.details)
                    }
                    Toggle("Mostrar archivos ocultos por defecto", isOn: $settings.showsHiddenFiles)
                    Toggle("Carpetas desplegables en modo Detalles", isOn: $settings.expandableFoldersInDetails)
                    Toggle("Abrir archivos comprimidos como carpetas (BrowseThroughArchives)", isOn: $settings.browseThroughArchives)
                }

                Section("Presentación de contenido (ContentDisplay)") {
                    Picker("Tamaño de carpetas en listas", selection: $settings.directorySizeMode) {
                        ForEach(DirectorySizeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Formato de permisos POSIX", selection: $settings.permissionsFormat) {
                        ForEach(PermissionsDisplayFormat.allCases) { fmt in
                            Text(fmt.title).tag(fmt)
                        }
                    }
                    Toggle("Usar fechas relativas cortas (Hoy, Ayer…)", isOn: $settings.useRelativeDates)
                }

                Section("Ordenación de archivos (SortingChoice)") {
                    Picker("Orden de nombres", selection: $settings.sortingChoice) {
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
                    Toggle("Pedir confirmación antes de mover archivos a la Papelera", isOn: $settings.confirmMoveToTrash)
                    Toggle("Pedir confirmación antes de vaciar la Papelera", isOn: $settings.confirmEmptyTrash)
                    Toggle("Pedir confirmación antes de eliminar permanentemente (⇧⌘⌫)", isOn: $settings.confirmPermanentDelete)
                }

                Section("Menú contextual") {
                    Toggle("Mostrar comando «Eliminar permanentemente» en el menú contextual", isOn: $settings.showPermanentDeleteCommand)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Confirmaciones", systemImage: "checkmark.shield")
            }

            ToolbarConfigurationEditorView(settings: $settings)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem {
                    Label("Barra de herramientas", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 720, height: 500)
        .onChange(of: settings) { _, newValue in
            store.setSettings(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let latest = store.settings()
            if latest != settings {
                settings = latest
            }
        }
    }

    private func chooseCustomStartupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            settings.customStartupPath = url.path
        }
    }
}
