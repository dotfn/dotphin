import AppKit
import Foundation
import Synchronization

/// Registro de eventos para depurar clics, selección, arrastre y teclado sin
/// poder mirar la pantalla. Apagado por defecto; se prende con cualquiera de:
/// - `DOTPHIN_DEBUG_EVENTS=1 swift run Dotphin`
/// - `swift run Dotphin --debug-events`
/// - menú Dotphin → "Registrar eventos de depuración" (queda guardado)
///
/// Cada línea va a stderr (la terminal o la consola de Xcode) y se agrega a
/// `~/Library/Logs/Dotphin/events.log`, que se vacía al iniciar cada sesión.
enum DebugEventLog {
    static let logFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dotphin/events.log")

    private static let defaultsKey = "debugEventsEnabled"

    private struct State {
        var isEnabled = false
        var fileHandle: FileHandle?
        var draggedEventsSinceMouseDown = 0
        let timestampFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    private static let state = Mutex(State())

    static var isEnabled: Bool {
        state.withLock { $0.isEnabled }
    }

    /// Lee el entorno, los argumentos y la preferencia guardada. Se llama una vez al arrancar.
    static func configureFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment["DOTPHIN_DEBUG_EVENTS"]
        let enabled = environment == "1"
            || CommandLine.arguments.contains("--debug-events")
            || UserDefaults.standard.bool(forKey: defaultsKey)
        setEnabled(enabled, persist: false)
    }

    static func setEnabled(_ enabled: Bool, persist: Bool = true) {
        if persist {
            UserDefaults.standard.set(enabled, forKey: defaultsKey)
        }
        state.withLock { state in
            guard state.isEnabled != enabled else { return }
            state.isEnabled = enabled
            if enabled {
                let directory = logFileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
                state.fileHandle = try? FileHandle(forWritingTo: logFileURL)
            } else {
                try? state.fileHandle?.close()
                state.fileHandle = nil
            }
        }
        if enabled {
            log("debug", "registro activado → \(logFileURL.path)")
        }
    }

    static func log(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        // El mensaje se arma FUERA del lock: si su texto vuelve a tomar `state`
        // (p. ej. para formatear una hora), adentro del lock era un deadlock que
        // colgaba el hilo principal en el siguiente log.
        let text = message()
        let now = Date()
        state.withLock { state in
            guard state.isEnabled else { return }
            let line = "[\(state.timestampFormatter.string(from: now))] [\(category)] \(text)\n"
            let data = Data(line.utf8)
            FileHandle.standardError.write(data)
            state.fileHandle?.write(data)
        }
    }

    /// Nombres de archivo en vez de URLs completas, para que el log se lea fácil.
    static func names<S: Sequence>(_ urls: S) -> String where S.Element == URL {
        let list = urls.map(\.lastPathComponent).sorted()
        return list.isEmpty ? "∅" : list.joined(separator: ", ")
    }

    // MARK: - Vigilante del hilo principal

    private static let lastMainHeartbeat = Mutex(Date())
    private nonisolated(unsafe) static var heartbeatTimer: Timer?

