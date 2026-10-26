# SDD ledger — plan: docs/superpowers/plans/2026-10-25-slice2-vistas-zoom-orden.md

Spec: docs/superpowers/specs/2026-10-25-dolphin-macos-design.md (leída)

## Pre-flight
- Task 2 <- Task 1 (SortField). Task 3 <- Task 1, 2 (ViewPropertiesStore, DirectoryReader overload). Task 4 <- Task 1, 3. Firmas revisadas al escribir el plan, consistentes.
Task 1: complete
Task 2: complete
Task 3: complete, ruling: extracted shared sort comparator to avoid duplication (not literally in plan, DRY call)
Task 4: complete. Consultado axiom-swiftui (containers-ref.md "File Browser"/LazyVGrid) y axiom-macos (swiftui-differences.md, Table) antes de implementar — confirman LazyVGrid para grid de iconos y Table(items) { TableColumn } para detalles. Ruling: no usé el sortOrder nativo de Table (column-click-to-sort) para no duplicar el control de orden con el Menu de la toolbar — un solo camino de orden (Menu) alimenta BrowserViewModel.setSort para los 3 modos.
Task 5: suite completa 26/26, build limpio, smoke run sin crash.
