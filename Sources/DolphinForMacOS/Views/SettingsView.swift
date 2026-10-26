import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettingsStore().settings()
    private let store = AppSettingsStore()

    var body: some View {
        Form {
            Picker("Vista por defecto", selection: $settings.defaultViewMode) {
                Text("Iconos").tag(ViewMode.icons)
                Text("Lista").tag(ViewMode.list)
                Text("Detalles").tag(ViewMode.details)
            }
            Toggle("Mostrar archivos ocultos", isOn: $settings.showsHiddenFiles)

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
        }
        .padding(20)
        .frame(width: 350)
        .onChange(of: settings) { _, newValue in
            store.setSettings(newValue)
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
