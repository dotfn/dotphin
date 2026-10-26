import SwiftUI

struct StatusBarView: View {
    let itemCount: Int
    let totalCount: Int
    let availableCapacity: Int64?

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var countText: String {
        itemCount == totalCount ? "\(itemCount) ítems" : "\(itemCount) de \(totalCount) ítems"
    }

    private var capacityText: String {
        availableCapacity.map { "\(Self.sizeFormatter.string(fromByteCount: $0)) libres" } ?? "—"
    }

    var body: some View {
        HStack {
            Text(countText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(capacityText)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
