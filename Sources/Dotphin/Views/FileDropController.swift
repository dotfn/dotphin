import AppKit

/// Qué hace soltar archivos, con las reglas de Finder:
/// mismo volumen → mover, otro volumen → copiar, ⌥ fuerza copiar y ⌘ fuerza mover.
enum FileDropPolicy {
    /// `sourceMask` es `NSDraggingInfo.draggingSourceOperationMask`, que
    /// AppKit ya ajusta según las teclas: con ⌥ solo queda `.copy`, con ⌘
    /// deja de incluirlo.
    static func transferKind(for urls: [URL], to destination: URL, sourceMask: NSDragOperation) -> FileTransferKind {
        if sourceMask.contains(.copy) && !sourceMask.contains(.move) && !sourceMask.contains(.generic) {
            return .copy
        }
        if !sourceMask.contains(.copy) {
            return .move
        }
        return isSameVolume(urls.first, destination) ? .move : .copy
    }

    static func isSameVolume(_ source: URL?, _ destination: URL) -> Bool {
        guard let source,
              let sourceVolume = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let destinationVolume = try? destination.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return true }
        return sourceVolume.isEqual(destinationVolume)
    }
}

/// Carpetas "con resorte": si un arrastre se queda quieto sobre una carpeta,
/// se abre para poder seguir soltando más adentro.
@MainActor
final class SpringLoadingTimer {
    var delay: Duration = .seconds(1)
    private var hoveredID: URL?
    private var task: Task<Void, Never>?

    /// Llamar en cada validación del arrastre con la carpeta bajo el cursor
    /// (`nil` si no hay). El reloj solo se reinicia cuando cambia la carpeta.
    func hover(_ id: URL?, onSpring: @escaping @MainActor () -> Void) {
        guard id != hoveredID else { return }
        cancel()
        guard let id else { return }
        hoveredID = id
        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            // `hoveredID` queda puesto: mientras el cursor siga sobre la misma
            // carpeta no vuelve a dispararse.
            guard !Task.isCancelled, let self, self.hoveredID == id else { return }
            onSpring()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        hoveredID = nil
    }
}

/// Validación y aceptación de un drop de archivos, compartida por la tabla
/// (Lista, Detalles) y la grilla (Iconos, Compacta).
@MainActor
final class FileDropController {
    enum Target: Equatable {
        /// Dentro de la carpeta que está bajo el cursor.
        case folder(URL)
        /// En la carpeta que se está mostrando.
        case currentDirectory(URL)
    }

    struct Proposal {
        let target: Target
        let kind: FileTransferKind

        var operation: NSDragOperation { kind == .copy ? .copy : .move }
    }

    let springLoading = SpringLoadingTimer()

    /// `nil` = no se puede soltar ahí.
    /// - Parameters:
    ///   - folder: carpeta bajo el cursor, si el drop es "sobre" un ítem.
    ///   - currentURL: carpeta mostrada; `nil` en resultados de búsqueda.
    func proposal(for info: any NSDraggingInfo, folder: FileItem?, currentURL: URL?) -> Proposal? {
        proposal(urls: Self.fileURLs(from: info), sourceMask: info.draggingSourceOperationMask, folder: folder, currentURL: currentURL)
    }

    func proposal(urls: [URL], sourceMask: NSDragOperation, folder: FileItem?, currentURL: URL?) -> Proposal? {
        guard !urls.isEmpty else { return nil }

        // Sobre una carpeta (que no sea una de las arrastradas): ahí.
        if let folder, folder.isDirectory,
           !urls.contains(where: { $0.standardizedFileURL == folder.url.standardizedFileURL }) {
            let kind = FileDropPolicy.transferKind(for: urls, to: folder.url, sourceMask: sourceMask)
            return Proposal(target: .folder(folder.url), kind: kind)
        }

        // En cualquier otro lugar: la carpeta actual.
        guard let currentURL else { return nil }
        let kind = FileDropPolicy.transferKind(for: urls, to: currentURL, sourceMask: sourceMask)
        let alreadyHere = urls.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL == currentURL.standardizedFileURL
        }
        // Mover a donde ya está no hace nada; copiar (⌥) sí: duplica.
        if alreadyHere && kind == .move { return nil }
        return Proposal(target: .currentDirectory(currentURL), kind: kind)
    }

    /// Valida y, si el cursor está sobre una carpeta, arma el resorte.
    func validate(
        _ info: any NSDraggingInfo,
        folder: FileItem?,
        currentURL: URL?,
        onSpringOpen: @escaping @MainActor (FileItem) -> Void
    ) -> Proposal? {
        let proposal = proposal(for: info, folder: folder, currentURL: currentURL)
        if case .folder = proposal?.target, let folder {
            springLoading.hover(folder.url) { onSpringOpen(folder) }
        } else {
            springLoading.hover(nil) {}
        }
        return proposal
    }

    func accept(
        _ info: any NSDraggingInfo,
        folder: FileItem?,
        currentURL: URL?,
        source: String,
        onMove: ([URL], URL) -> Void,
        onCopy: ([URL], URL) -> Void
    ) -> Bool {
        springLoading.cancel()
        let urls = Self.fileURLs(from: info)
        guard let proposal = proposal(for: info, folder: folder, currentURL: currentURL) else { return false }
        let destination: URL
        switch proposal.target {
        case .folder(let url), .currentDirectory(let url): destination = url
        }
        DebugEventLog.log("drop", "\(source): \(proposal.kind == .copy ? "copiar" : "mover") \(DebugEventLog.names(urls)) → \(destination.lastPathComponent)")
        switch proposal.kind {
        case .copy: onCopy(urls, destination)
        case .move: onMove(urls, destination)
        }
        return true
    }

    static func fileURLs(from info: any NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { $0 as? URL }
    }
}
