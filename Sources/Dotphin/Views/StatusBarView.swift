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
        let noun = itemCount == 1 ? String(localized: "ítem", bundle: #bundle) : String(localized: "ítems", bundle: #bundle)
        let totalNoun = totalCount == 1 ? String(localized: "ítem", bundle: #bundle) : String(localized: "ítems", bundle: #bundle)
        let base = itemCount == totalCount
            ? String(localized: "\(itemCount) \(noun)", bundle: #bundle)
            : String(localized: "\(itemCount) de \(totalCount) \(totalNoun)", bundle: #bundle)
        guard selectedCount > 0 else { return base }
        if selectedCount == 1, let item = singleSelectedItem {
            let meta = FileMetadataFormatter().metadata(for: item)
            if item.isDirectory {
                return String(localized: "\(base) — «\(item.name)» (\(meta.kind))", bundle: #bundle)
            } else {
                return String(localized: "\(base) — «\(item.name)» (\(meta.kind), \(meta.sizeText))", bundle: #bundle)
            }
        }
        let selNoun = selectedCount == 1 ? String(localized: "seleccionado", bundle: #bundle) : String(localized: "seleccionados", bundle: #bundle)
        if let bytes = selectedTotalBytes, bytes > 0 {
            let formatted = Self.sizeFormatter.string(fromByteCount: bytes)
            return String(localized: "\(base) — \(selectedCount) \(selNoun) (\(formatted))", bundle: #bundle)
        }
        return String(localized: "\(base) — \(selectedCount) \(selNoun)", bundle: #bundle)
    }

    private var capacityText: String {
        availableCapacity.map { String(localized: "\(Self.sizeFormatter.string(fromByteCount: $0)) libres", bundle: #bundle) } ?? "—"
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
                        Text(String(localized: "Seleccionar", bundle: #bundle))
                            .foregroundStyle(isSelectionModeActive.wrappedValue ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(String(localized: "Alternar modo de selección de Dolphin", bundle: #bundle))
                .accessibilityLabel(String(localized: "Modo de selección", bundle: #bundle))

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
                    .help(String(localized: "Reducir zoom", bundle: #bundle))

                    Slider(value: zoomLevel, in: 0.5...2.0)
                        .controlSize(.small)
                        .frame(width: 96)
                        .help(String(localized: "Tamaño de vista", bundle: #bundle))
                        .accessibilityLabel(String(localized: "Tamaño de vista", bundle: #bundle))

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            zoomLevel.wrappedValue = min(2.0, zoomLevel.wrappedValue + 0.1)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Aumentar zoom", bundle: #bundle))

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            zoomLevel.wrappedValue = 1.0
                        }
                    } label: {
                        Text(String(localized: "\(Int(round(zoomLevel.wrappedValue * 100)))%", bundle: #bundle))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.15), value: Int(round(zoomLevel.wrappedValue * 100)))
                            .frame(width: 36, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Restablecer zoom al 100%", bundle: #bundle))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if displayMode == .fullWidth {
                Divider()
                    .frame(height: 12)

                Menu {
                    if let total = totalCapacity, let free = availableCapacity {
                        let used = max(0, total - free)
                        Text(String(localized: "Usado: \(Self.sizeFormatter.string(fromByteCount: used)) de \(Self.sizeFormatter.string(fromByteCount: total))", bundle: #bundle))
                        Text(String(localized: "Libre: \(Self.sizeFormatter.string(fromByteCount: free))", bundle: #bundle))
                        Divider()
                    }
                    if let onOpenDiskUsageAnalyzer {
                        Button {
                            onOpenDiskUsageAnalyzer()
                        } label: {
                            Label(String(localized: "Estadísticas de uso de la carpeta actual…", bundle: #bundle), systemImage: "chart.pie")
                        }
                    }
                    Button {
                        let diskUtilURL = URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")
                        NSWorkspace.shared.openApplication(at: diskUtilURL, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label(String(localized: "Abrir Utilidad de Discos…", bundle: #bundle), systemImage: "internaldrive")
                    }
                    if let onEmptyTrash {
                        Divider()
                        Button(role: .destructive) {
                            onEmptyTrash()
                        } label: {
                            Label(String(localized: "Vaciar la Papelera…", bundle: #bundle), systemImage: "trash.slash")
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
                .help(String(localized: "Espacio libre en disco — clic para ver estadísticas de uso", bundle: #bundle))
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
                        zoomLevel != nil ? "Mostrar deslizador de zoom ✓" : String(localized: "Mostrar deslizador de zoom", bundle: #bundle),
                        systemImage: "magnifyingglass"
                    )
                }
            }
            if let onChangeDisplayMode {
                Menu(String(localized: "Estilo de barra de estado", bundle: #bundle)) {
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
                Label(String(localized: "Copiar texto de estado", bundle: #bundle), systemImage: "doc.on.doc")
            }
        }
    }
}
