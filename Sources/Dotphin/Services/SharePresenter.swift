import AppKit

/// Dónde abrir el panel de Compartir: junto al ícono del archivo que se tocó,
/// apuntándolo, como hace Finder. Lo arma la vista que muestra el menú contextual.
@MainActor
final class ShareAnchor {
    weak var view: NSView?
    let rect: NSRect

    init(view: NSView, rect: NSRect) {
        self.view = view
        self.rect = rect
    }

    /// El ícono de la fila si la celda lo tiene a la vista; si no, el comienzo de la fila.
    static func forRow(_ row: Int, in tableView: NSTableView) -> ShareAnchor? {
        guard row >= 0, row < tableView.numberOfRows else { return nil }
        if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false),
           let icon = firstImageView(in: cell), !icon.isHidden {
            return ShareAnchor(view: tableView, rect: icon.convert(icon.bounds, to: tableView))
        }
        let rowRect = tableView.rect(ofRow: row)
        return ShareAnchor(view: tableView, rect: NSRect(x: rowRect.minX, y: rowRect.minY, width: rowRect.height, height: rowRect.height))
    }

    private static func firstImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView { return imageView }
        for subview in view.subviews {
            if let found = firstImageView(in: subview) { return found }
        }
        return nil
    }
}

@MainActor
enum SharePresenter {
    /// Panel de Compartir del sistema (AirDrop, Mail, Mensajes…) para `urls`.
    static func share(_ urls: [URL], anchor: ShareAnchor?) {
        guard !urls.isEmpty else { return }
        // El menú contextual todavía se está cerrando: el panel va en el siguiente turno.
        Task { @MainActor in
            let picker = NSSharingServicePicker(items: urls)
            if let anchor, let view = anchor.view, view.window != nil {
                picker.show(relativeTo: anchor.rect, of: view, preferredEdge: .minX)
            } else if let window = NSApp.keyWindow, let content = window.contentView {
                let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                picker.show(relativeTo: NSRect(origin: point, size: .zero), of: content, preferredEdge: .minX)
            }
        }
    }
}
