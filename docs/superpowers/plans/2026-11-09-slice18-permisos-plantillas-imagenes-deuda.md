# Slice 18 — Permisos recursivos, plantillas custom, montar imágenes de disco y deuda menor de slice 15 — Plan

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:executing-plans para implementar este plan tarea por tarea.

**Contexto:** gap-analysis pedido por el usuario contra KDE Dolphin manteniendo
UI/UX de Apple/macOS. El análisis inicial sobreestimó 2 de los 4 huecos
reportados — una relectura más cuidadosa del código encontró que permisos
editables (toggles r/w/x) y "Crear nuevo" con 6 tipos de archivo YA EXISTEN
(`FilePropertiesSheetView.togglePermissionBit`, `DotphinContextMenus.createNewMenu`),
y que montar `.iso`/`.dmg` YA funciona gratis por el fallback genérico a
`NSWorkspace.shared.open` en `BrowserView.onOpen` (igual que Finder). El
alcance real, confirmado con el usuario, es más chico:

**Objetivo (4 partes independientes, igual que el bundling del slice 14):**

1. **Permisos recursivos:** `FilePropertiesSheetView` gana un toggle
   "Aplicar a subcarpetas y su contenido" (solo visible para carpetas). Al
   tildarlo, cada toggle de bit (r/w/x) que se cambie se propaga con
   `FileManager.enumerator` a todo el contenido recursivo, aplicando el
   mismo modo completo que acaba de quedar en la carpeta raíz.
   **`ponytail:`** esto aplica el bit de ejecución también a archivos
   regulares (a diferencia del modelo simplificado de Finder, que no
   expone ese bit) — ceiling documentado con una nota de texto visible
   junto al toggle; upgrade path si molesta: excluir el bit X de archivos
   no-directorio al recursar.
2. **Plantillas custom:** nuevo `TemplateProvider` (servicio chico, mismo
   estilo que `ArchiveService`/`FolderIconAndTagService`) que lista
   archivos regulares no ocultos directamente dentro de `~/Templates`
   (sin recursión a subcarpetas — alcance plano, Dolphin soporta submenús
   por subcarpeta pero no se replica para no sobre-construir). El menú
   "Crear nuevo" (las 2 copias en `DotphinContextMenus.swift`) agrega esos
   templates después de un `Divider()`, más un ítem final "Abrir carpeta
   de plantillas…" que crea `~/Templates` si no existe y la revela en
   Finder — sin esto no hay forma de agregar un template nuevo. Elegir un
   template dispara el mismo flujo de prompt que "Crear nuevo > Archivo de
   texto…" pero con los bytes del template como contenido inicial
   (`createFile(named:contents:)`, que ya soporta `Data` arbitraria).
