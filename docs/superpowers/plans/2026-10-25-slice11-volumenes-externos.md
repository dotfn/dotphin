# Slice 11 — Soporte más profundo de volúmenes externos — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Desde la sidebar de Places, sobre un volumen (no sobre un
bookmark): menú contextual con "Información" (capacidad total/libre,
formato del filesystem) y "Expulsar" (con confirmación).

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** la lista de volúmenes sigue siendo una foto fija al abrir la app
(no observa mount/unmount en vivo — decisión ya tomada y diferida desde
el slice 1/5). Expulsar un volumen no lo quita de la sidebar al
instante por la misma razón; se actualiza la próxima vez que se abra
la app o se refresque. No hay soporte de discos `.Trashes` por volumen
externo (la papelera del slice 9 sigue siendo solo `~/.Trash`).

**Arquitectura:** `VolumeInfoProvider` (ya existe desde el slice 5)
gana `info(for:)` con capacidad total y formato, además de la capacidad
libre que ya tenía. `VolumeEjectService` (nuevo, sin tests automáticos
— ver Global Constraints, el motivo es de seguridad, no de pereza)
envuelve la llamada real de expulsión. `PlacesSidebarView` gana un
`.contextMenu` por fila cuando `place.kind == .volume`.

**Tech Stack:** Swift 6.4, SwiftUI, `NSWorkspace`/`URLResourceValues`
nativos.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-10.
- **`VolumeEjectService.eject(_:)` no tiene test automático que llame al
  método real sobre un volumen real.** No es pereza: un test que
  expulsa un volumen de verdad podría expulsar el disco de arranque (o
  cualquier volumen montado en la máquina donde corre la suite) si algo
  en el test está mal armado. El riesgo de un bug en el test es peor
  que no tener el test. Se verifica manualmente con un volumen de
  prueba (una imagen de disco montada aparte) antes de dar el slice por
  terminado.
- Expulsar pide confirmación siempre (acción con efecto real sobre el
  sistema, aunque no sea destructiva de datos).

## Review Focus

- Pedir información de un volumen que se desmontó entre que se abrió el
  menú contextual y que se ejecutó la acción → debe degradar a un
  estado de error legible, nunca crashear.
- Expulsar un volumen que está en uso (archivo abierto, proceso
  corriendo ahí) → el error que devuelve el sistema debe mostrarse al
  usuario, nunca fallar en silencio ni descolgar la sidebar.
- `VolumeInfo` sobre una ruta que no es un punto de montaje real (por
  ejemplo, un volumen recién expulsado por otra vía) → todos los campos
  deben degradar a `nil`, nunca crashear.
- El menú contextual de "Expulsar"/"Información" solo debe aparecer
  sobre volúmenes (`kind == .volume`), nunca sobre Home/Desktop/etc.
  (`kind == .bookmark`).
- Expulsar el volumen que la ventana está mostrando actualmente (la
  carpeta abierta es ese volumen o algo debajo) → no debe crashear la
  app; el panel que quedó mirando una carpeta que ya no existe debe
  comportarse igual que cualquier otra carpeta borrada por fuera
  (slice 1: estado de error, no crash).

---

## Task 1: `VolumeInfoProvider.info(for:)`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/VolumeInfoProvider.swift`
- Modify: `Tests/DolphinForMacOSTests/VolumeInfoProviderTests.swift`

**Interfaces:**
- Produce (agrega al struct existente):
  ```swift
  struct VolumeInfo {
      let totalCapacity: Int64?
      let availableCapacity: Int64?
      let format: String?
  }

  func info(for url: URL) -> VolumeInfo
  ```
  Usa `URLResourceValues` con `.volumeTotalCapacityKey`,
  `.volumeAvailableCapacityKey`, `.volumeLocalizedFormatDescriptionKey`.
  Sobre una ruta inválida, los tres campos quedan `nil` (nunca tira).

- [ ] **Step 1: Test que falla**

