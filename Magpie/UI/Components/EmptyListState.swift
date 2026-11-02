import SwiftUI

/// An empty list's quiet block on the mist: a line icon, a title, one line of way
/// forward. No search pill sits under it — there is nothing to search. It goes in a
/// layer over the whole screen, not under the header, so its share of the height is
/// the screen's, not the leftover.
struct EmptyListState: View {
    let icon: String
    let title: String
    let message: String

    private enum EmptyMetrics {
        /// Where the block's top sits, as a share of the height on hand — the screen's
        /// safe height, when the layer is held to it: about 270 pt on a standard phone,
        /// holding its place on any height.
        static let topFraction: CGFloat = 0.35
        /// The least the top sits below the safe top: under the list headers (about
        /// 96 pt) with room to spare, for when the keys leave only a short height and
        /// the share alone would tuck the block against the title.
        static let minTop: CGFloat = 124
        static let titleGap: CGFloat = 8
        static let messageGap: CGFloat = 6
        static let sideInset: CGFloat = 40
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: EmptyMetrics.messageGap) {
                Image(systemName: icon)
                    .font(.largeTitle.weight(.regular))
                    .foregroundStyle(Palette.labelOnMist)
                    .padding(.bottom, EmptyMetrics.titleGap - EmptyMetrics.messageGap)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typography.emptyTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, EmptyMetrics.sideInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.top, max(geo.size.height * EmptyMetrics.topFraction, EmptyMetrics.minTop))
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
