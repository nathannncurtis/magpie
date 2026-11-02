import SwiftUI

/// "Closed · Undo": the small glass capsule that follows a card flung closed. The whole
/// capsule is the button.
struct UndoCapsule: View {
    var action: () -> Void

    /// The capsule's height at the default size, growing with Dynamic Type the way its
    /// label does.
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight = CapsuleMetrics.height
    private var height: CGFloat { max(CapsuleMetrics.height, scaledHeight) }

    private enum CapsuleMetrics {
        static let height: CGFloat = 46
        static let horizontalPadding: CGFloat = 20
        static let gap: CGFloat = 8
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: CapsuleMetrics.gap) {
                Text(TabsCopy.closed)
                    .font(Typography.row)
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: "\u{00B7}")
                    .font(Typography.row)
                    .foregroundStyle(Palette.textTertiary)
                Text(TabsCopy.undo)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, CapsuleMetrics.horizontalPadding)
            .frame(minHeight: height)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TabsCopy.undoClose))
        .accessibilityIdentifier("tabs.undo")
    }
}

#Preview {
    UndoCapsule(action: {})
        .padding(20)
}
