import CoreServices
import Foundation

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
        FSEventStreamSetDispatchQueue(stream, .main)
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

    func stop() {
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

    init(watchedPath: String, ignoring: (@MainActor (String) -> Bool)?, handler: @escaping @MainActor () -> Void) {
        self.watchedPath = watchedPath
        self.ignoring = ignoring
        self.handler = handler
    }

    /// Solo interesan las entradas directas de la carpeta observada, no lo que
    /// pasa dentro de sus subcarpetas (FSEvents observa el árbol entero).
    @MainActor
    func handle(events: [(path: String, flags: FSEventStreamEventFlags)]) {
        var changedNames: [String] = []
        for event in events {
            let path = event.path.hasSuffix("/") ? String(event.path.dropLast()) : event.path
            let flags = Int(event.flags)
            if flags & kFSEventStreamEventFlagMustScanSubDirs != 0 {
                // El sistema perdió eventos: hay que releer sin saber qué cambió.
                handler()
                return
            }
            let isDirectory = flags & kFSEventStreamEventFlagItemIsDir != 0
            let addedOrRemoved = flags & (kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed) != 0
            if path == watchedPath {
                // La carpeta misma: solo importa si la borraron o la movieron.
                if addedOrRemoved {
                    handler()
                    return
                }
                continue
            }
            guard (path as NSString).deletingLastPathComponent == watchedPath else { continue }
            // Una subcarpeta "modificada" es un cambio adentro de ella, no de esta lista.
            if isDirectory && !addedOrRemoved { continue }
            changedNames.append((path as NSString).lastPathComponent)
        }
        guard !changedNames.isEmpty else { return }
        if let ignoring, changedNames.allSatisfy(ignoring) { return }
        handler()
    }
}

/// Corre en la cola principal (ver `FSEventStreamSetDispatchQueue`).
private let directoryWatcherCallback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
    guard let info else { return }
    let box = Unmanaged<DirectoryWatcherBox>.fromOpaque(info).takeUnretainedValue()
    let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]) ?? []
    let events = paths.prefix(count).enumerated().map { index, path in
        (path: path, flags: eventFlags[index])
    }
    MainActor.assumeIsolated {
        box.handle(events: events)
    }
}
