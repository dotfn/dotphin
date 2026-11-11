import AppKit
import SwiftUI

/// Celda de la vista "Iconos" (la grilla es `FileCollectionView`).
struct IconGridCell: View {
    let item: FileItem
    let zoomLevel: Double
    let showPreviews: Bool
    let isSelected: Bool
    let isSelectionModeActive: Bool
    let gitStatus: GitFileStatus?

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private var iconDimension: CGFloat {
        58 * zoomLevel
    }

    var body: some View {
        VStack(spacing: 4) {
            // Native macOS Finder icon plate: rounded box around the icon only
            ZStack(alignment: .topTrailing) {
                Group {
                    if showPreviews, let resolvedThumbnail = thumbnail ?? ThumbnailLoader.cachedThumbnail(for: item.url) {
                        Image(nsImage: resolvedThumbnail)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.6)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Image(nsImage: ThumbnailLoader.icon(for: item))
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                    }
                }
                .frame(width: iconDimension, height: iconDimension)
                .scaleEffect(isHovered && !isSelected ? 1.035 : 1.0)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.primary.opacity(0.12)
                                : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                        )
                )

                HStack(spacing: 3) {
                    if isSelectionModeActive {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .background(Circle().fill(.regularMaterial))
                            .transition(.scale.combined(with: .opacity))
                    }
                    GitStatusBadge(status: gitStatus)
                }
                .padding(3)
            }

            // Native macOS Finder label pill: blue accent pill tightly wrapping the filename
            HStack(spacing: 4) {
                if let nsColor = item.colorTag.nsColor {
                    Circle()
                        .fill(Color(nsColor: nsColor))
                        .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0.35), lineWidth: 0.8))
                        .frame(width: 7.5, height: 7.5)
                }
                Text(item.name)
                    .font(.system(size: max(11, min(13, 11.5 * zoomLevel)), weight: isSelected ? .medium : .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 0)
        }
        .opacity(item.isHiddenItem ? 0.58 : 1.0)
        .frame(width: 96 * zoomLevel)
        .frame(minHeight: 92 * zoomLevel, alignment: .top)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.16), value: isSelected)
        .onHover { isHovered = $0 }
        .help(isHovered ? FileMetadataFormatter().hoverTooltip(for: item) : item.name)
        .task(id: item.url) {
            guard showPreviews else {
                thumbnail = nil
                return
            }
            if let cached = ThumbnailLoader.cachedThumbnail(for: item.url) {
                thumbnail = cached
                return
            }
            thumbnail = nil
            guard !item.isDirectory else { return }
            let image = await ThumbnailLoader().thumbnail(
                for: item.url,
                size: CGSize(width: 128, height: 128)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnail = image
            }
        }
    }
}
