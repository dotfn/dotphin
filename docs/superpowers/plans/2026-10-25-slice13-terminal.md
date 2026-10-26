# Slice 13 — Terminal embebido — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Un botón "Abrir Terminal aquí" que lanza Terminal.app ya
posicionado en la carpeta que se está navegando.

**Decisión de alcance (ya anticipada en el documento de diseño,
sección de Riesgos):** no se embebe un emulador de terminal real.
macOS no tiene un framework nativo de emulación de terminal (a
diferencia de VTE en Linux), y la única librería que lo daría
(SwiftTerm) es una dependencia de terceros — contra la regla del
proyecto de "sin dependencias nuevas, preferir nativo aunque la
feature sea más chica". Se lanza Terminal.app real vía `/usr/bin/open
-a Terminal <carpeta>`, que es el comportamiento documentado de macOS
para abrir una Terminal ya posicionada en una carpeta (lo mismo que
"Nueva Terminal en la carpeta" del menú contextual de Finder). Esto es
exactamente lo que Dolphin mismo describe en su propio README como
"no intrusivo": un solo ítem de menú, mucho valor para el usuario
power, cero complejidad para el resto.

**Arquitectura:** `TerminalLauncher` separa la parte pura y testeable
(construir los argumentos de `open`) de la parte con efecto real
(lanzar el proceso) — igual criterio que `VolumeEjectService` del
slice 11: lanzar una Terminal real durante un test automático abre una
ventana visible real, así que esa parte no se testea en automático,
pero la lógica que decide QUÉ lanzar sí.

**Tech Stack:** Swift 6.4, `Foundation.Process` (shell-out a
`/usr/bin/open`, nativo del sistema).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-12.
- `TerminalLauncher.openTerminal(at:)` no tiene test automático que lo
  ejecute de verdad (abriría una ventana real de Terminal.app durante
  la suite) — mismo motivo y mismo patrón que
  `VolumeEjectService.eject(_:)` del slice 11. Lo que sí se testea es
  `launchArguments(for:)`, la parte pura.

## Review Focus

- `/usr/bin/open` no encontrado o Terminal.app no instalado (muy
  improbable en macOS, pero el código no debe asumirlo) → el error
  debe mostrarse al usuario, nunca fallar en silencio.
- El botón debe usar siempre `viewModel.currentURL` en el momento del
  click, no una carpeta vieja cacheada — si el usuario navegó justo
  antes de clickear, tiene que abrir en la carpeta que ve en pantalla.
- Abrir terminal en una carpeta con espacios o caracteres especiales en
  el path → no debe romperse por falta de quoting (al pasar el path
  como argumento separado a `Process`, no como string shell
  interpolado, esto ya se evita por construcción — confirmar que
  `launchArguments` no concatena nada a mano).

---

## Task 1: `TerminalLauncher`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/TerminalLauncher.swift`
- Test: `Tests/DolphinForMacOSTests/TerminalLauncherTests.swift`

**Interfaces:**
- Produce:
  ```swift
  enum TerminalLauncherError: Error {
      case failed(String)
  }

  struct TerminalLauncher {
      func launchArguments(for url: URL) -> [String]
      func openTerminal(at url: URL) throws
  }
  ```
  `launchArguments(for:)` devuelve `["-a", "Terminal", url.path]` — cada
  elemento su propio argumento, nunca un string armado a mano (eso es
  lo que evita problemas de quoting con espacios/caracteres especiales
  en el path). `openTerminal(at:)` lanza
  `/usr/bin/open` con esos argumentos vía `Process`; si `process.run()`
  tira, lo envuelve en `TerminalLauncherError.failed(...)`.

- [ ] **Step 1: Test que falla**

```swift
import XCTest
@testable import DolphinForMacOS

final class TerminalLauncherTests: XCTestCase {
    func test_launchArguments_opensTerminalAtGivenPath() {
        let url = URL(fileURLWithPath: "/tmp/some folder")
        let args = TerminalLauncher().launchArguments(for: url)
        XCTAssertEqual(args, ["-a", "Terminal", "/tmp/some folder"])
    }
}
```

- [ ] **Step 2:** `swift test --filter TerminalLauncherTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/TerminalLauncher.swift Tests/DolphinForMacOSTests/TerminalLauncherTests.swift
git commit -m "feat: TerminalLauncher (abre Terminal.app vía open -a, sin dependencia de terceros)"
```

---

## Task 2: Botón "Abrir Terminal aquí" en `BrowserView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `TerminalLauncher` (Task 1).

- [ ] **Step 1: Implementar**

Un botón en la toolbar existente (ícono `"terminal"`) que llama
`try? TerminalLauncher().openTerminal(at: viewModel.currentURL)` en el
momento del click (lee `currentURL` ahí, no antes). Si tira, un
`@State private var terminalError: String?` + `.alert` simple (mismo
patrón que `ejectError` en `PlacesSidebarView` del slice 11).

- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: botón Abrir Terminal aquí — slice 13 completo"
```

---

## Task 3: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-13 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
