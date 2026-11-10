import Foundation
import Observation

/// Estado visible de una copia o movimiento en curso: avance, ítem actual y,
/// si aparece, el conflicto de nombres que espera respuesta del usuario.
@MainActor
@Observable
final class FileTransferProgress: Identifiable {
    let kind: FileTransferKind
    let totalCount: Int
    let destinationName: String
    private(set) var completedCount = 0
    private(set) var currentName = ""
    /// Recién pasa a `true` si la operación tarda: las instantáneas no
    /// llegan a mostrar la barra de progreso.
    private(set) var isLongRunning = false
    private(set) var pendingConflict: FileConflict?

    @ObservationIgnored private var conflictContinuation: CheckedContinuation<FileConflictDecision, Never>?
    @ObservationIgnored var task: Task<Void, Never>?

    init(kind: FileTransferKind, totalCount: Int, destinationName: String) {
        self.kind = kind
        self.totalCount = totalCount
        self.destinationName = destinationName
    }

    func update(completed: Int, current: URL) {
        completedCount = completed
        currentName = current.lastPathComponent
    }

    func markLongRunning() {
        isLongRunning = true
    }

    /// Suspende la operación hasta que el usuario responda con `resolve`.
    func ask(_ conflict: FileConflict) async -> FileConflictDecision {
        await withCheckedContinuation { continuation in
            conflictContinuation = continuation
            pendingConflict = conflict
        }
    }

    /// Responde el conflicto pendiente. No hace nada si ya fue respondido.
    func resolve(_ resolution: FileConflictResolution, applyToAll: Bool = false) {
        guard let continuation = conflictContinuation else { return }
        conflictContinuation = nil
        pendingConflict = nil
        continuation.resume(returning: FileConflictDecision(resolution: resolution, applyToAll: applyToAll))
    }

    /// Corta la operación después del ítem en curso; lo ya transferido queda.
    func cancel() {
        task?.cancel()
        resolve(.stop)
    }
}
