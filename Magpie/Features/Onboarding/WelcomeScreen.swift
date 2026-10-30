import SwiftUI

/// Welcome, the first screen of the first launch (04 · 07a): the mark on the mist, the
/// name and the line under it, and one button. The mark's draw-on comes later; it stands
/// still for now.
struct WelcomeScreen: View {
    var onGetStarted: () -> Void

    private enum WelcomeMetrics {
        /// Where the block's top sits below the safe-area top, as a share of the
        /// height on hand: about 176 pt on a standard phone, holding its place on any
        /// height.
        static let topFraction: CGFloat = 0.23
    }

    var body: some View {
        ZStack {
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

            VStack(spacing: 12) {
                PrimaryCTA(title: "Get started", action: onGetStarted)
                    .accessibilityIdentifier("welcome.start")
                Text("Free and open source. No account. Nothing collected.")
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
    }
}
