import AppKit
import SwiftUI

/// Celda de la vista "Compacta" de Dolphin: ícono y nombre lado a lado
/// (la grilla es `FileCollectionView`).
struct CompactGridCell: View {
    let item: FileItem
    let zoomLevel: Double
    let isSelected: Bool
    let isSelectionModeActive: Bool
    let gitStatus: GitFileStatus?

    @State private var isHovered = false

    private var iconDimension: CGFloat {
        max(18, 22 * zoomLevel)
    }

    var body: some View {
        HStack(spacing: 7) {
            if isSelectionModeActive {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .transition(.scale.combined(with: .opacity))
            }

            Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: iconDimension, height: iconDimension)

            Text(item.name)
                .font(.system(size: max(11.5, 12.5 * min(1.25, zoomLevel)), weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            if let nsColor = item.colorTag.nsColor {
                Circle()
                    .fill(Color(nsColor: nsColor))
                    .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0.35), lineWidth: 0.8))
                    .frame(width: 8, height: 8)
                    .help(String(localized: "Etiqueta: \(item.colorTag.title)", bundle: #bundle))
            }

            GitStatusBadge(status: gitStatus)

            Spacer(minLength: 0)
        }
        .opacity(item.isHiddenItem ? 0.58 : 1.0)
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy(duration: 0.15), value: isSelected)
        .onHover { isHovered = $0 }
        .help(isHovered ? FileMetadataFormatter().hoverTooltip(for: item) : item.name)
    }
}

struct DotphinGroupSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
            Text(String(localized: "\(count)", bundle: #bundle))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            VStack {
                Divider()
                    .opacity(0.6)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.bar)
    }
}
