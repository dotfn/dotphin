import AppKit
import SwiftUI

struct DiskUsageEntry: Identifiable, Equatable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let sizeBytes: Int64
    var id: URL { url }
}

/// Built-in disk space analyzer inspired by KDE Dolphin's `DiskSpaceUsageMenu` / Filelight integration
/// (`src/statusbar/diskspaceusagemenu.cpp`).
struct DiskUsageAnalyzerSheetView: View {
    let directoryURL: URL
    var onNavigateToFolder: ((URL) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DiskUsageEntry] = []
    @State private var totalBytes: Int64 = 0
    @State private var isCalculating = true

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estadísticas de uso de disco — \(directoryURL.lastPathComponent.isEmpty ? "/" : directoryURL.lastPathComponent)")
                        .font(.headline)
                    Text(directoryURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !isCalculating {
                    Text("Total: \(Self.byteFormatter.string(fromByteCount: totalBytes))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }

            Divider()

            if isCalculating {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Analizando el uso de espacio en «\(directoryURL.lastPathComponent)»…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Carpeta vacía",
                    systemImage: "folder",
                    description: Text("No hay elementos con tamaño medible en esta carpeta.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    let fraction = totalBytes > 0 ? Double(entry.sizeBytes) / Double(totalBytes) : 0
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f%%", fraction * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(Self.byteFormatter.string(fromByteCount: entry.sizeBytes))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .frame(width: 78, alignment: .trailing)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.10))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(barColor(for: fraction))
                                        .frame(width: max(4, geo.size.width * fraction), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }

                        if entry.isDirectory, let onNavigateToFolder {
                            Button {
                                onNavigateToFolder(entry.url)
                                dismiss()
                            } label: {
                                Image(systemName: "arrow.right.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Abrir carpeta en Dolphin")
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            HStack {
                Button("Abrir Utilidad de Discos…") {
                    let diskUtilURL = URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")
                    NSWorkspace.shared.openApplication(at: diskUtilURL, configuration: NSWorkspace.OpenConfiguration())
                }
                Spacer()
                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 540, height: 440)
        .task(id: directoryURL) {
            isCalculating = true
            let target = directoryURL
            let computed = await Task.detached(priority: .userInitiated) {
                Self.analyzeDirectory(target)
            }.value
            guard !Task.isCancelled else { return }
            entries = computed
            totalBytes = computed.reduce(0) { $0 + $1.sizeBytes }
            isCalculating = false
        }
    }

    private func barColor(for fraction: Double) -> Color {
        if fraction > 0.5 { return .orange }
        if fraction > 0.25 { return .blue }
        return .teal
    }

    nonisolated static func analyzeDirectory(_ directory: URL) -> [DiskUsageEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [DiskUsageEntry] = []
        for url in urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = FilePropertiesSheetView.computeTotalSize(of: url) ?? 0
            results.append(
                DiskUsageEntry(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: isDir,
                    sizeBytes: size
                )
            )
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
