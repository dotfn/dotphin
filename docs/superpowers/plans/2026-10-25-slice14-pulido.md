# Slice 14 — Pasada de pulido — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Último slice del roadmap original. Cierra la deuda de
accesibilidad acumulada en `docs/decisions.md` a lo largo de los
slices 3-13 (botones de ícono sin `.help`/accessibility label), agrega
preview real de Quick Look al panel de información (diferido desde el
slice 4), y confirma el estado de adopción de Liquid Glass.

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** drag & drop entre paneles y con Finder queda explícitamente
afuera de este slice — es un patrón de interacción nuevo
(`.draggable()`/`.dropDestination()`, `NSItemProvider`) que toca otra
vez las 3 vistas de listado, y forzarlo al final de una sesión larga
sin poder probarlo a mano es más riesgo que valor. Queda documentado
como el único punto del roadmap original sin cerrar, con su propio
diseño pendiente si se retoma.

**Arquitectura:** `ThumbnailLoader` (nuevo, async, envuelve
`QLThumbnailGenerator`) para el preview real de archivos en
`InfoPanelView`. El resto son cambios de UI puntuales (`.help` +
`.accessibilityLabel` en botones de solo ícono) sin servicio nuevo.

**Tech Stack:** Swift 6.4, SwiftUI, `QuickLookThumbnailing` nativo
(framework del sistema, sin dependencias nuevas).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-13.
- `ThumbnailLoader` nunca bloquea el main thread — es async desde el
  día uno (a diferencia de la lectura de directorio del slice 1, que
  sí es síncrona por precedente ya aceptado; generar un thumbnail real
  puede tardar más que listar un directorio, así que no se repite esa
  concesión aquí).

## Review Focus

- Pedir un thumbnail de un archivo que no existe (se borró entre que
  se seleccionó y que terminó de generarse) → debe degradar al ícono
  genérico, nunca crashear ni dejar el panel de info en un estado
  roto.
- Cambiar la selección mientras un thumbnail todavía se está generando
  → el thumbnail viejo no debe aparecer pegado al ítem nuevo (hay que
  invalidar/cancelar el `.task` anterior, no solo lanzar uno nuevo
  encima).
- Un archivo de un tipo sin preview conocido (binario raro, etc.) →
  `QLThumbnailGenerator` normalmente devuelve un ícono genérico igual;
  confirmar que un `nil`/error no deja el panel vacío sin ícono de
  ningún tipo.
- Todos los botones de solo ícono agregados en los slices 3 a 13
  deben tener `.help` Y `.accessibilityLabel` — no alcanza con uno
  solo (VoiceOver necesita el label, el tooltip visual necesita
  `.help`).

---

## Task 1: Barrido de accesibilidad en botones de solo ícono

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`
- Modify: `Sources/DolphinForMacOS/Views/TabBarView.swift`
- Modify: `Sources/DolphinForMacOS/Views/ContentView.swift`
- Modify: `Sources/DolphinForMacOS/Views/FilterBarView.swift`
- Modify: `Sources/DolphinForMacOS/Views/PlacesSidebarView.swift` (el
  ícono `sidebar.right` si corresponde, ya se movió a `ContentView` en
  el slice 4 — verificar ahí)

Antes de implementar, consultar `axiom-accessibility` por el patrón
correcto de `.help` + `.accessibilityLabel` en botones de ícono —
regla del proyecto.

**Interfaces:** sin cambios de firma — solo modificadores agregados a
vistas existentes.

- [ ] **Step 1: Agregar `.help(...)` + `.accessibilityLabel(...)` a
  cada botón de solo ícono**

Lista conocida (de `docs/decisions.md`, slices 3/4/5/8/9/10/11/13):
botón de split y de "+"/cerrar pestaña en `TabBarView`; botón del
panel de información (`sidebar.right`) en `ContentView`; botón de
split (`rectangle.split.2x1`) en `ContentView`; terminal, nueva
carpeta, renombrar, eliminar, restaurar, vaciar papelera, orden
(`arrow.up.arrow.down`) en `BrowserView`; botón de limpiar filtro en
`FilterBarView`. Cada uno gana las dos modificadores con el mismo
texto descriptivo (p. ej. `.help("Abrir Terminal aquí")` +
`.accessibilityLabel("Abrir Terminal aquí")`).

- [ ] **Step 2:** `swift build` → `Build complete!` (sin test
  automático — no hay una forma de testear accessibility labels de
  SwiftUI sin infraestructura de UI testing que este proyecto no usa;
  se verifica por lectura de código, no es lógica de negocio).
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/BrowserView.swift Sources/DolphinForMacOS/Views/TabBarView.swift Sources/DolphinForMacOS/Views/ContentView.swift Sources/DolphinForMacOS/Views/FilterBarView.swift
git commit -m "feat: accesibilidad (.help + .accessibilityLabel) en todos los botones de solo ícono"
```

