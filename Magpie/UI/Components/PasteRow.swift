import SwiftUI

/// The first row when the pasteboard holds a link: one tap opens it. It does not say where
/// the link goes: reading the pasteboard raises the system's paste prompt, and the row
/// only asks whether a link is there.
struct PasteRow: View {

    /// Layout numbers, shared with the suggestion rows.
    private enum Layout {
        static let iconSize: CGFloat = 16
        static let gap: CGFloat = 12
        static let horizontalPadding: CGFloat = 12
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(Palette.textTertiary)
                Text(String(localized: "Go to copied link"))
                    .font(Typography.row)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Layout.gap)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .frame(minHeight: Metrics.Spacing.rowSuggestion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.paste")
    }
}

#Preview {
    PasteRow(action: {})
        .padding()
}
