import SwiftUI

/// The glass chip that opens the archive, carrying the archived count.
struct ArchivedChip: View {
    let count: Int
    var action: () -> Void

    /// The chip's height at the default size, growing with Dynamic Type the way its
    /// label does.
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight = ChipMetrics.height
    /// Grows with the type size, never below the board's height at the smaller sizes.
    private var height: CGFloat { max(ChipMetrics.height, scaledHeight) }

    private enum ChipMetrics {
        static let height: CGFloat = 46
        static let horizontalPadding: CGFloat = 16
        static let icon: CGFloat = 18
        static let iconGap: CGFloat = 8
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChipMetrics.iconGap) {
                Image(systemName: "archivebox")
                    .font(.system(size: ChipMetrics.icon, weight: .medium))
                    .imageScale(.medium)
                Text(TabsCopy.archived(count))
                    .font(Typography.rowTitle)
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, ChipMetrics.horizontalPadding)
            .frame(minHeight: height)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ArchivedChip(count: 12, action: {})
        .padding(20)
}