---

## Task 2: `ThumbnailLoader` (Quick Look real)

**Files:**
- Create: `Sources/DolphinForMacOS/Services/ThumbnailLoader.swift`
- Test: `Tests/DolphinForMacOSTests/ThumbnailLoaderTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct ThumbnailLoader {
      func thumbnail(for url: URL, size: CGSize) async -> NSImage?
  }
  ```
  Envuelve `QLThumbnailGenerator.shared.generateBestRepresentation(for:completionHandler:)`
  con `withCheckedContinuation`. Sobre una ruta que no existe o que
  tira, devuelve `nil` (nunca propaga el error, el llamador solo
  necesita saber si hay o no imagen).

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class ThumbnailLoaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_thumbnail_forExistingFile_returnsAnImage() async throws {
        let fileURL = tempDir.appendingPathComponent("doc.txt")
        try "contenido de prueba".write(to: fileURL, atomically: true, encoding: .utf8)
        let image = await ThumbnailLoader().thumbnail(for: fileURL, size: CGSize(width: 64, height: 64))
        XCTAssertNotNil(image)
    }

    func test_thumbnail_forNonExistentFile_returnsNil() async {
        let missing = tempDir.appendingPathComponent("doesNotExist.txt")
        let image = await ThumbnailLoader().thumbnail(for: missing, size: CGSize(width: 64, height: 64))
        XCTAssertNil(image)
    }
}
```

- [ ] **Step 2:** `swift test --filter ThumbnailLoaderTests` → FAIL.
- [ ] **Step 3:** Implementar con `QLThumbnailGenerator.Request(fileAt:
  size:scale:representationTypes: .thumbnail)`, `scale` = 2 (retina).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/ThumbnailLoader.swift Tests/DolphinForMacOSTests/ThumbnailLoaderTests.swift
git commit -m "feat: ThumbnailLoader (Quick Look real, async, nativo)"
```

---

## Task 3: Wiring en `InfoPanelView` + chequeo de Liquid Glass

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/InfoPanelView.swift`

**Interfaces:**
- Consume: `ThumbnailLoader` (Task 2).

- [ ] **Step 1: Implementar el thumbnail en `InfoPanelView`**

```swift
@State private var thumbnail: NSImage?

// en el ícono grande existente:
Group {
    if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFit()
    } else {
        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
    }
}
.frame(width: 64, height: 64)
.task(id: item.url) {
    thumbnail = nil // limpia el thumbnail viejo antes de pedir el nuevo
    guard !item.isDirectory else { return }
    thumbnail = await ThumbnailLoader().thumbnail(for: item.url, size: CGSize(width: 128, height: 128))
}
```
`.task(id:)` cancela automáticamente la tarea anterior cuando `item.url`
cambia — eso resuelve el caso de "cambiar selección mientras carga".

- [ ] **Step 2: Chequeo de adopción de Liquid Glass**

Leer `skills/liquid-glass-auditor.md` de `axiom-design` y repasar la
app: no hay ningún `.background(.ultraThinMaterial)`,
`NSVisualEffectView`, ni override de material custom en ningún lado
del código — todo son controles stock de SwiftUI
(`List`/`Table`/`NavigationSplitView`/`Menu`/`Button`/`TextField`/
`.alert`/`.inspector`) sobre macOS 27. Según la guía del propio skill
("la mayoría de los componentes estándar de SwiftUI/UIKit adoptan
Liquid Glass automáticamente"), no hay nada que cambiar en código —
se documenta la conclusión en `docs/decisions.md`, no se agrega
código por agregar.

- [ ] **Step 3:** `swift build` → `Build complete!`.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/InfoPanelView.swift
git commit -m "feat: Quick Look real en el panel de información — slice 14 completo"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-14 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
