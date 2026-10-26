# Slice 14b — Deuda de accesibilidad (ViewModePicker, zoom, git badge) — Plan

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Cerrar la deuda de accesibilidad que el review de slice 14
detectó pero que ese slice no cubrió: `ViewModePicker` (3 segmentos de
solo ícono), el `Slider` de zoom en `BrowserView`, y `GitStatusBadge`
(un punto de color sin alternativa accesible). Documentado en
`docs/decisions.md` bajo la entrada del review de slice 14.

**Arquitectura:** Mismo patrón que el resto del barrido de
accesibilidad (`.help` + `.accessibilityLabel`). Para `GitStatusBadge`
se agrega una propiedad computada testeable (`GitFileStatus.accessibilityDescription`)
en vez de incrustar los strings directamente en la vista, porque es la
única pieza de este slice con lógica real (un mapping) en vez de solo
modificadores de vista.

**Tech Stack:** Swift 6.4, SwiftUI, sin dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices anteriores.
- Ningún cambio de comportamiento — esto es puramente accesibilidad
  (etiquetas/tooltips), no debe tocar lógica de selección de vista, zoom
  ni estado de git.

## Review Focus

- `GitStatusBadge` con `status == nil` no debe ganar ningún label vacío
  ni volverse un elemento fantasma para VoiceOver — el `if let status`
  existente ya lo cubre, pero verificar que el label se agregue solo
  dentro de esa rama.
- Los 3 segmentos de `ViewModePicker` deben seguir funcionando como
  Picker nativo (seleccionable, con el tag correcto) después de agregar
  modificadores — un error común es que agregar `.accessibilityLabel`
  a la vista hija en vez de encadenarlo correctamente rompa el `.tag`.

---

## Task 1: `GitFileStatus.accessibilityDescription` + wiring en `GitStatusBadge`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/GitStatusProvider.swift`
- Modify: `Sources/DolphinForMacOS/Views/GitStatusBadge.swift`
- Test: `Tests/DolphinForMacOSTests/GitStatusProviderTests.swift`

**Interfaces:**
- Produce: `GitFileStatus.accessibilityDescription: String`

- [ ] **Step 1: Test que falla**

```swift
func test_accessibilityDescription_coversEveryCase() {
    XCTAssertEqual(GitFileStatus.modified.accessibilityDescription, "Modificado")
    XCTAssertEqual(GitFileStatus.added.accessibilityDescription, "Agregado")
    XCTAssertEqual(GitFileStatus.deleted.accessibilityDescription, "Eliminado")
    XCTAssertEqual(GitFileStatus.untracked.accessibilityDescription, "Sin seguimiento")
    XCTAssertEqual(GitFileStatus.renamed.accessibilityDescription, "Renombrado")
}
```

- [ ] **Step 2:** `swift test --filter test_accessibilityDescription_coversEveryCase` → FAIL (no existe la propiedad).
- [ ] **Step 3:** Implementar como `extension GitFileStatus` en el mismo archivo de `GitStatusProvider.swift`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** En `GitStatusBadge.swift`, agregar `.accessibilityLabel(status.accessibilityDescription)` al `Circle()` dentro del `if let status`.
- [ ] **Step 6:** `swift build` → `Build complete!`.
- [ ] **Step 7: Commit**

```bash
git add Sources/DolphinForMacOS/Services/GitStatusProvider.swift Sources/DolphinForMacOS/Views/GitStatusBadge.swift Tests/DolphinForMacOSTests/GitStatusProviderTests.swift
git commit -m "feat: accessibilityLabel en GitStatusBadge (estado de git visible para VoiceOver)"
```

---

## Task 2: Accesibilidad en `ViewModePicker` y en el `Slider` de zoom

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/ViewModePicker.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:** sin cambios de firma — solo modificadores agregados.

- [ ] **Step 1:** En `ViewModePicker`, agregar `.accessibilityLabel(...)` + `.help(...)` a cada uno de los 3 `Image(systemName:)` (íconos, lista, detalles), encadenados antes o después de `.tag(...)` sin removerlo.
- [ ] **Step 2:** En `BrowserView`, agregar `.accessibilityLabel("Zoom")` + `.help("Zoom")` al `Slider` de zoom (dentro del `if viewModel.viewProperties.mode == .icons`).
- [ ] **Step 3:** `swift build` → `Build complete!` (sin test automático, mismo motivo que el resto del barrido de accesibilidad: no hay infraestructura de UI testing en este proyecto).
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/ViewModePicker.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: accessibilityLabel + help en ViewModePicker y slider de zoom"
```

---

## Task 3: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests en PASS (incluyendo el nuevo).
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
