import Foundation
import Observation

/// Estado del árbol "Carpetas" del panel lateral: qué carpetas están
/// desplegadas y sus subcarpetas, por URL.
///
/// Vive fuera de las filas a propósito. Con `@State` en cada fila, SwiftUI
/// descartaba el estado de las filas hijas al plegar un padre, pero el
/// `NSOutlineView` seguía recordándolas desplegadas; al plegar o desplegar de
/// nuevo, SwiftUI pedía una fila que ya no tenía y abortaba
/// (`ViewListTree.visitItem`). Además las subcarpetas se leen antes de marcar
/// la carpeta como desplegada, así la lista nunca cambia a mitad de la expansión.
@MainActor
@Observable
final class FolderTreeModel {
    /// Profundidad máxima (desde la raíz) que se despliega sola para mostrar la carpeta actual.
    static let maxRevealDepth = 5

    private(set) var expanded: Set<URL> = []
    private var subdirectories: [URL: [URL]] = [:]
    private(set) var showsHiddenFiles = false

    static func key(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path)
    }

    func isExpanded(_ url: URL) -> Bool {
        expanded.contains(Self.key(url))
    }

    func children(of url: URL) -> [URL]? {
        subdirectories[Self.key(url)]
    }

    func setExpanded(_ isExpanded: Bool, for url: URL) {
        let key = Self.key(url)
        if isExpanded {
            load(key)
            expanded.insert(key)
        } else {
            expanded.remove(key)
        }
    }

    /// Despliega la raíz y las carpetas que llevan hasta `current`, sin desplegar `current`.
    func reveal(_ current: URL, under root: URL) {
        let rootKey = Self.key(root)
        let rootComponents = rootKey.pathComponents
        let targetComponents = Self.key(current).pathComponents
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents
        else { return }

        var ancestor = rootKey
        let between = targetComponents.dropFirst(rootComponents.count).dropLast()
        var chain = [rootKey]
        for component in between {
            ancestor = ancestor.appendingPathComponent(component)
            chain.append(ancestor)
        }
        for key in chain.prefix(Self.maxRevealDepth) where !expanded.contains(key) {
            load(key)
            expanded.insert(key)
        }
    }

    func setShowsHiddenFiles(_ showsHidden: Bool) {
        guard showsHidden != showsHiddenFiles else { return }
        showsHiddenFiles = showsHidden
        // Las plegadas se vuelven a leer al desplegarlas.
        subdirectories = subdirectories.filter { expanded.contains($0.key) }
        for key in subdirectories.keys {
            load(key)
        }
    }

    private func load(_ key: URL) {
        subdirectories[key] = FolderTreeProvider(showsHiddenFiles: showsHiddenFiles)
            .subdirectories(of: key)
            .map(Self.key)
    }
}
