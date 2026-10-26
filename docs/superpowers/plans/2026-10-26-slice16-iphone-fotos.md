# Slice 16 — Fotos del iPhone conectado (ImageCaptureCore) — Plan

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Entregar la parte de "dispositivos móviles" del diseño
original que SÍ es técnicamente posible sin APIs privadas: ver las
fotos/videos de un iPhone conectado por USB desde la sidebar de la app,
de solo lectura. No es browsing de archivos general — eso fue
descartado en el slice 12 y queda confirmado abajo con evidencia nueva.

**Por qué esto y no más:** se leyeron los headers reales de
`ImageCaptureCore.framework` en el SDK de macOS 27 instalado en esta
máquina (no se asumió nada de memoria):
- `ICCameraDevice.mountPoint` y `ICCameraItem.fileSystemPath` son
  `NULL` para cualquier dispositivo que no sea una cámara vieja estilo
  USB Mass Storage — un iPhone conecta por otro transporte, así que
  **nunca hay un path de archivo real**. Confirma que esto no puede ser
  "browsing de archivos", solo fotos/videos vía `ICCameraItem`.
- Los callbacks del delegate de `ICDeviceBrowser`/`ICDevice` están
  documentados explícitamente como "Execution of the delegate callback
  will occur on the main thread" — encaja limpio con `@MainActor`.
- Android sigue descartado: ninguna skill de Axiom (ni siquiera
  `axiom-media`, que documenta hasta DockKit y ScreenCaptureKit) tiene
  un patrón de acceso a un dispositivo conectado por USB desde una Mac
  app, y macOS nunca tuvo soporte nativo de MTP — el único camino es
  un driver/dependencia de terceros (`libmtp`), contra la regla
  explícita del proyecto de no agregar dependencias de terceros por
  default.

**Importante — esta es la primera vez en el proyecto que SÍ hay
hardware real para verificar:** el usuario tiene un iPhone conectado
ahora mismo. A diferencia de `VolumeEjectService` (slice 11) o
`TerminalLauncher` (slice 13), donde la verificación real quedó
documentada como limitación aceptada, acá el plan incluye puntos donde
el ejecutor corre la app (`swift run` en background, leer su log) y,
si algo no es verificable solo por log, pide al usuario que mire la
sidebar y reporte qué ve — antes de considerar una tarea terminada.

**Arquitectura:**
- `PhotoDeviceBrowser`: `@MainActor @Observable final class ... : NSObject, ICDeviceBrowserDelegate` — envuelve `ICDeviceBrowser`, filtra a `ICCameraDevice`, expone `private(set) var devices: [ICCameraDevice]`.
- `PhotoDeviceSession`: `@MainActor @Observable final class ... : NSObject, ICCameraDeviceDelegate` — abre sesión en UN `ICCameraDevice`, expone `private(set) var items: [PhotoItem]` (modelo propio, no `ICCameraItem` crudo).
- `PhotoItem`: struct `Identifiable` liviana (id, name, isVideo, thumbnail: NSImage?) — lo único testeable de forma pura (mapeo desde metadata/UTI).
- `PhotoDeviceView`: grilla de solo lectura, mismo estilo visual que `IconGridView` pero sin drag/drop, sin eliminar, sin abrir — son fotos de un dispositivo externo, no archivos locales.
- Wiring: `ContentView` gana `@State private var selectedDevice: ICCameraDevice?`; si no es `nil`, el detail pane muestra `PhotoDeviceView` en vez de `SplitBrowserView`. La sidebar de Places gana una sección nueva "Dispositivos" (dinámica, usa `PhotoDeviceBrowser`) debajo de la sección estática de volúmenes.

