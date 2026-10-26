import SwiftUI

struct FilterBarView: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField("Filtrar...", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Limpiar filtro")
                .accessibilityLabel("Limpiar filtro")
            }
        }
        .padding(6)
    }
}
