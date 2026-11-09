import SwiftUI

struct ViewModePicker: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker("Vista", selection: $mode) {
            Image(systemName: "square.grid.2x2")
                .tag(ViewMode.icons)
                .accessibilityLabel("Vista de íconos")
                .help("Vista de íconos")
            Image(systemName: "rectangle.grid.3x2")
                .tag(ViewMode.compact)
                .accessibilityLabel("Vista compacta")
                .help("Vista compacta")
            Image(systemName: "list.bullet")
                .tag(ViewMode.list)
                .accessibilityLabel("Vista de lista")
                .help("Vista de lista")
            Image(systemName: "tablecells")
                .tag(ViewMode.details)
                .accessibilityLabel("Vista de detalles")
                .help("Vista de detalles")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 190)
    }
}