**Tech Stack:** Swift 6.4, SwiftUI, `ImageCaptureCore` nativo (framework
del sistema, sin dependencias nuevas). Sin sandbox (ya decidido para
todo el proyecto), así que no hay entitlements de sandbox que pedir;
si macOS pide algún permiso de TCC al abrir sesión en el dispositivo
real, se documenta en decisions.md con lo que se vio en la práctica —
ninguna doc de Apple en este SDK describe un prompt de TCC para
ImageCaptureCore en macOS (a diferencia de iOS 14+, que sí tiene
`contentsAuthorizationStatus`, marcado `IC_UNAVAILABLE(macos)`).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`
(el diseño original listaba iPhone/Android como "en alcance" para la
sidebar de Places; este slice entrega la porción de iPhone que es
técnicamente posible, documentando por qué el resto no lo es).

## Global Constraints

- Mismas restricciones globales de los slices anteriores.
- Solo lectura: nada en este slice borra, descarga, ni copia archivos
  del dispositivo — ver fotos y listo. Descargar/exportar queda
  explícitamente fuera de alcance (extensión futura, no necesaria para
  "ver las fotos de tu iPhone").
- Android queda descartado de forma definitiva y documentada — no se
  vuelve a investigar en este slice.
- Si en algún punto el comportamiento real con el iPhone conectado del
  usuario no coincide con lo que dicen los headers (ej. si sí aparece
  algún prompt de permiso, o el dispositivo no aparece como
  `ICCameraDevice`), se para esa tarea, se ajusta el código según lo
  que se observa, y se documenta la discrepancia en decisions.md —
  igual que la corrección de la API de eject en el slice 11.

## Review Focus

- Desconectar el iPhone mientras `PhotoDeviceView` está mostrando sus
  fotos no debe crashear ni dejar la vista en un estado roto — debe
  volver a la sidebar/al browsing normal de forma razonable.
- Un dispositivo que no es cámara (ej. un scanner, si alguna vez se
  conecta uno) no debe aparecer en la lista de "Dispositivos" — el
  filtro a `ICCameraDevice` debe ser real, no solo de nombre.
- Si `PhotoDeviceBrowser.start()` nunca se llama o se llama dos veces,
  no debe haber crash ni fuga de delegate (reemplazar el browser, no
  apilar).

---

## Task 1: `PhotoItem` + mapeo puro (testeable)

**Files:**
- Create: `Sources/DolphinForMacOS/Models/PhotoItem.swift`
- Test: `Tests/DolphinForMacOSTests/PhotoItemTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct PhotoItem: Identifiable {
      let id: String
      let name: String
      let isVideo: Bool
      var thumbnail: NSImage?
  }
  extension PhotoItem {
      init(name: String?, utiIdentifier: String?, id: String)
  }
  ```
  `isVideo` se deriva del UTI con `UTType(utiIdentifier)?.conforms(to: .movie) ?? false`
  (si el UTI es nil o no resuelve, `isVideo = false`).

- [ ] **Step 1: Test que falla**

```swift
import XCTest
@testable import DolphinForMacOS

final class PhotoItemTests: XCTestCase {
    func test_init_withImageUTI_isNotVideo() {
        let item = PhotoItem(name: "foto.heic", utiIdentifier: "public.heic", id: "1")
        XCTAssertFalse(item.isVideo)
    }

    func test_init_withMovieUTI_isVideo() {
        let item = PhotoItem(name: "clip.mov", utiIdentifier: "com.apple.quicktime-movie", id: "2")
        XCTAssertTrue(item.isVideo)
    }

    func test_init_withNilUTI_isNotVideo() {
        let item = PhotoItem(name: "misterioso", utiIdentifier: nil, id: "3")
        XCTAssertFalse(item.isVideo)
    }

    func test_init_withNilName_usesFallback() {
        let item = PhotoItem(name: nil, utiIdentifier: nil, id: "4")
        XCTAssertFalse(item.name.isEmpty)
    }
}
```

- [ ] **Step 2:** `swift test --filter PhotoItemTests` → FAIL.
- [ ] **Step 3:** Implementar `PhotoItem` + el init de conveniencia con
  `UniformTypeIdentifiers`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Models/PhotoItem.swift Tests/DolphinForMacOSTests/PhotoItemTests.swift
git commit -m "feat: PhotoItem + mapeo de UTI a isVideo"
```

---

## Task 2: `PhotoDeviceBrowser` (detección de dispositivos)

**Files:**
- Create: `Sources/DolphinForMacOS/Services/PhotoDeviceBrowser.swift`

**Interfaces:**
- Produce:
  ```swift
  @MainActor @Observable
  final class PhotoDeviceBrowser: NSObject, ICDeviceBrowserDelegate {
      private(set) var devices: [ICCameraDevice] = []
      func start()
      func stop()
  }
  ```
  `browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMaskCamera.rawValue | ICDeviceLocationTypeMaskLocal.rawValue)`
  (los dos son `NS_ENUM`, no `NS_OPTIONS` — SwiftUI no los trae como
  `OptionSet`, hay que combinar `.rawValue` a mano).
  `deviceBrowser(_:didAddDevice:moreComing:)` agrega el device a
  `devices` SOLO si es `ICCameraDevice`; `didRemoveDevice` lo saca por
  identidad de objeto (`===`).

- [ ] **Step 1:** Implementar la clase (sin test automático — requiere
  el Image Capture agent del sistema y un dispositivo real; no es
  unit-testeable, mismo precedente que `VolumeEjectService`).
- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Verificación real con el iPhone del usuario.** Agregar
  TEMPORALMENTE un `print("Dispositivo detectado: \(device.name ?? "?")")`
  en `didAddDevice`, correr `swift run` en background, leer el log, y
  confirmar que el iPhone conectado aparece. Si no aparece: no seguir a
  la Task 3 — diagnosticar primero (¿el iPhone está desbloqueado y
  "confía en esta computadora"? ¿aparece como `ICCameraDevice` o como
  otro tipo?). Remover el `print` temporal una vez confirmado.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Services/PhotoDeviceBrowser.swift
