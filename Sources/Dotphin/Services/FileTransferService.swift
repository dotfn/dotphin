import Foundation

enum FileTransferKind: Sendable {
    case copy
    case move
}

/// Ya hay un ítem con el mismo nombre en el destino.
struct FileConflict: Sendable, Equatable {
    let source: URL
    let existing: URL
}

enum FileConflictResolution: Sendable, Equatable {
    /// Manda el existente a la Papelera y pone el nuevo en su lugar (se puede deshacer).
    case replace
    /// Deja los dos: el nuevo entra con un nombre libre ("a copy.txt").
    case keepBoth
    case skip
    /// Corta la operación; lo ya transferido queda.
    case stop
    /// Sin nadie a quien preguntar: se informa como error de ese ítem.
    case reportError
}

struct FileConflictDecision: Sendable, Equatable {
    var resolution: FileConflictResolution
    /// Usar la misma respuesta para el resto de los conflictos de esta operación.
    var applyToAll = false
}

struct FileTransferResult: Sendable, Equatable {
    /// Pasos reversibles, en orden, para el historial de deshacer.
    var records: [FileOperationRecord] = []
    var createdURLs: [URL] = []
    var failures: [String] = []
    var wasCancelled = false
}

/// Copia o mueve un lote de ítems fuera del main actor, avisando el avance
/// ítem por ítem y preguntando qué hacer cuando el nombre ya existe.
///
/// La cancelación es cooperativa y entre ítems: un archivo que ya se está
/// copiando termina (`FileManager` no deja cortarlo a la mitad).
struct FileTransferService: Sendable {
    private let operations = FileOperationsService()

    @concurrent
    func run(
        _ kind: FileTransferKind,
        sources: [URL],
        into directory: URL,
        onProgress: @Sendable (_ completed: Int, _ current: URL) async -> Void = { _, _ in },
        resolveConflict: @Sendable (FileConflict) async -> FileConflictDecision
    ) async -> FileTransferResult {
        var result = FileTransferResult()
        var rememberedResolution: FileConflictResolution?
        let destinationDirectoryPath = directory.resolvingSymlinksInPath().path

        for (index, source) in sources.enumerated() {
            await onProgress(index, source)
            // Después del aviso: si cancelaron mientras tanto, este ítem ya no se toca.
            if Task.isCancelled {
                result.wasCancelled = true
                break
            }

            let sourceParentPath = source.deletingLastPathComponent().resolvingSymlinksInPath().path
            let staysInPlace = sourceParentPath == destinationDirectoryPath
            // Mover algo a la carpeta donde ya está no hace nada.
            if kind == .move && staysInPlace { continue }

            var destination = directory.appendingPathComponent(source.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    // Copiar en la misma carpeta es "duplicar": nunca hay a quién pisar.
                    var resolution: FileConflictResolution = .keepBoth
                    if !staysInPlace {
                        if let rememberedResolution {
                            resolution = rememberedResolution
                        } else {
                            let decision = await resolveConflict(FileConflict(source: source, existing: destination))
                            resolution = decision.resolution
                            if decision.applyToAll {
                                rememberedResolution = decision.resolution
                            }
                        }
                    }
                    switch resolution {
                    case .skip:
                        continue
                    case .stop:
                        result.wasCancelled = true
                        return result
                    case .reportError:
                        throw FileOperationError.nameAlreadyExists(destination)
                    case .keepBoth:
                        destination = operations.uniqueDestination(for: source.lastPathComponent, in: directory)
                    case .replace:
                        try operations.validateTransfer(of: source, to: destination, kind: kind)
                        if let trashed = try operations.trash(destination) {
                            result.records.append(.trashed(original: destination, trashed: trashed))
                        }
                    }
                }

                switch kind {
                case .copy:
                    try operations.copy(source, to: destination)
                    result.records.append(.copied(source: source, to: destination))
                case .move:
                    try operations.move(source, to: destination)
                    result.records.append(.moved(from: source, to: destination))
                }
                result.createdURLs.append(destination)
            } catch let error as FileOperationError {
                result.failures.append("\(source.lastPathComponent): \(error.message)")
            } catch {
                result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }
}
