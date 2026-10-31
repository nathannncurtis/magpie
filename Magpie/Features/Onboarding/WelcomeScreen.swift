import SwiftUI

/// Welcome, the first screen of the first launch (04 · 07a): the mark on the mist, the
/// name and the line under it, and one button. The mark's draw-on comes later; it stands
/// still for now.
struct WelcomeScreen: View {
    var onGetStarted: () -> Void

    /// The bottom inset, read while the layout still respects it: the button's layer
    /// runs on under the home indicator, where the inset can no longer be read.
    @State private var bottomInset: CGFloat = 0

    private enum WelcomeMetrics {
        /// Where the block's top sits below the safe-area top, as a share of the
        /// height on hand: about 176 pt on a standard phone, holding its place on any
        /// height.
        static let topFraction: CGFloat = 0.23
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.size.height * WelcomeMetrics.topFraction)
                    Mark(size: 120, style: .sheen)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityHidden(true)
                    Text("magpie")
                        .font(Typography.wordmark)
                        .tracking(Typography.wordmarkTracking)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, 16)
                    Text("The browser you shape.")
                        .font(Typography.row)
                        .foregroundStyle(Palette.textOnMistSecondary)
                        .padding(.top, 2)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }

            // The button measures from the physical bottom edge (01 · Bottom controls),
            // the way the reading bar does: its layer runs on under the home indicator
            // and the padding, read off the inset first, seats it above that edge.
            VStack(spacing: 12) {
                PrimaryCTA(title: String(localized: "Get started"), action: onGetStarted)
                    .accessibilityIdentifier("welcome.start")
                Text("Free and open source. No account. Nothing collected.")
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
            }
            .padding(.horizontal, 16)
            .readableWidth()
            .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
            .ignoresSafeArea(edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
    }
}
