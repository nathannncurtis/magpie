import SwiftUI
import _WebKit_SwiftUI

// MARK: - Working scene

/// Where the Skim working scene puts its mark, shared with the failed scene so the
/// still mark stands where the drawing one left off. The place is a share of the
/// screen's height, not a fixed offset, so it holds on any device: on the board's
/// 844 pt phone, 0.344 of the height is the board's 290 pt.
enum SkimScene {

    /// The mark's side.
    static let markSize: CGFloat = 96

    /// The mark's top edge, as a share of the screen's height.
    static let markTopShare: CGFloat = 0.344

    /// The mark's top edge on a screen of the given height.
    static func markTop(in height: CGFloat) -> CGFloat {
        markTopShare * height
    }
}

// MARK: - Query bar

/// The Skim page's floating query bar (03 · Skim): glass, the search icon, the
/// query, and the mark with a "Skim" tag. Tapping it edits the query.
struct SkimQueryBar: View {

    let query: String
    let onEdit: () -> Void

    /// The gap between the status bar's bottom edge and the bar's top. The bar sits
    /// inside the safe area, so it rides just under the status bar on any device —
    /// 58 pt from the top on the board's 54 pt status bar.
    static let topGap: CGFloat = 4

    private enum Layout {
        static let height = Metrics.Bar.skimQueryHeight
        static let inset = Metrics.Spacing.insetFloating
        static let gap: CGFloat = 9
        static let sidePadding: CGFloat = 14
        static let iconSize: CGFloat = 15
        static let markSize: CGFloat = 12
        static let tagGap: CGFloat = 5
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: Layout.iconSize, weight: .medium))
                Text(query)
                    .font(Typography.row)
                    .foregroundStyle(Palette.skimQueryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                HStack(spacing: Layout.tagGap) {
                    Mark(size: Layout.markSize, style: .strokeOnly)
                    Text("Skim")
                        .font(Typography.small)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, Layout.sidePadding)
            .frame(height: Layout.height)
            .frame(maxWidth: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textPrimary)
        .accessibilityIdentifier("skim.queryBar")
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Control bar

/// The Skim page's floating control bar (03 · Skim): "Dig deeper" with the mark,
/// a divider, and the share button. "Dig deeper" hides once ten sources are in.
struct SkimControlBar: View {

    let canDigDeeper: Bool
    let onDigDeeper: () -> Void
    let shareURL: URL?

    private enum Layout {
        static let height = Metrics.Bar.skimControlHeight
        static let markSize: CGFloat = 18
        static let digGap: CGFloat = 9
        static let leadingPadding: CGFloat = 18
        static let trailingPadding: CGFloat = 6
    }

    var body: some View {
        HStack(spacing: 0) {
            if canDigDeeper {
                Button(action: onDigDeeper) {
                    HStack(spacing: Layout.digGap) {
                        Mark(size: Layout.markSize, style: .strokeOnly)
                        Text("Dig deeper · up to 10")
                            .font(Typography.buttonBar)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("skim.digDeeper")
                Rectangle()
                    .fill(Palette.skimControlDivider)
                    .frame(width: 1, height: 24)
            }
            share
        }
        .padding(.leading, canDigDeeper ? Layout.leadingPadding : Layout.trailingPadding)
        .padding(.trailing, Layout.trailingPadding)
        .frame(height: Layout.height)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("skim.controlBar")
    }

    @ViewBuilder
    private var share: some View {
        if let shareURL {
            ShareLink(
                item: shareURL,
                preview: SharePreview(shareURL.deletingPathExtension().lastPathComponent)
            ) {
                CircleButtonSymbol(systemName: "square.and.arrow.up")
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("skim.share")
        } else {
            CircleButton(systemName: "square.and.arrow.up") {}
                .foregroundStyle(Palette.textPrimary.opacity(0.35))
                .frame(width: 46, height: 46)
                .disabled(true)
        }
    }
}

// MARK: - Photo header

/// The photos at the top of a Skim page (03 · Skim), by how many the sources
/// gave: a mosaic of three or more, a single hero, or none — where the mist
/// fades into the page instead.
struct PhotoHeader: View {

    let photos: [URL]
    /// How many photos have arrived; they settle in one by one.
    var revealed = 0

    private enum Layout {
        static let height: CGFloat = 300
        static let gap: CGFloat = 3
        /// The large tile's share of the mosaic's width.
        static let largeShare: CGFloat = 1.55 / 2.55
        /// Where the block's photos start fading into the paper the title sits on.
        static let fadeFrom: Double = 0.87
        /// Where the fade is fully paper — above the block's edge, so no tile
        /// edge shows through the last points of the blend.
        static let fadeEnd: Double = 0.98
    }

    var body: some View {
        GeometryReader { geo in
            if photos.count >= 3 {
                mosaic(size: geo.size)
            } else if let hero = photos.first {
                SkimPhoto(url: hero, revealed: revealed > 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .frame(height: Layout.height)
        .overlay(Self.paperFade)
        .accessibilityHidden(true)
    }

    /// Three or more photos: one large tile and two stacked, one flush block —
    /// shared top and bottom edges, the board's gap between tiles.
    private func mosaic(size: CGSize) -> some View {
        let columns = size.width - Layout.gap
        let large = columns * Layout.largeShare
        let small = columns - large
        let stacked = (size.height - Layout.gap) / 2
        return HStack(alignment: .top, spacing: Layout.gap) {
            SkimPhoto(url: photos[0], revealed: revealed > 0)
                .frame(width: large, height: size.height)
                .clipped()
            VStack(spacing: Layout.gap) {
                SkimPhoto(url: photos[1], revealed: revealed > 1)
                    .frame(width: small, height: stacked)
                    .clipped()
                SkimPhoto(url: photos[2], revealed: revealed > 2)
                    .frame(width: small, height: stacked)
                    .clipped()
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The block's bottom fading into the page's paper, so the title below reads
    /// on paper, never across a tile edge. Fully paper above the edge: the fill
    /// photos are clipped to their frames, and the fade holds opaque paper
    /// through its last stretch.
    private static var paperFade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.skimBackground.opacity(0), location: Layout.fadeFrom),
                .init(color: Palette.skimBackground, location: Layout.fadeEnd),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

/// One photo, cropped to fill, settling from 1.04 scale as it arrives.
private struct SkimPhoto: View {

    let url: URL
    let revealed: Bool

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Palette.fill)
            }
        }
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 1.04)
    }
}

// MARK: - Header

/// The Skim page's title block (03 · Skim): the title, then the sources'
/// favicons and the "From N pages" line. On the no-photo tier the title sits on
/// the mist at 40 pt with a kicker above it.
struct SkimHeader: View {

    let title: String
    let hosts: [String]
    let fromCount: Int
    /// The no-photo tier: bigger, on the mist.
    var onMist = false

    private enum Layout {
        static let titleGap: CGFloat = 10
        static let sourceGap: CGFloat = 8
        static let kickerGap: CGFloat = 10
        static let padding = EdgeInsets(top: 18, leading: 22, bottom: 4, trailing: 22)
        static let mistPadding = EdgeInsets(top: 18, leading: 22, bottom: 4, trailing: 22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if onMist {
                Text("Skim · \(fromCount) pages")
                    .font(Typography.label)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.labelOnMist)
                    .padding(.bottom, Layout.kickerGap)
            }
            Text(title)
                .font(onMist ? Typography.skimTitleNoPhotos : Typography.skimTitle)
                .foregroundStyle(Palette.textPrimary)
                .kerning(Typography.skimTitleTracking)
                .padding(.bottom, Layout.titleGap)
            HStack(spacing: Layout.sourceGap) {
                FaviconStack(hosts: hosts, size: 20, ring: onMist ? nil : Palette.skimBackground)
                Text(SkimPage.fromLine(count: fromCount))
                    .font(Typography.small)
                    .fontWeight(.medium)
                    .foregroundStyle(onMist ? Palette.skimStatus : Palette.textSecondary)
            }
        }
        .padding(onMist ? Layout.mistPadding : Layout.padding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section

/// One point of a Skim page (03 · Skim): an emoji tile, then the claim as one
/// run of text — term, dash, claim — with its citations inline at its end,
/// each a circled digit on the sheen that taps to its source.
struct SkimSectionRow: View {

    let section: SkimSection
    let onCitation: (Int) -> Void

    private enum Layout {
        static let tile: CGFloat = 30
        static let radius: CGFloat = 9
        static let emojiSize: CGFloat = 16
        static let gap: CGFloat = 10
        /// The citation dot that sits inline at the claim's end.
        static let dotSize: CGFloat = 17
        static let dotLift: CGFloat = 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: Layout.gap) {
            RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                .fill(Palette.emojiTile)
                .frame(width: Layout.tile, height: Layout.tile)
                .overlay(
                    Text(section.emoji)
                        .font(.system(size: Layout.emojiSize)))
            claim
                .lineSpacing(Typography.bodyLineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard let citation = Self.citation(from: url) else { return .systemAction }
                onCitation(citation)
                return .handled
            })
    }

    /// The claim with its citations inline: per citation, one thin space then
    /// a circled digit in the sheen's solid mid tone — itself the link that
    /// taps to its source. These stay inside the text: they are links a finger
    /// follows while reading, not buttons it aims at, so they carry no 44 pt
    /// target (the source cards' dots do).
    private var claim: Text {
        var text = AttributedString()
        var term = AttributedString(section.term)
        term.font = Typography.body.weight(.semibold)
        text += term
        var rest = AttributedString(" — \(section.claim)")
        rest.font = Typography.body
        text += rest
        for citation in section.citations {
            var space = AttributedString(Self.thinSpace)
            space.font = .system(size: Layout.dotSize)
            text += space
            var dot = AttributedString(Self.dotGlyph(for: citation))
            dot.font = .system(size: Layout.dotSize)
            dot.foregroundColor = Palette.sheenMid
            dot.baselineOffset = Layout.dotLift
            dot.link = URL(string: "magpie-cite://\(citation)")
            text += dot
        }
        return Text(text)
    }

    /// The circled-digit characters citations 1-10 show inline.
    private static let dotGlyphs = [
        "\u{2776}", "\u{2777}", "\u{2778}", "\u{2779}", "\u{277A}",
        "\u{277B}", "\u{277C}", "\u{277D}", "\u{277E}", "\u{277F}",
    ]

    private static func dotGlyph(for citation: Int) -> String {
        (1...10).contains(citation) ? dotGlyphs[citation - 1] : "(\(citation))"
    }

    private static let thinSpace = "\u{2009}"

    /// The citation a link run points at, when it is one of ours.
    private static func citation(from url: URL) -> Int? {
        guard url.scheme == "magpie-cite", let host = url.host(), let number = Int(host) else {
            return nil
        }
        return number
    }
}

/// The source's number on the sheen (03 · CitationDot): the 17 pt circle itself,
/// for the places it sits inside a line and is not tapped on its own.
struct CitationBadge: View {

    let number: Int

    private enum Layout {
        static let size: CGFloat = 17
        static let numberSize: CGFloat = 10
    }

    var body: some View {
        Text("\(number)")
            .font(.system(size: Layout.numberSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Layout.size, height: Layout.size)
            .background(Circle().fill(Palette.sheen))
            .contentShape(Circle())
            .accessibilityLabel(Text("Source \(number)"))
    }
}

/// A citation dot (03 · Skim). Tapping it scrolls to the source's card; holding
/// it previews the page. The circle stays 17 pt; the target around it is the
/// 44 pt minimum, invisible.
struct CitationDot: View {

    let number: Int
    let previewURL: URL?
    let onTap: () -> Void

    private enum Layout {
        /// The touch target the dot carries.
        static let hitSide: CGFloat = 44
    }

    var body: some View {
        Button(action: onTap) {
            CitationBadge(number: number)
                .frame(minWidth: Layout.hitSide, minHeight: Layout.hitSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu(
            menuItems: {},
            preview: {
                if let previewURL {
                    WebView(url: previewURL)
                        .ignoresSafeArea()
                }
            }
        )
        .accessibilityLabel(Text("Source \(number)"))
    }
}

// MARK: - Source card

/// One source under a Skim page's "Sources" heading (03 · Skim): a thumbnail,
/// the site line with its number, and the page's title.
struct SourceCard: View {

    let number: Int
    let source: SkimSourceRef
    let onOpen: (URL) -> Void

    private enum Layout {
        static let width: CGFloat = 200
        static let radius: CGFloat = 18
        static let thumbnailHeight: CGFloat = 84
        static let thumbnailRadius: CGFloat = 12
        static let favicon: CGFloat = 14
        static let gap: CGFloat = 6
        static let padding: CGFloat = 8
        static let bottomPadding: CGFloat = 12
    }

    var body: some View {
        Button {
            onOpen(source.url)
        } label: {
            VStack(alignment: .leading, spacing: Layout.gap) {
                thumbnail
                HStack(spacing: Layout.gap) {
                    ListFavicon(host: source.host, size: Layout.favicon)
                    CitationBadge(number: number)
                    Text(source.host)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.skimSourceSite)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(source.title)
                    .font(Typography.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.skimSourceTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, Layout.padding)
            .padding(.top, Layout.padding)
            .padding(.bottom, Layout.bottomPadding)
            .frame(width: Layout.width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                    .stroke(Palette.skimSourceRing, lineWidth: 1)
            )
            .shadow(color: Palette.skimSourceShadow, radius: 10, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("skim.source.\(number)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageURL = source.imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Palette.fill)
                }
            }
            .frame(height: Layout.thumbnailHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Layout.thumbnailRadius, style: .continuous))
        } else {
            Rectangle()
                .fill(Palette.fill)
                .frame(height: Layout.thumbnailHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Layout.thumbnailRadius, style: .continuous))
        }
    }
}
