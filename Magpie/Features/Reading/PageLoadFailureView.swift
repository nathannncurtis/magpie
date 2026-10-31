import SwiftUI

/// 04 · 15, the page can't load: Magpie's own page on `skimBackground`, centred — one
/// plain line on what happened, one way forward. The bar stays, at its default tint.
struct PageLoadFailureView: View {

    let failure: PageLoadFailure
    let onRetry: () -> Void

    /// The title, 18 pt semibold on the board.
    private static let titleSize: CGFloat = 18
    /// The block's rhythm: a 6 pt gap with a little more above the title and the button.
    private static let gap: CGFloat = 6
    private static let titleGap: CGFloat = 4
    private static let buttonGap: CGFloat = 8
    private static let sideInset: CGFloat = 44
    /// The block sits this far above centre.
    private static let lift: CGFloat = 80
    /// The "Try again" capsule, its height a full-size tap target.
    private static let buttonPaddingH: CGFloat = 22
    private static let buttonHeight: CGFloat = 44

    /// The title's size, scaling with Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var titleSize = Self.titleSize

    var body: some View {
        VStack(spacing: Self.gap) {
            GlobeWithSlash()
                .accessibilityHidden(true)
            Text(failure.title)
                .font(.system(size: titleSize, weight: .semibold))
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
                    .frame(minHeight: Self.buttonHeight)
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

/// The 04 · 15 line icon: a globe with a slash through it. SF Symbols carries no such
/// glyph, so the slash is composed over the plain globe, leaning the way the system's
/// own slashed glyphs lean.
private struct GlobeWithSlash: View {

    /// The globe.
    private static let globeSize: CGFloat = 40
    /// The slash, long enough to cross the globe's stroke corner to corner.
    private static let slashLength: CGFloat = 58
    /// The slash's thickness, at the medium-weight symbol's stroke.
    private static let slashWidth: CGFloat = 3.5

    var body: some View {
        Image(systemName: "globe")
            .font(.system(size: Self.globeSize, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
            .overlay {
                Capsule()
                    .fill(Palette.textTertiary)
                    .frame(width: Self.slashWidth, height: Self.slashLength)
                    .rotationEffect(.degrees(45))
            }
            // The title says what happened; the icon is a picture of it.
            .accessibilityHidden(true)
    }
}

#Preview {
    PageLoadFailureView(
        failure: PageLoadFailure(host: "quietweb.org", isOffline: true), onRetry: {})
}