git commit -m "feat: PhotoDeviceBrowser — detección de iPhone/cámaras conectadas"
```

---

## Task 3: `PhotoDeviceSession` (sesión + fotos + thumbnails de UN dispositivo)

**Files:**
- Create: `Sources/DolphinForMacOS/Services/PhotoDeviceSession.swift`

**Interfaces:**
- Consume: `PhotoItem` (Task 1)
- Produce:
  ```swift
  @MainActor @Observable
  final class PhotoDeviceSession: NSObject, ICCameraDeviceDelegate {
      private(set) var items: [PhotoItem] = []
      init(device: ICCameraDevice)
      func open()
      func close()
  }
  ```
  `open()` asigna `device.delegate = self` y llama
  `device.requestOpenSession()`. En `device(_:didOpenSessionWithError:)`
  (de `ICDeviceDelegate`, que `ICCameraDeviceDelegate` hereda o requiere
  por separado — confirmar firma exacta leyendo `ICDevice.h` otra vez
  si el compilador se queja), si no hay error, poblar `items` desde
  `device.mediaFiles ?? device.contents ?? []`, mapeando cada
  `ICCameraItem` a `PhotoItem(name:utiIdentifier:id:)` usando
  `item.name`, `item.UTI`, `String(item.ptpObjectHandle)` como id.
  `cameraDevice(_:didReceiveThumbnail:forItem:error:)` busca el
  `PhotoItem` por id y le asigna `thumbnail = NSImage(cgImage:size:)`
  si `thumbnail != nil` y `error == nil`.

- [ ] **Step 1:** Implementar la clase (sin test automático, mismo
  motivo que Task 2).
- [ ] **Step 2:** `swift build` → `Build complete!` — prestar atención
  a cualquier error de firma de delegate; el compilador es la fuente de
  verdad final sobre los nombres exactos de los métodos opcionales de
  `ICCameraDeviceDelegate` (mismo patrón que la corrección de
  `VolumeEjectService` en el slice 11).
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Services/PhotoDeviceSession.swift
git commit -m "feat: PhotoDeviceSession — abre sesión y lista fotos con thumbnails"
```

---

## Task 4: `PhotoDeviceView` (grilla de solo lectura)

**Files:**
- Create: `Sources/DolphinForMacOS/Views/PhotoDeviceView.swift`

**Interfaces:**
- Consume: `PhotoDeviceSession` (Task 3)

- [ ] **Step 1:** Grilla simple (`LazyVGrid` + `ScrollView`, mismo estilo
  visual que `IconGridView`: `Image(nsImage:)` si hay thumbnail, si no
  un ícono genérico `"photo"`/`"video"` según `isVideo`, con el nombre
  debajo). Sin drag, sin drop, sin contextMenu, sin selección — es de
  solo lectura. `.task` al aparecer llama `session.open()`; `.onDisappear`
  llama `session.close()`.
- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/PhotoDeviceView.swift
git commit -m "feat: PhotoDeviceView — grilla de fotos de solo lectura"
```

---

## Task 5: Wiring en la sidebar y en `ContentView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/PlacesSidebarView.swift`
- Modify: `Sources/DolphinForMacOS/Views/ContentView.swift`

**Interfaces:**
- Consume: `PhotoDeviceBrowser` (Task 2), `PhotoDeviceView` (Task 4).

- [ ] **Step 1:** `ContentView` crea un `@State private var photoDeviceBrowser = PhotoDeviceBrowser()`
  y `@State private var selectedDevice: ICCameraDevice?`; llama
  `photoDeviceBrowser.start()` en `.task` (una sola vez). Agrega una
  sección "Dispositivos" en la sidebar (debajo de Places) listando
  `photoDeviceBrowser.devices` por nombre con ícono `"iphone"`; tocar
  uno asigna `selectedDevice = device`. El `detail:` del
  `NavigationSplitView` muestra `PhotoDeviceView(device: selectedDevice)`
  si `selectedDevice != nil`, si no la vista normal de browsing de
  siempre (`SplitBrowserView`/pestañas). Seleccionar cualquier Place
  normal limpia `selectedDevice = nil`.
- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Verificación real con el iPhone del usuario.** Correr
  `swift run`, y esta vez SÍ pedirle al usuario que mire la ventana:
  ¿aparece el iPhone en la sidebar? ¿al tocarlo aparecen fotos reales
  con thumbnails? Si algo no se ve bien, ajustar antes de seguir —no
  dar la tarea por terminada solo porque compila.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/PlacesSidebarView.swift Sources/DolphinForMacOS/Views/ContentView.swift
git commit -m "feat: iPhone conectado visible en la sidebar — slice 16 completo"
```

---

## Task 6: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests en PASS (incluyendo
  los 4 nuevos de `PhotoItemTests`).
- [ ] **Step 2:** `swift build && swift run` con el iPhone del usuario
  conectado — confirmación final en vivo, no solo build verde.
