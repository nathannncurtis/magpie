import SwiftUI
import _WebKit_SwiftUI

// MARK: - Query bar

/// The Skim page's floating query bar (03 · Skim): glass, the search icon, the
/// query, and the mark with a "Skim" tag. Tapping it edits the query.
struct SkimQueryBar: View {

    let query: String
    let onEdit: () -> Void

    private enum Layout {
        static let height = Metrics.Bar.skimQueryHeight
        static let inset = Metrics.Spacing.insetFloating
        /// Just under the status bar.
        static let fromTop: CGFloat = 58
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
        .glassEffect(.regular, in: .capsule)
        .accessibilityIdentifier("skim.queryBar")
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
    }

    var body: some View {
        GeometryReader { geo in
            if photos.count >= 3 {
                mosaic(width: geo.size.width)
            } else if let hero = photos.first {
                SkimPhoto(url: hero, revealed: revealed > 0)
            }
        }
        .frame(height: Layout.height)
        .accessibilityHidden(true)
    }

    /// Three or more photos: one large tile beside two stacked.
    private func mosaic(width: CGFloat) -> some View {
        let large = (width - Layout.gap) * Layout.largeShare
        return HStack(spacing: Layout.gap) {
            SkimPhoto(url: photos[0], revealed: revealed > 0)
                .frame(width: large)
            VStack(spacing: Layout.gap) {
                SkimPhoto(url: photos[1], revealed: revealed > 1)
                SkimPhoto(url: photos[2], revealed: revealed > 2)
            }
        }
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
        .clipped()
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

/// One point of a Skim page (03 · Skim): an emoji tile, then the term, a dash,
/// the claim, and the citation dots that stand behind it.
struct SkimSectionRow: View {

    let section: SkimSection
    let sources: [SkimSourceRef]
    let onCitation: (Int) -> Void

    private enum Layout {
        static let tile: CGFloat = 30
        static let radius: CGFloat = 9
        static let emojiSize: CGFloat = 16
        static let gap: CGFloat = 10
        static let dotGap: CGFloat = 3
        static let dotRowGap: CGFloat = 6
    }

    var body: some View {
        HStack(alignment: .top, spacing: Layout.gap) {
            RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                .fill(Palette.emojiTile)
                .frame(width: Layout.tile, height: Layout.tile)
                .overlay(
                    Text(section.emoji)
                        .font(.system(size: Layout.emojiSize)))
            VStack(alignment: .leading, spacing: Layout.dotRowGap) {
                Text("\(Text(section.term).fontWeight(.semibold)) — \(section.claim)")
                    .font(Typography.body)
                    .lineSpacing(Typography.bodyLineSpacing)
                HStack(spacing: Layout.dotGap) {
                    ForEach(section.citations, id: \.self) { citation in
                        CitationDot(
                            number: citation,
                            previewURL: sources.indices.contains(citation - 1)
                                ? sources[citation - 1].url : nil
                        ) {
                            onCitation(citation)
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }
}

/// A citation dot (03 · Skim): the source's number on the sheen. Tapping it
/// scrolls to the source's card; holding it previews the page.
struct CitationDot: View {

    let number: Int
    let previewURL: URL?
    let onTap: () -> Void

    private enum Layout {
        static let size: CGFloat = 17
        static let numberSize: CGFloat = 10
    }

    var body: some View {
        Button(action: onTap) {
            Text("\(number)")
                .font(.system(size: Layout.numberSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.size, height: Layout.size)
                .background(Circle().fill(Palette.sheen))
                .contentShape(Circle())
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
                    CitationDot(number: number, previewURL: source.url) {}
                        .allowsHitTesting(false)
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
