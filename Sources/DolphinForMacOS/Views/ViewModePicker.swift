import SwiftUI

struct ViewModePicker: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker("Vista", selection: $mode) {
            Image(systemName: "square.grid.2x2").tag(ViewMode.icons)
            Image(systemName: "list.bullet").tag(ViewMode.list)
            Image(systemName: "tablecells").tag(ViewMode.details)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 160)
    }
}
