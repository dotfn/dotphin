# Slice 22 — Terminal integrada sobre SwiftTerm

## Objetivo

Reemplazar el emulador hecho a mano (`TerminalScreenBuffer` + `Text` +
`TextField`) por SwiftTerm, para tener una terminal completa en el panel F4:
colores (16, 256 y truecolor), pantalla alterna (`vim`, `less`, `htop`),
teclado directo a la shell (Tab, Ctrl+R, flechas), mouse, tamaño real del
pty y caracteres anchos.

## Decisiones

- Dependencia: `SwiftTerm` (MIT) `from: "1.99.3"`. Es la primera dependencia
  externa del paquete; la elige el usuario el 2026-11-10 ("completa la
  migración hacia la terminal más madura"). Alternativas descartadas:
  libghostty (API de embebido no estable, build con Zig), xterm.js en
  WKWebView (no nativo), iTerm2/Alacritty (no embebibles).
- Axiom consultado: `axiom-macos` → `appkit-interop.md` (ciclo de vida de
  `NSViewRepresentable`, no tocar el frame, guardar las actualizaciones).
- `EmbeddedTerminalSession` sigue siendo el dueño (vive en `ContentView`) y
  ahora es dueño de la vista `DotphinTerminalView`
  (`LocalProcessTerminalView`). Así la shell sobrevive a ocultar/mostrar el
  panel, como hoy. Si la shell termina, reabrir el panel crea una vista nueva.
- Se conserva: sincronización Dotphin → shell (Ctrl+E Ctrl+U ` cd '…'`),
  shell → Dotphin (`proc_pidinfo` tras cada lote de salida, y OSC 7 si la
  shell lo emite), `enrichedDeveloperPath`, argumentos de zsh, botones de
  sincronizar, ^C, limpiar, Terminal.app y cerrar.
- "El usuario ya ejecutó un comando" (para decidir si el `cd` va con
  `clear`) se detecta en `send(source:data:)`: cualquier Intro tecleado.
- F4 / ⇧F4 con el foco en la terminal: la subclase ofrece esas teclas al
  menú principal antes de mandarlas a la shell.
- Colores: fondo y texto del sistema (`textBackgroundColor`/`textColor`),
  reaplicados al cambiar de apariencia clara/oscura. Fuente monoespaciada del
  sistema, 12 pt.
- Se borra: `TerminalScreenBuffer`, `outputText`, `sendCommand`,
  `updateWindowSize`, `stripANSISequences`, `applyBackspaces`, la barra de
  entrada y su historial, y sus textos del catálogo.

## Pasos (TDD)

1. Tests: reemplazar los tests del buffer por tests de la sesión real —
   arranca la shell en la carpeta pedida, `syncDirectory` mueve la shell
   (verificado con `workingDirectory(forPID:)`), el panel monta la vista de
   SwiftTerm en una ventana, F4 con la terminal enfocada llega al menú.
2. `Package.swift`: agregar SwiftTerm.
3. Reescribir `EmbeddedTerminalView.swift`.
4. Catálogo: quitar claves muertas, agregar las nuevas (en/es).
5. `swift build`, `swift test` (mirar el código de salida), `.app` con
   `scripts/build_app_bundle.sh`.
6. Revisión independiente, corregir Important/Critical, merge fast-forward.