3. **Montar imagen de disco:** nuevo `DiskImageMountService` (mismo patrón
   que `TerminalLauncher`/`GitStatusProvider`: shell-out a
   `/usr/bin/hdiutil attach`, leyendo stderr via
   `readDataToEndOfFile()` ANTES de `waitUntilExit()`, nunca después —
   lección de los slices 10/13, repetida aquí porque es el mismo tipo de
   llamada). `BrowserViewModel.mountDiskImage(_:)` lo invoca y, si tiene
   éxito, posta `.placesBookmarksDidChange` para refrescar la sidebar de
   Lugares (reutiliza el mecanismo existente de
   `PlacesProvider`/`ContentView.onReceive`, no uno nuevo) — así el
   volumen montado aparece sin reiniciar la app, cerrando para este caso
   puntual la deuda de slice 1 ("Places es un snapshot sin watching de
   mount/unmount"). Ítem de contexto "Montar imagen de disco" visible
   solo para `.iso`/`.dmg`/`.cdr`/`.img`.
4. **Deuda menor de slice 15 (`docs/decisions.md`, revisión de drag & drop):**
   - **D1:** `BrowserViewModel.moveDroppedItems` descarta el motivo
     específico de cada fallo y solo junta nombres de archivo. Fix:
     capturar el mensaje real de cada `FileOperationError` (se agrega
     `var message: String` a `FileOperationError`, reutilizado también
     por `BrowserView.operationErrorMessage` para no duplicar el switch).
   - **D2:** el no-op de "soltar una carpeta sobre sí misma" en
     `FileOperationsService.move` compara paths con `.standardizedFileURL`,
     que no resuelve alias por symlink (`/tmp` vs `/private/tmp`). Fix:
     resolver con `.resolvingSymlinksInPath()` antes de comparar en los 3
     guards de esa función.
   - **D3 (riesgo aceptado explícitamente por el usuario):** migrar
     `DetailsListView` de la sintaxis `TableColumn`-con-closure a
     `Table(of:selection:) { } rows: { ForEach { TableRow(...).draggable(...).dropDestination(...) } }`
     para que drag & drop funcione en toda la fila, no solo en la columna
     "Nombre" — el reviewer de slice 15 confirmó que la API existe desde
     macOS 14 (la premisa del plan original de que no existía era falsa),
     pero señaló un riesgo no verificado de conflicto de gestos entre
     `.draggable` por fila y la selección nativa de `Table`/`NSTableView`.
     Este entorno sigue sin poder clickear la GUI real. Se hace la
     migración con tests donde alcancen (compilación, que `onOpen`/
     `primaryAction` sigan cableados, que el drop siga llamando
     `onMoveDropped` con los mismos argumentos), y se deja un checklist
     explícito en el reporte final para que el usuario confirme a mano:
     (a) un solo click sigue seleccionando la fila en cualquier columna,
     no solo en "Nombre"; (b) doble click sigue abriendo; (c) arrastrar
     desde una celda que no sea "Nombre" también mueve el archivo.

**Arquitectura / Tech Stack:** Swift 6.4, SwiftUI + AppKit donde haga
falta (`NSWorkspace`, `FileManager`, `Process`). Sin dependencias nuevas.
Mismo patrón de testing que el resto del proyecto (XCTest, TDD).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`;
`docs/decisions.md` (entrada de la revisión de slice 15, sección "Minor
(deferred)" ×3).

## Global Constraints

- Nada de esto puede tocar el flujo de `emptyTrash` ni el guard de
  `isBrowsingTrash` — sin relación, pero cualquier cambio en
  `FileOperationsService`/`BrowserViewModel` debe mantenerlos intactos.
- D2 solo debe cambiar la comparación de identidad de paths, no el
  comportamiento de mover entre volúmenes ni los demás guards ya
  cubiertos por tests existentes.
- D3 no debe cambiar la firma pública de `DetailsListView` (los
  `let`/`var` del struct) — solo su `body` interno — para no romper a
  los 2 call sites que la instancian.
- El montaje de imágenes de disco no debe pedir contraseña ni elevar
  privilegios (si `hdiutil attach` falla por estar la imagen protegida/
  encriptada, eso es un error normal mostrado al usuario, no un caso a
  manejar especialmente).
- Las plantillas nunca se crean/sobrescriben automáticamente — si
  `~/Templates` no existe, solo se crea cuando el usuario pulsa "Abrir
  carpeta de plantillas…", nunca al sólo abrir el menú "Crear nuevo".

## Tasks

1. `FileOperationsService`: agregar `var message: String` a
   `FileOperationError` (mover el switch que hoy vive en
   `BrowserView.operationErrorMessage`); actualizar `operationErrorMessage`
   para delegar (`viewModel.operationError?.message ?? ""`). Resolver
   symlinks en los 3 guards de `move(_:toDirectory:)` (D2). Tests:
   `test_move_folderDroppedOntoItself_viaSymlinkAlias_isNoOp` (crear un
   symlink real a un directorio y soltar la carpeta original sobre su
   alias), test de `FileOperationError.message` para los 3 casos.
2. `BrowserViewModel.moveDroppedItems`: usar `error.message`/
   `error.localizedDescription` por archivo en vez de solo el nombre
   (D1). Test que fuerza un fallo de "mover carpeta dentro de sí misma"
   en un batch con al menos un éxito, verificando que el mensaje agregado
   contiene el motivo real, no solo el nombre.
3. Nuevo `Sources/Dotphin/Services/TemplateProvider.swift`
   (`customTemplates()`, `templatesDirectory`,
   `revealOrCreateTemplatesDirectory()`). Tests en un `TemplateProviderTests.swift`
   nuevo: carpeta sin crear → lista vacía sin crashear; carpeta con 2
   archivos y 1 subcarpeta → solo los 2 archivos, ignorando la subcarpeta
   y los dotfiles.
4. `DotphinContextMenus.swift`: extender `createNewMenu` (las 2 copias)
   con los templates custom + el ítem "Abrir carpeta de plantillas…";
   agregar `onNewFileFromTemplatePrompt` y `onMountDiskImage` a
   `BrowserContextMenuActions`; agregar el ítem "Montar imagen de disco"
   en `DotphinItemContextMenu` cuando `DiskImageMountService.isDiskImage`
   es true para el único ítem seleccionado.
5. Nuevo `Sources/Dotphin/Services/DiskImageMountService.swift`
   (`isDiskImage(_:)`, `mount(_:) throws`, shell-out a `hdiutil attach`
   con el orden correcto stderr→waitUntilExit). Tests en
   `DiskImageMountServiceTests.swift`: `isDiskImage` para las 4
   extensiones + negativos; `mount` sobre un path inexistente debe
   lanzar `.failed` con un mensaje no vacío (sin montar nada real, mismo
   precedente que `VolumeEjectServiceTests`/`TerminalLauncherTests` de no
   ejecutar la acción real contra hardware/discos en CI).
6. `BrowserViewModel.mountDiskImage(_:)`: envuelve el service, posta
   `.placesBookmarksDidChange` en éxito, setea `operationError` en
   fallo. Wiring en `BrowserView` para pasar `onMountDiskImage` a
   `menuActions`.
7. `FilePropertiesSheetView`: toggle "Aplicar a subcarpetas y su
   contenido" (solo si `isDirectory`) + propagación recursiva en
   `togglePermissionBit` + nota de texto sobre el bit de ejecución.
   Test (en un target testeable, ej. extrayendo la lógica recursiva a un
   `nonisolated static func applyPermissionsRecursively(_:under:)`
   testeable sin SwiftUI): aplica un modo a un árbol con 1 subcarpeta y 2
   archivos, verifica que los 3 quedan con el nuevo modo.
8. `DetailsListView`: migrar a `Table(of: ExpandableDetailRow.self,
   selection: $selection) { columns } rows: { ForEach(flattenedRows) {
   row in TableRow(row) ... } }`, moviendo `.draggable(row.item.url)` y
   `.dropDestination(for: URL.self)` al nivel de `TableRow` en vez de
   solo en la columna "Nombre". Mantener intactos
   `.contextMenu(forSelectionType:)` y `primaryAction`. Tests: los
   existentes de `DetailsListView` (si hay alguno a nivel de snapshot/
   render) deben seguir pasando; si no hay ninguno de UI, al menos un
   test de que `onMoveDropped` se sigue invocando con los mismos
   argumentos que antes para el caso de columna "Nombre" (regression,
   mismo nivel de lo que ya cubre `FileOperationsServiceTests`).
9. `swift build && swift test` verde. Actualizar `docs/decisions.md` con
   el resultado del review de este slice (igual que los anteriores) y
   marcar los 3 ítems de deuda de slice 15 como resueltos (D3 con la nota
   de verificación manual pendiente).

## Review Focus

- Confirmar que D2 no rompe el guard existente de "mover carpeta dentro
  de sí misma por path literal" (el guard de prefijo `hasPrefix(sourcePath + "/")`
  sigue necesitando sourcePath ya resuelto, no el original).
- Confirmar que el toggle recursivo de permisos no deja el árbol en un
  estado parcialmente aplicado sin avisar si falla a mitad de camino
  (archivos sin permiso de escritura del usuario, por ejemplo).
- Confirmar con una sonda real contra el SDK (no solo lectura) que
  `TableRowContent.draggable`/`.dropDestination` compilan y no rompen
  `.contextMenu(forSelectionType:)` en la sintaxis `Table(rows:)` — el
  mismo tipo de verificación que cerró la duda de slice 15.
- Señalar explícitamente en el reporte el checklist de verificación
  manual de D3 (selección por click fuera de "Nombre", doble click,
  drag desde otra columna) — no se puede dar por cerrado sin eso.
