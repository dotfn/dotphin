import CoreServices
import Foundation
import Synchronization

/// Avisa cuando cambia el contenido de una carpeta (altas, bajas, renombres,
/// archivos modificados), venga el cambio de esta app o de cualquier otra.
///
/// Usa FSEvents, lo mismo que Finder: el sistema agrupa los cambios y avisa
/// por carpeta, sin tener que sondear el disco.
@MainActor
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var box: DirectoryWatcherBox?
    private(set) var watchedURL: URL?

    /// Empieza a observar `url` (y deja de observar la anterior). `onChange`
    /// se llama en el main actor, a lo sumo una vez por tanda de cambios.
    /// `ignoring` recibe el nombre de cada entrada que cambió: si devuelve
    /// `true` para todas (p. ej. archivos ocultos que no se muestran), no se avisa.
    func watch(
        _ url: URL,
        latency: TimeInterval = 0.3,
        ignoring: (@MainActor (String) -> Bool)? = nil,
        onChange: @escaping @MainActor () -> Void
    ) {
        stop()
        let path = Self.realPath(of: url)
        let box = DirectoryWatcherBox(watchedPath: path, ignoring: ignoring, handler: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // Eventos por archivo: hace falta el nombre de lo que cambió para poder
        // ignorar, por ejemplo, un `~/.claude.json` que otra app reescribe sin parar.
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            directoryWatcherCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }
        // Con eventos por archivo, FSEvents avisa de cada escritura en todo el
        // árbol (en la carpeta personal: cachés, navegadores, compilaciones). Se
        // descartan en esta cola; al main actor solo llega lo de esta carpeta.
        FSEventStreamSetDispatchQueue(stream, Self.eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
        self.box = box
        watchedURL = url
    }

    /// FSEvents informa rutas reales (/tmp llega como /private/tmp), y
    /// `resolvingSymlinksInPath()` justamente le saca el /private: hace falta `realpath`.
    private static func realPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static let eventQueue = DispatchQueue(label: "dev.dotfn.dotphin.directory-watcher", qos: .utility)

    func stop() {
        box?.deactivate()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        box = nil
        watchedURL = nil
    }

    isolated deinit {
        stop()
    }
}

/// Lo que recibe el callback de C; `DirectoryWatcher` lo mantiene vivo
/// mientras exista el stream.
private final class DirectoryWatcherBox: Sendable {
    let watchedPath: String
    let ignoring: (@MainActor (String) -> Bool)?
    let handler: @MainActor () -> Void
    /// Un aviso ya encolado hacia el main actor no debe llegar después de `stop()`.
    private let isActive = Mutex(true)

    init(watchedPath: String, ignoring: (@MainActor (String) -> Bool)?, handler: @escaping @MainActor () -> Void) {
        self.watchedPath = watchedPath
        self.ignoring = ignoring
        self.handler = handler
    }

    func deactivate() {
        isActive.withLock { $0 = false }
    }

    private enum Relevance {
        case none
        case reload
        case entries([String])
    }

    /// Corre en la cola del stream. Solo interesan las entradas directas de la
    /// carpeta observada, no lo que pasa dentro de sus subcarpetas (FSEvents
    /// observa el árbol entero).
    func handle(events: [(path: String, flags: FSEventStreamEventFlags)]) {
        let relevance = relevance(of: events)
        if case .none = relevance { return }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                guard isActive.withLock({ $0 }) else { return }
                if case .entries(let names) = relevance, let ignoring, names.allSatisfy(ignoring) {
                    return
                }
                handler()
            }
        }
    }

    private func relevance(of events: [(path: String, flags: FSEventStreamEventFlags)]) -> Relevance {
        var changedNames: [String] = []
        for event in events {
            let path = event.path.hasSuffix("/") ? String(event.path.dropLast()) : event.path
            let flags = Int(event.flags)
            if flags & kFSEventStreamEventFlagMustScanSubDirs != 0 {
                // El sistema perdió eventos: hay que releer sin saber qué cambió.
                return .reload
            }
            let addedOrRemoved = flags & (kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed) != 0
            if path == watchedPath {
                // La carpeta misma: solo importa si la borraron o la movieron.
                if addedOrRemoved { return .reload }
                continue
            }
            guard (path as NSString).deletingLastPathComponent == watchedPath else { continue }
            // Una subcarpeta solo "modificada" es un cambio adentro de ella, no de
            // esta lista; sus etiquetas o su dueño sí se ven acá.
            let isDirectory = flags & kFSEventStreamEventFlagItemIsDir != 0
            let shownDirectoryChange = addedOrRemoved || flags & (kFSEventStreamEventFlagItemXattrMod
                | kFSEventStreamEventFlagItemFinderInfoMod
                | kFSEventStreamEventFlagItemChangeOwner) != 0
            if isDirectory && !shownDirectoryChange { continue }
            changedNames.append((path as NSString).lastPathComponent)
        }
        return changedNames.isEmpty ? .none : .entries(changedNames)
    }
}

/// Corre en `DirectoryWatcher.eventQueue` (ver `FSEventStreamSetDispatchQueue`).
private let directoryWatcherCallback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
    guard let info else { return }
    let box = Unmanaged<DirectoryWatcherBox>.fromOpaque(info).takeUnretainedValue()
    let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]) ?? []
    let events = paths.prefix(count).enumerated().map { index, path in
        (path: path, flags: eventFlags[index])
    }
    box.handle(events: events)
}
