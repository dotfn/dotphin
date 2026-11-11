import SwiftUI

/// "Cambiar ícono…" de la barra lateral: una grilla de símbolos, como el
/// selector de íconos de las listas de Recordatorios.
struct SidebarSymbolPicker: View {
    let current: String
    let defaultSymbol: String
    let onPick: (String?) -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PlacesProvider.symbolChoices, id: \.self) { symbol in
                    Button {
                        onPick(symbol == defaultSymbol ? nil : symbol)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(symbol == current ? Color.white : Color.accentColor)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(symbol == current ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(symbol == current ? .isSelected : [])
                }
            }
            Divider()
            Button(String(localized: "Restablecer", bundle: #bundle)) {
                onPick(nil)
            }
            .disabled(current == defaultSymbol)
        }
        .padding(12)
    }
}
