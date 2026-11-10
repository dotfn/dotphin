import AppKit
import SwiftUI

/// Lo que las vistas de archivos de AppKit (`FileNSTableView`, la grilla)
/// necesitan del panel que las contiene. `BrowserView` lo publica por
/// `Environment` para no enhebrarlo por cada vista intermedia.
struct FileViewInteraction {
    /// Ítem que se está renombrando en línea (`nil` = ninguno).
    var renamingItemID: FileItem.ID?
    /// La vista recibió el foco o un clic: su panel pasa a ser el activo.
    var onActivate: @MainActor () -> Void = {}
    /// Barra espaciadora: Vista rápida.
    var onQuickLook: @MainActor () -> Void = {}
    /// Intro: renombrar la selección (uno en línea, varios por lote).
    var onRequestRename: @MainActor () -> Void = {}
    /// Letra tipeada en la grilla: saltar al ítem que empieza así. (Las
    /// tablas usan la búsqueda al tipear propia de `NSTableView`.)
    var onTypeAhead: @MainActor (String) -> Void = { _ in }
    /// Fin de la edición en línea; `nil` = cancelada.
    var onEndRename: @MainActor (FileItem.ID, String?) -> Void = { _, _ in }
}

private struct FileViewInteractionKey: EnvironmentKey {
    static var defaultValue: FileViewInteraction { FileViewInteraction() }
}

private struct ActiveBrowserPaneKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var fileViewInteraction: FileViewInteraction {
        get { self[FileViewInteractionKey.self] }
        set { self[FileViewInteractionKey.self] = newValue }
    }

    /// `false` en el panel sin foco de una vista dividida.
    var isActiveBrowserPane: Bool {
        get { self[ActiveBrowserPaneKey.self] }
        set { self[ActiveBrowserPaneKey.self] = newValue }
    }
}

/// Marca a las vistas de archivos de AppKit (tabla, grilla): entre ellas el
/// foco se puede pasar sin robárselo a un campo de texto o al panel lateral.
@MainActor
protocol FileViewResponder: AnyObject {}

/// Vista de archivos que puede decirle a Quick Look desde dónde animar.
@MainActor
protocol QuickLookSourceProviding: AnyObject {
    /// Rect en pantalla del ícono de `url`, o `nil` si no está visible.
    func quickLookSourceFrame(for url: URL) -> NSRect?
    /// Flechas apretadas con el panel de Quick Look al frente: la vista mueve
    /// su selección como si las hubiera recibido ella.
    func quickLookForwardKeyDown(_ event: NSEvent)
}
