import SwiftUI

struct ToolbarConfigurationSheetView: View {
    @Binding var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            ToolbarConfigurationEditorView(settings: $settings)

            Divider()

            HStack {
                Spacer()
                Button("Aceptar") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 470, idealHeight: 500)
    }
}

struct ToolbarConfigurationEditorView: View {
    @Binding var settings: AppSettings

    @State private var entries: [ToolbarConfigEntry] = []
    @State private var availableFilter: String = ""
    @State private var currentFilter: String = ""
    @State private var selectedAvailableID: String?
    @State private var selectedCurrentID: String?

    private var availableEntries: [ToolbarConfigEntry] {
        var result: [ToolbarConfigEntry] = [
            .divider(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            .fixedSpacer(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
            .separator(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        ]
        let activeActions = Set(entries.compactMap { entry -> ToolbarActionItem? in
            if case .action(let item) = entry { return item }
            return nil
        })
        for item in ToolbarActionItem.allCases where !activeActions.contains(item) {
            result.append(.action(item))
        }
        let trimmed = availableFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        return result.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var filteredCurrentEntries: [ToolbarConfigEntry] {
        let trimmed = currentFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var selectedCurrentAction: ToolbarActionItem? {
        guard let selectedCurrentID,
              let entry = entries.first(where: { $0.id == selectedCurrentID }),
              case .action(let item) = entry else {
            return nil
        }
        return item
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disposición de elementos de la barra (estilo KDE Dolphin)")
                        .font(.headline)
                    Text("Agrega divisores (|), espacios (Divider Space), separadores de grupo o reordena acciones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Posición del texto:", selection: $settings.toolbarTextPosition) {
                    ForEach(ToolbarTextPosition.allCases, id: \.self) { pos in
                        Text(pos.title).tag(pos)
                    }
                }
                .frame(width: 260)
                .onChange(of: settings.toolbarTextPosition) { _, newPos in
                    settings.showsToolbarLabels = (newPos == .textAlongsideIcons)
                }
            }

            HStack(spacing: 12) {
                // Left column: Available actions & layout elements
                VStack(alignment: .leading, spacing: 6) {
                    Text("Acciones y separadores disponibles:")
                        .font(.subheadline.weight(.semibold))

                    TextField("Filtrar disponibles…", text: $availableFilter)
                        .textFieldStyle(.roundedBorder)
                        .fixedSize(horizontal: false, vertical: true)
                        .transaction { $0.animation = nil }

                    List(selection: $selectedAvailableID) {
                        ForEach(availableEntries, id: \.id) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: entry.systemImage)
                                    .frame(width: 18)
                                    .foregroundStyle(isLayoutEntry(entry) ? Color.accentColor : .primary)
                                Text(entry.title)
                                    .font(isLayoutEntry(entry) ? .callout.weight(.medium) : .callout)
                                    .foregroundStyle(isLayoutEntry(entry) ? Color.accentColor : .primary)
                                Spacer()
                            }
                            .tag(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedAvailableID = entry.id
                                addSelectedAvailable()
                            }
                        }
                    }
                    .listStyle(.bordered)
                }
                .frame(minWidth: 245, maxHeight: .infinity)

                // Center buttons: Add / Remove / Up / Down
                VStack(spacing: 10) {
                    Spacer()

                    Button {
                        moveSelectedCurrent(offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(!canMoveSelectedCurrent(offset: -1))
                    .help("Mover arriba (a la izquierda en la barra)")

                    Button {
                        addSelectedAvailable()
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(selectedAvailableID == nil)
                    .help("Añadir a las acciones actuales")

                    Button {
                        removeSelectedCurrent()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(!canRemoveSelectedCurrent)
                    .help("Quitar de las acciones actuales")

                    Button {
                        moveSelectedCurrent(offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(!canMoveSelectedCurrent(offset: 1))
                    .help("Mover abajo (a la derecha en la barra)")

                    Spacer()
                }

                // Right column: Current actions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Acciones actuales en la barra:")
                        .font(.subheadline.weight(.semibold))

                    TextField("Filtrar actuales…", text: $currentFilter)
                        .textFieldStyle(.roundedBorder)
                        .fixedSize(horizontal: false, vertical: true)
                        .transaction { $0.animation = nil }

                    List(selection: $selectedCurrentID) {
                        ForEach(filteredCurrentEntries, id: \.id) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: entry.systemImage)
                                    .frame(width: 18)
                                    .foregroundStyle(isLayoutEntry(entry) ? Color.accentColor : .primary)
                                Text(entry.title)
                                    .font(isLayoutEntry(entry) ? .callout.italic() : .callout)
                                    .foregroundStyle(isLayoutEntry(entry) ? Color.accentColor : .primary)
                                Spacer()
                                if case .action(let item) = entry,
                                   settings.showsLabel(for: item) {
                                    Text("Texto visible")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                                }
                            }
                            .tag(entry.id)
                        }
                        .onMove { source, destination in
                            guard currentFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            entries.move(fromOffsets: source, toOffset: destination)
                            syncEntriesToSettings()
                        }
                    }
                    .listStyle(.bordered)

                    // Per-item text alongside icon toggle (KDE Dolphin style)
                    if let selectedItem = selectedCurrentAction {
                        HStack {
                            Toggle(
                                "Mostrar texto al costado del icono «\(selectedItem.title)»",
                                isOn: Binding(
                                    get: { settings.showsLabel(for: selectedItem) },
                                    set: { _ in settings.toggleLabel(for: selectedItem) }
                                )
                            )
                            .font(.callout)
                            Spacer()
                        }
                        .padding(.top, 2)
                    } else {
                        Text("Doble clic en un Divisor o Espacio disponible para insertarlo tras la acción seleccionada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(minWidth: 280, maxHeight: .infinity)
            }

            HStack {
                Button("Restablecer valores predeterminados") {
                    settings.resetToolbarToDefaults()
                    entries = settings.activeConfigEntries()
                }

                Toggle("Bloquear posiciones en la barra", isOn: $settings.isToolbarLocked)
                    .padding(.leading, 12)

                Spacer()
            }
        }
        .onAppear {
            entries = settings.activeConfigEntries()
        }
        .onChange(of: settings) { _, _ in
            let latest = settings.activeConfigEntries()
            if latest.map(\.title) != entries.map(\.title) {
                entries = latest
            }
        }
    }

    private func isLayoutEntry(_ entry: ToolbarConfigEntry) -> Bool {
        switch entry {
        case .divider, .fixedSpacer, .separator, .expandingSpacer:
            return true
        case .action:
            return false
        }
    }

    private func isSpacerEntry(_ entry: ToolbarConfigEntry) -> Bool {
        switch entry {
        case .fixedSpacer, .expandingSpacer:
            return true
        default:
            return false
        }
    }

    private var canRemoveSelectedCurrent: Bool {
        guard let selectedCurrentID,
              let entry = entries.first(where: { $0.id == selectedCurrentID }) else {
            return false
        }
        if case .action = entry {
            let actionCount = entries.reduce(0) { count, item in
                if case .action = item { return count + 1 }
                return count
            }
            return actionCount > 1
        }
        return true
    }

    private func canMoveSelectedCurrent(offset: Int) -> Bool {
        guard let selectedCurrentID,
              let idx = entries.firstIndex(where: { $0.id == selectedCurrentID }) else {
            return false
        }
        let target = idx + offset
        return entries.indices.contains(target)
    }

    private func moveSelectedCurrent(offset: Int) {
        guard let selectedCurrentID,
              let idx = entries.firstIndex(where: { $0.id == selectedCurrentID }) else {
            return
        }
        let target = idx + offset
        guard entries.indices.contains(target) else { return }

        if isSpacerEntry(entries[idx]), case .action = entries[target] {
            let movingEntry = entries[idx]
            // Leave a group separator behind if needed so the two groups don't accidentally merge
            let prevIsAction = idx > 0 && { if case .action = entries[idx - 1] { return true }; return false }()
            let nextIsAction = idx + 1 < entries.count && { if case .action = entries[idx + 1] { return true }; return false }()
            if prevIsAction && nextIsAction {
                entries[idx] = .separator(UUID())
                let newInsertIdx = offset > 0 ? min(entries.count, target + 1) : max(0, target)
                entries.insert(movingEntry, at: newInsertIdx)
                // Clean up adjacent redundant separator at destination
                if let movedIdx = entries.firstIndex(where: { $0.id == movingEntry.id }) {
                    if movedIdx + 1 < entries.count, case .separator = entries[movedIdx + 1] {
                        entries.remove(at: movedIdx + 1)
                    } else if movedIdx > 0, case .separator = entries[movedIdx - 1] {
                        entries.remove(at: movedIdx - 1)
                    }
                }
            } else {
                entries.swapAt(idx, target)
            }
        } else {
            entries.swapAt(idx, target)
        }
        syncEntriesToSettings()
    }

    private func addSelectedAvailable() {
        guard let selectedAvailableID,
              let sourceEntry = availableEntries.first(where: { $0.id == selectedAvailableID }) else {
            return
        }
        let entryToInsert: ToolbarConfigEntry
        switch sourceEntry {
        case .divider:
            entryToInsert = .divider(UUID())
        case .fixedSpacer:
            entryToInsert = .fixedSpacer(UUID())
        case .separator:
            entryToInsert = .separator(UUID())
        case .expandingSpacer:
            entryToInsert = .expandingSpacer
        case .action(let item):
            entryToInsert = .action(item)
        }

        if let selectedCurrentID,
           let currentIdx = entries.firstIndex(where: { $0.id == selectedCurrentID }) {
            if isSpacerEntry(entryToInsert), case .separator = entries[currentIdx] {
                entries[currentIdx] = entryToInsert
            } else if isSpacerEntry(entryToInsert),
                      currentIdx + 1 < entries.count,
                      case .separator = entries[currentIdx + 1] {
                entries[currentIdx + 1] = entryToInsert
            } else {
                entries.insert(entryToInsert, at: currentIdx + 1)
            }
        } else {
            entries.append(entryToInsert)
        }
        selectedCurrentID = entryToInsert.id
        syncEntriesToSettings()
    }

    private func removeSelectedCurrent() {
        guard canRemoveSelectedCurrent,
              let selectedCurrentID,
              let idx = entries.firstIndex(where: { $0.id == selectedCurrentID }) else {
            return
        }
        let removed = entries[idx]
        let prevIsAction = idx > 0 && { if case .action = entries[idx - 1] { return true }; return false }()
        let nextIsAction = idx + 1 < entries.count && { if case .action = entries[idx + 1] { return true }; return false }()

        if isSpacerEntry(removed) && prevIsAction && nextIsAction {
            let replacement = ToolbarConfigEntry.separator(UUID())
            entries[idx] = replacement
            self.selectedCurrentID = replacement.id
        } else {
            entries.remove(at: idx)
            if entries.indices.contains(idx) {
                self.selectedCurrentID = entries[idx].id
            } else {
                self.selectedCurrentID = entries.last?.id
            }
        }
        syncEntriesToSettings()
    }

    private func syncEntriesToSettings() {
        settings.applyConfigEntries(entries)
    }
}
