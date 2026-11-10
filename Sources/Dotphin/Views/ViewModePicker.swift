import SwiftUI

struct ViewModePicker: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker(String(localized: "Vista", bundle: #bundle), selection: $mode) {
            Image(systemName: "square.grid.2x2")
                .tag(ViewMode.icons)
                .accessibilityLabel(String(localized: "Vista de íconos", bundle: #bundle))
                .help(String(localized: "Vista de íconos", bundle: #bundle))
            Image(systemName: "rectangle.grid.3x2")
                .tag(ViewMode.compact)
                .accessibilityLabel(String(localized: "Vista compacta", bundle: #bundle))
                .help(String(localized: "Vista compacta", bundle: #bundle))
            Image(systemName: "list.bullet")
                .tag(ViewMode.list)
                .accessibilityLabel(String(localized: "Vista de lista", bundle: #bundle))
                .help(String(localized: "Vista de lista", bundle: #bundle))
            Image(systemName: "tablecells")
                .tag(ViewMode.details)
                .accessibilityLabel(String(localized: "Vista de detalles", bundle: #bundle))
                .help(String(localized: "Vista de detalles", bundle: #bundle))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 190)
    }
}
