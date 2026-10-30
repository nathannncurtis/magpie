import SwiftUI

/// Welcome, the first screen of the first launch (04 · 07a): the mark on the mist, the
/// name and the line under it, and one button. The mark's draw-on comes later; it stands
/// still for now.
struct WelcomeScreen: View {
    var onGetStarted: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // The board puts this block 230 from the top, 176 past its status bar.
                Color.clear.frame(height: 176)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
