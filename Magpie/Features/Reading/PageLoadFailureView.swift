import SwiftUI

/// 04 · 15, the page can't load: Magpie's own page on `skimBackground`, centred — one
/// plain line on what happened, one way forward. The bar stays, at its default tint.
struct PageLoadFailureView: View {

    let failure: PageLoadFailure
    let onRetry: () -> Void

    /// The line glyph, a plain SF Symbol standing in for the drawn one.
    private static let iconSize: CGFloat = 40
    /// The title, 18 pt semibold on the board.
    private static let titleSize: CGFloat = 18
    /// The block's rhythm: a 6 pt gap with a little more above the title and the button.
    private static let gap: CGFloat = 6
    private static let titleGap: CGFloat = 4
    private static let buttonGap: CGFloat = 8
    private static let sideInset: CGFloat = 44
    /// The block sits this far above centre.
    private static let lift: CGFloat = 80
    /// The "Try again" capsule.
    private static let buttonPaddingH: CGFloat = 22
    private static let buttonPaddingV: CGFloat = 11

    var body: some View {
        VStack(spacing: Self.gap) {
            Image(systemName: "globe")
                .font(.system(size: Self.iconSize, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            Text(failure.title)
                .font(.system(size: Self.titleSize, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, Self.titleGap)
                .multilineTextAlignment(.center)
            Text(failure.line)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("Try again")
                    .font(Typography.buttonPill)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, Self.buttonPaddingH)
                    .padding(.vertical, Self.buttonPaddingV)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .padding(.top, Self.buttonGap)
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.bottom, Self.lift)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.skimBackground)
    }
}

#Preview {
    PageLoadFailureView(
        failure: PageLoadFailure(host: "quietweb.org", isOffline: true), onRetry: {})
}
