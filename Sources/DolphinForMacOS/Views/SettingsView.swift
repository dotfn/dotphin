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
        }
        .padding(20)
        .frame(width: 350)
        .onChange(of: settings) { _, newValue in
            store.setSettings(newValue)
        }
    }
}
