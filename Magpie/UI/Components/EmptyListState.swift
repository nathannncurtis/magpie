import SwiftUI

/// An empty list's quiet block on the mist: a line icon, a title, one line of way
/// forward. No search pill sits under it — there is nothing to search.
struct EmptyListState: View {
    let icon: String
    let title: String
    let message: String

    private enum EmptyMetrics {
        /// Where the block's top sits, as a share of the height on hand: about 300 pt
        /// on a standard phone, holding its place on any height.
        static let topFraction: CGFloat = 0.35
        static let icon: CGFloat = 34
        static let titleGap: CGFloat = 8
        static let messageGap: CGFloat = 6
        static let sideInset: CGFloat = 40
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: EmptyMetrics.messageGap) {
                Image(systemName: icon)
                    .font(.system(size: EmptyMetrics.icon, weight: .medium))
                    .foregroundStyle(Palette.labelOnMist)
                    .padding(.bottom, EmptyMetrics.titleGap - EmptyMetrics.messageGap)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, EmptyMetrics.sideInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.top, geo.size.height * EmptyMetrics.topFraction)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Archive") {
    ZStack {
        MistBackground().ignoresSafeArea()
        EmptyListState(
            icon: "archivebox",
            title: "Nothing archived yet",
            message: "Tabs you leave alone for a day land here, and stay for 30 days.")
    }
}