    /// Un timer en el main (modo `.common`, así también late durante el bucle
    /// de seguimiento del `NSTableView`) marca un latido cada 50 ms; un hilo
    /// aparte avisa si el latido se atrasa más de 250 ms. Si avisa, el main
    /// estaba de verdad bloqueado haciendo trabajo, no esperando eventos.
    @MainActor
    static func installMainThreadWatchdog() {
        guard heartbeatTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            lastMainHeartbeat.withLock { $0 = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer

        let watchdog = Thread {
            var stallStart: Date?
            var lastReportedSecond = 0
            while true {
                Thread.sleep(forTimeInterval: 0.05)
                guard isEnabled else { continue }
                let last = lastMainHeartbeat.withLock { $0 }
                let silence = Date().timeIntervalSince(last)
                if silence > 0.25 {
                    if stallStart == nil {
                        stallStart = last
                        lastReportedSecond = 0
                    }
                    // Aviso por cada segundo que sigue trabado: si la app se
                    // cuelga y la matan, el log igual muestra que estaba bloqueada.
                    let second = Int(silence)
                    if second > lastReportedSecond {
                        lastReportedSecond = second
                        log("hang", "hilo principal sigue BLOQUEADO hace \(second) s…")
                    }
                } else if let start = stallStart {
                    let millis = Int(Date().timeIntervalSince(start) * 1000)
                    log("hang", "hilo principal estuvo BLOQUEADO ~\(millis) ms")
                    stallStart = nil
                }
            }
        }
        watchdog.name = "Dotphin.DebugEventLog.watchdog"
        watchdog.start()
    }

    /// Modo del run loop actual: `NSEventTrackingRunLoopMode` = dentro de un
    /// bucle de seguimiento (clic sostenido en la tabla, arrastre, menú).
    static var runLoopModeDescription: String {
        guard let mode = RunLoop.current.currentMode else { return "ninguno" }
        return mode == .default ? "default" : mode.rawValue
    }

    /// Mide cuánto tarda `work` y lo registra si el registro está activo.
    static func measure<T>(_ category: String, _ label: @autoclosure () -> String, _ work: () throws -> T) rethrows -> T {
        guard isEnabled else { return try work() }
        let start = Date()
        let result = try work()
        let millis = Int(Date().timeIntervalSince(start) * 1000)
        log(category, "\(label()) tardó \(millis) ms")
        return result
    }

    // MARK: - Eventos crudos de AppKit

    private nonisolated(unsafe) static var eventMonitor: Any?

    /// Observa (sin consumir) mouse y teclado de toda la app: qué vista recibe
    /// cada clic y quién es el first responder en ese momento.
    @MainActor
    static func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .keyDown]
        ) { event in
            guard isEnabled else { return event }
            MainActor.assumeIsolated { describe(event) }
            return event
        }
    }

    @MainActor
    private static func describe(_ event: NSEvent) {
        let point = event.locationInWindow
        let position = "(\(Int(point.x)), \(Int(point.y)))"
        let modifiers = modifierDescription(event.modifierFlags)
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            state.withLock { $0.draggedEventsSinceMouseDown = 0 }
            let button = event.type == .leftMouseDown ? "leftMouseDown" : "rightMouseDown"
            log("mouse", "\(button) en \(position) clicks=\(event.clickCount)\(modifiers) vista=\(hitChain(for: event)) firstResponder=\(firstResponderName(event.window))")
        case .leftMouseDragged:
            let count = state.withLock { state -> Int in
                state.draggedEventsSinceMouseDown += 1
                return state.draggedEventsSinceMouseDown
            }
            // El primero y luego 1 de cada 20, para no inundar el log.
            if count == 1 || count % 20 == 0 {
                log("mouse", "leftMouseDragged #\(count) en \(position)")
            }
        case .leftMouseUp:
            let count = state.withLock { $0.draggedEventsSinceMouseDown }
            log("mouse", "leftMouseUp en \(position) clicks=\(event.clickCount) tras \(count) dragged")
        case .keyDown:
            let characters = event.charactersIgnoringModifiers.map { $0 == " " ? "␣" : $0 } ?? ""
            log("key", "keyDown code=\(event.keyCode) chars=\"\(characters)\"\(modifiers) firstResponder=\(firstResponderName(event.window ?? NSApp.keyWindow))")
        default:
            break
        }
    }

    @MainActor
    private static func hitChain(for event: NSEvent) -> String {
        guard let window = event.window,
              let root = window.contentView?.superview ?? window.contentView,
              let hit = root.hitTest(event.locationInWindow) else {
            return "ninguna"
        }
        var chain: [String] = []
        var current: NSView? = hit
        while let view = current, chain.count < 6 {
            chain.append(String(describing: type(of: view)))
            current = view.superview
        }
        return chain.joined(separator: " ← ")
    }

    @MainActor
    private static func firstResponderName(_ window: NSWindow?) -> String {
        guard let responder = window?.firstResponder else { return "nil" }
        return String(describing: type(of: responder))
    }

    private static func modifierDescription(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.control) { parts.append("⌃") }
        return parts.isEmpty ? "" : " mods=" + parts.joined()
    }
}
