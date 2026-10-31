import SwiftUI

/// The featured mod: a solid card with a 150 pt hand-drawn preview of what the mod does,
/// then the mod itself (03 · Featured mod card).
struct FeaturedModCard: View {

    /// Layout numbers from the board.
    private enum Layout {
        /// The mark the card carries while its install runs (05 · 06).
        static let mark: CGFloat = 24
    }

    let mod: DirectoryMod
    var installed: Bool
    /// The mod's file is being fetched and checked, so Get gives way to the mark.
    var fetching = false
    var onGet: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            preview
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                ModIcon(spec: mod.icon)
                    .accessibilityHidden(true)
                // The card's text reads as one line; what trails it stays its own
                // element, so Get stays reachable.
                VStack(alignment: .leading, spacing: 1) {
                    Text(mod.name)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(mod.descriptionText)
                        .font(Typography.small)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if installed {
                    InstalledCheck()
                } else if fetching {
                    MarkSpinner(size: Layout.mark)
                        .accessibilityElement()
                        .accessibilityLabel(Text(ModsCopy.installing))
                } else {
                    GetButton(action: onGet)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .shadow(color: Palette.tabCardShadow, radius: 15, y: 14)
        .overlay(cardHairline)
        .accessibilityIdentifier("mods.featured")
    }

    @ViewBuilder
    private var preview: some View {
        switch mod.preview {
        case .googleAnswerBox:
            GoogleAnswerBoxPreview()
        case nil:
            FeaturedPreviewSky {
                Image(systemName: mod.icon.glyph)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Dark's hairline ring; light carries its shadow alone.
    private var cardHairline: some View {
        Group {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            }
        }
    }
}

/// The sky every featured preview draws on: 150 pt of the 160-degree gradient.
private struct FeaturedPreviewSky<Content: View>: View {

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Palette.featuredPreviewTop, Palette.featuredPreviewBottom],
                    startPoint: UnitPoint(x: 0.58, y: 0),
                    endPoint: UnitPoint(x: 0.42, y: 1)
                )
            )
            .clipped()
    }
}

/// The Google Answer Box mod's own picture: a mini search result with the direct answer
/// ringed, drawn in SwiftUI, in its own light and dark palettes (board 06). The colours
/// are the picture's, not the app's; the words are the illustration's, fixed.
private struct GoogleAnswerBoxPreview: View {

    @Environment(\.colorScheme) private var colorScheme

    private enum Drawing {
        static let query = "how long to rest steak"
        static let answerLabel = "ANSWER"
        static let answerLead = "5 to 10 minutes"
        static let answerRest = "for steaks; about 15 for a roast."
    }

    private var palette: PreviewPalette {
        colorScheme == .dark ? PreviewPalette.dark : PreviewPalette.light
    }

    var body: some View {
        FeaturedPreviewSky {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.googleBlue)
                            .frame(width: 22, height: 22)
                            .background(palette.tile, in: Circle())
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.tile)
                            Text(Drawing.query)
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.queryText)
                                .padding(.horizontal, 11)
                                .lineLimit(1)
                        }
                        .frame(height: 26)
                    }
                    answerCard
                    skeleton(width: geo.size.width * 0.88)
                    skeleton(width: geo.size.width * 0.60)
                    skeleton(width: geo.size.width * 0.88)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Drawing.answerLabel)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.85)
                .foregroundStyle(palette.ring)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Drawing.answerLead)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.answerStrong)
                Text(Drawing.answerRest)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.answerText)
                    .lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
        .background(palette.answerTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.ring, lineWidth: 1.5)
        )
        .shadow(color: palette.ringShadow, radius: 7, y: 3)
    }

    private func skeleton(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(palette.skeleton)
            .frame(height: 7)
            .frame(width: width, alignment: .leading)
    }

    private struct PreviewPalette {
        let googleBlue: Color
        let tile: Color
        let answerTile: Color
        let queryText: Color
        let answerText: Color
        let answerStrong: Color
        let ring: Color
        let ringShadow: Color
        let skeleton: Color

        static let light = PreviewPalette(
            googleBlue: Color(hex: 0x4285F4),
            tile: .white,
            answerTile: .white,
            queryText: Color(hex: 0x3C4043),
            answerText: Color(hex: 0x3C4043),
            answerStrong: Color(hex: 0x1B1C21),
            ring: Color(hex: 0x1A56D6),
            ringShadow: Color(hex: 0x1A56D6, opacity: 0.6),
            skeleton: Color(hex: 0x3C4043, opacity: 0.14))

        static let dark = PreviewPalette(
            googleBlue: Color(hex: 0x8AB4F8),
            tile: Color(hex: 0x2A303C),
            answerTile: Color(hex: 0x1E2533),
            queryText: Color(hex: 0xD6D9E0),
            answerText: Color(hex: 0xC2C7D0),
            answerStrong: .white,
            ring: Color(hex: 0x8AB4F8),
            ringShadow: Color(hex: 0x8AB4F8, opacity: 0.5),
            skeleton: Color.white.opacity(0.12))
    }
}
