import SwiftUI

/// Celda de tamaño para listas. Para carpetas el cálculo (contar o sumar el
/// contenido) va en segundo plano: hacerlo en el `body` de cada fila trababa el
/// scroll y la selección en carpetas con muchas subcarpetas o discos lentos.
struct DirectorySizeText: View {
    let item: FileItem
    let directorySizeMode: DirectorySizeMode

    @State private var computedText: String?

    private var formatter: FileMetadataFormatter { FileMetadataFormatter() }

    var body: some View {
        Text(formatter.cachedSizeDisplayText(for: item, directorySizeMode: directorySizeMode) ?? computedText ?? "…")
            .task(id: TaskKey(item: item, mode: directorySizeMode)) {
                guard formatter.cachedSizeDisplayText(for: item, directorySizeMode: directorySizeMode) == nil else { return }
                computedText = nil
                let text = await formatter.computedSizeDisplayText(for: item, directorySizeMode: directorySizeMode)
                guard !Task.isCancelled else { return }
                computedText = text
            }
    }

    private struct TaskKey: Hashable {
        let item: FileItem
        let mode: DirectorySizeMode
    }
}
