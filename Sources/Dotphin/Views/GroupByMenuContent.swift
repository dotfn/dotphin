import SwiftUI

/// Opciones de "Agrupar por" para menús: una sola elección, marcada con la
/// marca nativa del menú.
struct GroupByPicker: View {
    @Binding var selection: GroupByChoice

    var body: some View {
        // Sin título propio: va dentro de un submenú que ya se llama "Agrupar por".
        Picker(selection: $selection) {
            Text(String(localized: "Ninguno", bundle: #bundle)).tag(GroupByChoice.none)
            Text(String(localized: "Igual que el criterio de ordenación", bundle: #bundle)).tag(GroupByChoice.sameAsSort)
            Divider()
            ForEach(SortField.allCases, id: \.self) { field in
                Text(field.title).tag(GroupByChoice.field(field))
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.inline)
    }
}