```swift
func test_info_forRealPath_returnsPositiveCapacitiesAndFormat() {
    let provider = VolumeInfoProvider()
    let info = provider.info(for: FileManager.default.temporaryDirectory)
    XCTAssertNotNil(info.totalCapacity)
    XCTAssertNotNil(info.availableCapacity)
    XCTAssertNotNil(info.format)
    XCTAssertTrue((info.totalCapacity ?? 0) > 0)
}

func test_info_forNonExistentPath_returnsAllNil() {
    let provider = VolumeInfoProvider()
    let info = provider.info(for: URL(fileURLWithPath: "/this/does/not/exist/at/all"))
    XCTAssertNil(info.totalCapacity)
    XCTAssertNil(info.availableCapacity)
    XCTAssertNil(info.format)
}
```

- [ ] **Step 2:** `swift test --filter VolumeInfoProviderTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-10).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/VolumeInfoProvider.swift Tests/DolphinForMacOSTests/VolumeInfoProviderTests.swift
git commit -m "feat: VolumeInfoProvider.info(for:) con capacidad total y formato"
```

---

## Task 2: `VolumeEjectService`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/VolumeEjectService.swift`

**Interfaces:**
- Produce:
  ```swift
  enum VolumeEjectError: Error {
      case failed(String)
  }

  struct VolumeEjectService {
      func eject(_ url: URL) throws
  }
  ```

Antes de implementar, consultar `axiom-macos` por la API vigente de
`NSWorkspace` para expulsar un volumen (la firma exacta puede variar
entre versiones del SDK) — regla del proyecto. Sin test automático
(ver Global Constraints) — verificación manual con un volumen de
prueba al cerrar el slice.

- [ ] **Step 1: Implementar** usando el método que `axiom-macos`
  confirme como vigente para macOS 27. Mapear cualquier fallo del
  sistema a `VolumeEjectError.failed(mensaje)`.
- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Services/VolumeEjectService.swift
git commit -m "feat: VolumeEjectService (sin test automático, ver decisions.md)"
```

---

## Task 3: Menú contextual en `PlacesSidebarView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/PlacesSidebarView.swift`

**Interfaces:**
- Consume: `VolumeInfoProvider.info(for:)` (Task 1),
  `VolumeEjectService.eject(_:)` (Task 2).
- Produce: sin cambios en la firma pública de `PlacesSidebarView`
  (sigue siendo `places:`, `currentURL:`, `onSelect:`) — todo lo nuevo
  es estado interno.

- [ ] **Step 1: Implementar**

```swift
@State private var pendingEject: PlaceItem?
@State private var showsEjectConfirmation = false
@State private var infoTarget: PlaceItem?
@State private var ejectError: String?
```
Un `.contextMenu` por fila, solo si `place.kind == .volume`:
"Información" pone `infoTarget = place`; "Expulsar" pone
`pendingEject = place; showsEjectConfirmation = true`. Un
`.alert("Expulsar \"\(place.name)\"?", isPresented:, presenting:
pendingEject)` con botón "Expulsar" que llama
`VolumeEjectService().eject(place.url)` y, si tira, pone
`ejectError = error.localizedDescription` para mostrar en otro alert
simple. `infoTarget` se muestra en un `.popover` o `.alert` con
`VolumeInfoProvider().info(for: place.url)` formateado (mismo
`ByteCountFormatter` que ya se usa en `StatusBarView`/
`FileMetadataFormatter`).

- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/PlacesSidebarView.swift
git commit -m "feat: menú contextual de Información/Expulsar para volúmenes — slice 11 completo"
```

---

## Task 4: Suite completa + smoke run + verificación manual de eject

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-11 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** Verificación manual (fuera del alcance de este
  ejecutor si no hay herramienta de UI disponible — dejar anotado en
  el ledger, igual que el resto de la navegación/clicks de slices
  anteriores): montar una imagen de disco de prueba (`hdiutil attach`
  de un `.dmg` vacío), confirmar que aparece como volumen en la
  sidebar, click derecho → Expulsar, confirmar que desaparece.
- [ ] **Step 4:** sin commit si no hay cambios pendientes.
