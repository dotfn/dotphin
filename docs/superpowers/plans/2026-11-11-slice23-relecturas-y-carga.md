# Slice 23 — Relecturas en ráfaga y carga al arrancar (issue #2)

## Lo que mostró el registro del usuario (2026-11-11)

- Arranque: `contentsOfDirectory` de la carpeta personal tardó 3076 ms en el
  hilo principal; la ventana quedó ~4 s trabada.
- Cientos de `cambio en disco en mbook` → `load(mbook)`, a veces decenas por
  segundo, cada uno duplicado. La causa: archivos ocultos de la carpeta
  personal que otras apps reescriben (`~/.claude.json` con un temporal y un
  renombre: 60 ↔ 61 entradas mientras se ven 12), y cada pestaña que alguna
  vez se mostró sigue observando su carpeta (`watchesCurrentDirectory` se
  prende y nunca se apaga).
- Tras las ráfagas, el hilo principal queda bloqueado 400–900 ms aunque cada
  lectura tarda pocos ms: cada relectura reasigna `items`, `availableCapacity`
  y `isCurrentDirectoryWritable` aunque no cambien, y `@Observable` avisa igual.

## Decisiones

- Axiom consultado: `axiom-concurrency` → `swift-concurrency.md` (`@concurrent`
  para sacar trabajo del main actor; `async` solo no cambia de hilo).
- Una sola lectura pura, `nonisolated` y `@concurrent`, que devuelve un
  `DirectoryLoadResult` Sendable (ítems o error, espacio libre, si se puede
  escribir). La usa tanto la carga sincrónica como la de segundo plano.
- Aplicar el resultado solo cambia lo que cambió (ítems iguales → no se toca
  `items`).
- Contador de generación: un resultado viejo (se navegó o se refrescó mientras
  tanto) se descarta.
- Navegar en segundo plano: los `BrowserViewModel` que crea `TabsViewModel`
  (la app) cargan en segundo plano; los tests que construyen un view model
  suelto siguen sincrónicos (`loadsInBackground: false` por defecto), así sus
  aserciones sobre `items` siguen siendo inmediatas. Mientras carga:
  `isLoadingDirectory`, ítems vacíos y un indicador en la vista.
- Navegar y seleccionar (abrir carpeta contenedora, ir al destino de un
  enlace, hoja de propiedades): `navigate(to:selecting:)` aplica la selección
  cuando llega el resultado.
- `refresh()` después de una operación propia sigue sincrónico (la carpeta ya
  está en caché y la vista selecciona lo creado enseguida).
- Cambios en disco: se agrupan (una relectura pendiente a la vez, 0,25 s) y se
  leen en segundo plano. FSEvents con eventos por archivo: si solo cambiaron
  ocultos y no se muestran, no se relee.
- Solo observa la pestaña visible: `BrowserView` apaga el observador al
  desaparecer; al volver a aparecer se relee una vez en segundo plano.

## Pasos (TDD)

1. Tests: ítems iguales no tocan `items`; resultado viejo descartado; navegar
   en segundo plano deja `isLoadingDirectory` y luego los ítems;
   `navigate(to:selecting:)` selecciona al terminar; ráfaga de cambios → una
   relectura; cambio solo de ocultos sin mostrarlos → ninguna; apagar el
   observador lo detiene.
2. Implementación en `DirectoryWatcher`, `BrowserViewModel`, `TabsViewModel`,
   `BrowserView`/`ContentView`.
3. `swift test` (código de salida), `.app`, revisión independiente, merge.
