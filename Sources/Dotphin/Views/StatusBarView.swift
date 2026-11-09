import AppKit
import SwiftUI

struct StatusBarView: View {
    let itemCount: Int
    let totalCount: Int
    var selectedCount: Int = 0
    var selectedTotalBytes: Int64? = nil
    var singleSelectedItem: FileItem? = nil
    let availableCapacity: Int64?
    var totalCapacity: Int64? = nil
    var displayMode: StatusBarDisplayMode = .fullWidth
    var zoomLevel: Binding<Double>?
    var isSelectionModeActive: Binding<Bool>? = nil
    var onOpenDiskUsageAnalyzer: (() -> Void)? = nil
    var onEmptyTrash: (() -> Void)? = nil
    var onToggleZoomSlider: (() -> Void)? = nil
    var onChangeDisplayMode: ((StatusBarDisplayMode) -> Void)? = nil

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var statusSummaryText: String {
        let noun = itemCount == 1 ? "ítem" : "ítems"
        let totalNoun = totalCount == 1 ? "ítem" : "ítems"
        let base = itemCount == totalCount ? "\(itemCount) \(noun)" : "\(itemCount) de \(totalCount) \(totalNoun)"
        guard selectedCount > 0 else { return base }
        if selectedCount == 1, let item = singleSelectedItem {
            let meta = FileMetadataFormatter().metadata(for: item)
            if item.isDirectory {
                return "\(base) — «\(item.name)» (\(meta.kind))"
            } else {
                return "\(base) — «\(item.name)» (\(meta.kind), \(meta.sizeText))"
            }
        }
        let selNoun = selectedCount == 1 ? "seleccionado" : "seleccionados"
        if let bytes = selectedTotalBytes, bytes > 0 {
            let formatted = Self.sizeFormatter.string(fromByteCount: bytes)
            return "\(base) — \(selectedCount) \(selNoun) (\(formatted))"
        }
        return "\(base) — \(selectedCount) \(selNoun)"
    }

    private var capacityText: String {
        availableCapacity.map { "\(Self.sizeFormatter.string(fromByteCount: $0)) libres" } ?? "—"
    }

    private var usedFraction: Double? {
        guard let total = totalCapacity, let free = availableCapacity, total > 0 else { return nil }
        let used = max(0, total - free)
        return min(1.0, Double(used) / Double(total))
    }

    var body: some View {
        HStack(spacing: 12) {
            if let isSelectionModeActive {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isSelectionModeActive.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSelectionModeActive.wrappedValue ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(isSelectionModeActive.wrappedValue ? Color.accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text("Seleccionar")
                            .foregroundStyle(isSelectionModeActive.wrappedValue ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Alternar modo de selección de Dolphin")
                .accessibilityLabel("Modo de selección")

                Divider()
                    .frame(height: 12)
            }

            Text(statusSummaryText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: statusSummaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if displayMode == .fullWidth, let zoomLevel {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            zoomLevel.wrappedValue = max(0.5, zoomLevel.wrappedValue - 0.1)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reducir zoom")

                    Slider(value: zoomLevel, in: 0.5...2.0)
                        .controlSize(.small)
                        .frame(width: 96)
                        .help("Tamaño de vista")
                        .accessibilityLabel("Tamaño de vista")

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            zoomLevel.wrappedValue = min(2.0, zoomLevel.wrappedValue + 0.1)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Aumentar zoom")

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            zoomLevel.wrappedValue = 1.0
                        }
                    } label: {
                        Text("\(Int(round(zoomLevel.wrappedValue * 100)))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.15), value: Int(round(zoomLevel.wrappedValue * 100)))
                            .frame(width: 36, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .help("Restablecer zoom al 100%")
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if displayMode == .fullWidth {
                Divider()
                    .frame(height: 12)

                Menu {
                    if let total = totalCapacity, let free = availableCapacity {
                        let used = max(0, total - free)
                        Text("Usado: \(Self.sizeFormatter.string(fromByteCount: used)) de \(Self.sizeFormatter.string(fromByteCount: total))")
                        Text("Libre: \(Self.sizeFormatter.string(fromByteCount: free))")
                        Divider()
                    }
                    if let onOpenDiskUsageAnalyzer {
                        Button {
                            onOpenDiskUsageAnalyzer()
                        } label: {
                            Label("Estadísticas de uso de la carpeta actual…", systemImage: "chart.pie")
                        }
                    }
                    Button {
                        let diskUtilURL = URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")
                        NSWorkspace.shared.openApplication(at: diskUtilURL, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label("Abrir Utilidad de Discos…", systemImage: "internaldrive")
                    }
                    if let onEmptyTrash {
                        Divider()
                        Button(role: .destructive) {
                            onEmptyTrash()
                        } label: {
                            Label("Vaciar la Papelera…", systemImage: "trash.slash")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let fraction = usedFraction {
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.14))
                                    .frame(width: 44, height: 5)
                                Capsule()
                                    .fill(fraction > 0.9 ? Color.orange : Color.accentColor)
                                    .frame(width: max(4, 44 * fraction), height: 5)
                            }
                        }
                        Text(capacityText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Espacio libre en disco — clic para ver estadísticas de uso")
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .contextMenu {
            if let onToggleZoomSlider {
                Button {
                    onToggleZoomSlider()
                } label: {
                    Label(
                        zoomLevel != nil ? "Mostrar deslizador de zoom ✓" : "Mostrar deslizador de zoom",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            if let onChangeDisplayMode {
                Menu("Estilo de barra de estado") {
                    ForEach(StatusBarDisplayMode.allCases) { mode in
                        Button {
                            onChangeDisplayMode(mode)
                        } label: {
                            HStack {
                                Text(mode.title)
                                if displayMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(statusSummaryText, forType: .string)
            } label: {
                Label("Copiar texto de estado", systemImage: "doc.on.doc")
            }
        }
    }
}
