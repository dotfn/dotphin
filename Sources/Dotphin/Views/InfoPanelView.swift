import AppKit
import AVFoundation
import ImageIO
import SwiftUI

struct InfoPanelView: View {
    let item: FileItem?
    var selectedCount: Int = 0
    var selectedTotalBytes: Int64? = nil
    var onShowProperties: ((URL) -> Void)? = nil
    var onColorTagChanged: ((FinderColorTag) -> Void)? = nil

    @State private var thumbnail: NSImage?
    @State private var folderSizeText: String?
    @State private var posixPermissionsText: String?
    @State private var imageDimensionsText: String?
    @State private var textPreviewSnippet: String?
    @State private var finderComment: String = ""
    @State private var activeColorTag: FinderColorTag = .none

    // MediaWidget state (`src/panels/information/mediawidget.cpp`)
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlayingMedia: Bool = false
    @State private var mediaDuration: TimeInterval = 0
    @State private var mediaCurrentTime: TimeInterval = 0

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        if let item {
            let meta = FileMetadataFormatter().metadata(for: item)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 10) {
                        Group {
                            if let thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            } else {
                                Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .frame(width: 96, height: 96)
                        .task(id: item.url) {
                            stopMediaPlayback()
                            thumbnail = nil
                            folderSizeText = nil
                            posixPermissionsText = nil
                            imageDimensionsText = nil
                            textPreviewSnippet = nil
                            activeColorTag = item.colorTag
                            finderComment = FolderIconAndTagService().getFinderComment(for: item.url)

                            if let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path),
                               let perms = attrs[.posixPermissions] as? NSNumber {
                                posixPermissionsText = FilePropertiesSheetView.symbolicPermissions(perms.intValue)
                            }
                            if item.isDirectory {
                                let targetURL = item.url
                                let computed = await Task.detached(priority: .utility) { () -> String in
                                    guard let bytes = FilePropertiesSheetView.computeTotalSize(of: targetURL) else {
                                        return "—"
                                    }
                                    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                                }.value
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeOut(duration: 0.16)) {
                                    folderSizeText = computed
                                }
                            } else {
                                imageDimensionsText = Self.readImageDimensions(for: item.url)
                                textPreviewSnippet = Self.readTextPreviewSnippet(for: item)
                                prepareMediaIfApplicable(for: item)
                                let image = await ThumbnailLoader().thumbnail(for: item.url, size: CGSize(width: 192, height: 192))
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeOut(duration: 0.18)) {
                                    thumbnail = image
                                }
                            }
                        }
                        .onDisappear {
                            stopMediaPlayback()
                        }

                        Text(item.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)

                    if mediaDuration > 0 {
                        mediaPlayerCard(for: item)
                    }

                    if let textPreviewSnippet {
                        textPreviewCard(textPreviewSnippet)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Tipo", value: meta.kind)
                        LabeledContent(
                            "Tamaño",
                            value: item.isDirectory ? (folderSizeText ?? "Calculando…") : meta.sizeText
                        )
                        if let imageDimensionsText {
                            LabeledContent("Dimensiones", value: imageDimensionsText)
                        }
                        LabeledContent("Modificado", value: meta.modifiedText)
                        if let posixPermissionsText {
                            LabeledContent("Permisos") {
                                Text(posixPermissionsText)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Ubicación") {
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.subheadline)

                    Divider()

                    // Inline Tags & Comments (`Baloo::FileMetaDataWidget`)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Etiqueta de color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(FinderColorTag.allCases) { tag in
                                Button {
                                    withAnimation(.snappy(duration: 0.16)) {
                                        activeColorTag = tag
                                    }
                                    try? FolderIconAndTagService().setColorTag(tag, for: item.url)
                                    onColorTagChanged?(tag)
                                } label: {
                                    ZStack {
                                        if let nsColor = tag.nsColor {
                                            Circle()
                                                .fill(Color(nsColor: nsColor))
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Circle()
                                                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.2)
                                                .frame(width: 16, height: 16)
                                        }
                                        if activeColorTag == tag {
                                            Image(systemName: tag == .none ? "xmark" : "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(tag == .none ? Color.secondary : Color.white)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .scaleEffect(activeColorTag == tag ? 1.14 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .help(tag.title)
                            }
                        }

                        Text("Comentario")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        HStack(spacing: 6) {
                            TextField("Añadir comentario de Spotlight…", text: $finderComment)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .onSubmit {
                                    _ = FolderIconAndTagService().setFinderComment(finderComment, for: item.url)
                                }
                            Button {
                                _ = FolderIconAndTagService().setFinderComment(finderComment, for: item.url)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Guardar comentario")
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            QuickLookPreviewController.shared.present(items: [item], startIndex: 0)
                        } label: {
                            Label("Vista rápida (Espacio)", systemImage: "eye")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .controlSize(.small)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Label("Mostrar en Finder", systemImage: "macwindow")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .controlSize(.small)

                        if let onShowProperties {
                            Button {
                                onShowProperties(item.url)
                            } label: {
                                Label("Propiedades y sumas de verificación…", systemImage: "info.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .controlSize(.small)
                        }
                    }

                    Spacer()
                }
                .padding()
                .animation(.snappy(duration: 0.2), value: item.id)
            }
            .transition(.opacity)
        } else if selectedCount > 1 {
            VStack(spacing: 12) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: selectedCount)
                Text("\(selectedCount) ítems seleccionados")
                    .font(.headline)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: selectedCount)
                if let bytes = selectedTotalBytes, bytes > 0 {
                    Text(Self.sizeFormatter.string(fromByteCount: bytes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .transition(.opacity)
        } else {
            ContentUnavailableView(
                "Nada seleccionado",
                systemImage: "sidebar.right",
                description: Text("Seleccioná un archivo o carpeta para ver su vista previa y metadatos.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func mediaPlayerCard(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleMediaPlayback()
                } label: {
                    Image(systemName: isPlayingMedia ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { mediaCurrentTime },
                            set: { newTime in
                                mediaCurrentTime = newTime
                                audioPlayer?.currentTime = newTime
                            }
                        ),
                        in: 0...max(mediaDuration, 0.1)
                    )
                    .controlSize(.mini)

                    HStack {
                        Text(Self.formatDuration(mediaCurrentTime))
                        Spacer()
                        Text(Self.formatDuration(mediaDuration))
                    }
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private func textPreviewCard(_ snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vista previa de texto")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(snippet)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func prepareMediaIfApplicable(for item: FileItem) {
        guard SearchTypeFilter.audio.matches(item) || SearchTypeFilter.video.matches(item) else { return }
        if let player = try? AVAudioPlayer(contentsOf: item.url) {
            player.prepareToPlay()
            audioPlayer = player
            mediaDuration = player.duration
            mediaCurrentTime = 0
        }
    }

    private func toggleMediaPlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlayingMedia = false
        } else {
            player.play()
            isPlayingMedia = true
        }
        mediaCurrentTime = player.currentTime
    }

    private func stopMediaPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingMedia = false
        mediaDuration = 0
        mediaCurrentTime = 0
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(round(seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    nonisolated static func readImageDimensions(for url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return "\(width) × \(height) px"
    }

    nonisolated static func readTextPreviewSnippet(for item: FileItem, maxLines: Int = 25) -> String? {
        guard !item.isDirectory else { return nil }
        let size = item.size ?? 0
        guard size > 0, size <= 524_288 else { return nil }
        let ext = item.url.pathExtension.lowercased()
        let textExts: Set<String> = [
            "txt", "md", "markdown", "json", "yaml", "yml", "toml", "xml", "csv",
            "log", "ini", "conf", "cfg", "sh", "zsh", "py", "rb", "js", "ts",
            "swift", "c", "cpp", "h", "hpp", "rs", "go", "java", "kt", "html", "css", "sql"
        ]
        guard textExts.contains(ext) || SearchTypeFilter.code.matches(item) else { return nil }
        guard let content = try? String(contentsOf: item.url, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).prefix(maxLines)
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
