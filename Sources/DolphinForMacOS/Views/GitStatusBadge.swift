import SwiftUI

struct GitStatusBadge: View {
    let status: GitFileStatus?

    var body: some View {
        if let status {
            Circle()
                .fill(color(for: status))
                .frame(width: 6, height: 6)
                .accessibilityLabel(status.accessibilityDescription)
        }
    }

    private func color(for status: GitFileStatus) -> Color {
        switch status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .untracked: return .gray
        case .renamed: return .blue
        }
    }
}
