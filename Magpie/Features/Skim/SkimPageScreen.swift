import SwiftUI

/// 04 · The Skim page: the photos the sources gave, the title over its sources'
/// favicons, the sections with their citation dots, and the sources themselves;
/// the query bar floats above and the control bar below. When it lands, the
/// whole page reveals itself in about 1.4 s (05 · 04): photos settle in, then
/// the title and each section rise, then the bars arrive. Under Reduce Motion
/// it is one crossfade.
struct SkimPageScreen: View {

    let page: SkimPage
    let onEditQuery: () -> Void
    let onDigDeeper: () -> Void
    let onOpenSource: (URL) -> Void

    private enum Layout {
        /// How long the working scene takes to clear before the page reveals.
        static let clearDelay: UInt64 = 350_000_000
        /// How far apart the page's pieces arrive.
        static let itemGap: UInt64 = 70_000_000
        /// How far below the floating query bar the mist tier's content starts: the
        /// board's 112 pt from the top, measured from the bar instead of the edge.
        static let belowQueryBar: CGFloat = 12
        static let mistBottom: CGFloat = 6
        static let sourcesTop: CGFloat = 22
        static let sourcesBottom: CGFloat = 8
        static let cardGap: CGFloat = 10
        static let barClearance: CGFloat = 40
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var shareURL: URL?
    @State private var bottomInset: CGFloat = 0
    /// The query bar's top edge in screen coordinates, so the mist tier's content
    /// can start below the bar wherever the status bar puts it. The first frame
    /// carries the board phone's value; the read corrects it on the first layout.
    @State private var queryBarTop: CGFloat = 58

    var body: some View {
        GlassEffectContainer {
            ZStack(alignment: .top) {
                Palette.skimBackground
                    .ignoresSafeArea()
                scroll
                VStack(spacing: 0) {
                    Spacer()
                    SkimControlBar(
                        canDigDeeper: page.canDigDeeper,
                        onDigDeeper: onDigDeeper,
                        shareURL: shareURL
                    )
                    .padding(.horizontal, Metrics.Spacing.insetFloating)
                    .readableWidth()
                    .padding(
                        .bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset)
                    )
                    .modifier(Arrived(shown: step >= barsStep, drop: -12))
                }
                SkimQueryBar(query: page.query, onEdit: onEditQuery)
                    .padding(.horizontal, Metrics.Spacing.insetFloating)
                    .readableWidth()
                    .padding(.top, SkimQueryBar.topGap)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .global).minY
                    } action: {
                        queryBarTop = $0
                    }
                    .modifier(Arrived(shown: step >= barsStep, drop: -12))
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(edges: .bottom)
        .task(id: page) {
            await reveal()
        }
        .task(id: page) {
            shareURL = Self.shareFile(for: page)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("skim.page")
    }

    // MARK: Content

    private var scroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ForEach(Array(page.sections.enumerated()), id: \.element.id) { index, section in
                        SkimSectionRow(section: section) { citation in
                            withAnimation(Springs.settle.animation) {
                                proxy.scrollTo(Self.sourcesAnchor, anchor: .center)
                                proxy.scrollTo(Self.sourceAnchor(citation), anchor: .center)
                            }
                        }
                        .padding(.horizontal, Metrics.Spacing.insetText)
                        .modifier(Arrived(shown: step >= sectionStep(index)))
                    }
                    sources
                    Color.clear.frame(
                        height: Metrics.Bar.skimControlHeight
                            + Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset)
                            + Layout.barClearance)
                }
                .readableWidth()
                .padding(.bottom, bottomInset)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The page's top: the photos the sources gave, or the mist they didn't.
    @ViewBuilder
    private var header: some View {
        switch page.photoTier {
        case .mosaic, .hero:
            PhotoHeader(photos: page.photoURLs, revealed: min(step, photoSteps))
            SkimHeader(
                title: page.title,
                hosts: page.sources.map(\.host),
                fromCount: page.sources.count
            )
            .modifier(Arrived(shown: step >= headerStep))
        case .none:
            ZStack(alignment: .top) {
                MistBackground(fadesIntoPage: true)
                    .frame(height: Metrics.Mist.fadeHeight)
                VStack(spacing: 0) {
                    Color.clear.frame(height: mistContentTop)
                    SkimHeader(
                        title: page.title,
                        hosts: page.sources.map(\.host),
                        fromCount: page.sources.count,
                        onMist: true
                    )
                    .padding(.bottom, Layout.mistBottom)
                }
            }
            .modifier(Arrived(shown: step >= headerStep))
        }
    }

    /// Where the mist tier's content starts, measured from the physical top the
    /// scroll lays out in: under the query bar and its clearance, wherever the
    /// status bar has pushed the bar to.
    private var mistContentTop: CGFloat {
        queryBarTop + Metrics.Bar.skimQueryHeight + Layout.belowQueryBar
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sources")
                .font(Typography.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.Spacing.insetText)
                .padding(.top, Layout.sourcesTop)
                .padding(.bottom, Layout.sourcesBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(Self.sourcesAnchor)
                .modifier(Arrived(shown: step >= sourcesStep))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.cardGap) {
                    ForEach(Array(page.sources.enumerated()), id: \.element.id) { index, source in
                        SourceCard(number: index + 1, source: source, onOpen: onOpenSource)
                            .id(Self.sourceAnchor(index + 1))
                            .modifier(Arrived(shown: step >= sourcesStep))
                    }
                }
                .padding(.horizontal, Metrics.Spacing.insetText)
            }
        }
    }

    // MARK: The reveal

    private var photoSteps: Int {
        switch page.photoTier {
        case .mosaic: 3
        case .hero: 1
        case .none: 0
        }
    }

    private var headerStep: Int { photoSteps + 1 }
    private func sectionStep(_ index: Int) -> Int { headerStep + 1 + index }
    private var sourcesStep: Int { headerStep + 1 + page.sections.count }
    private var barsStep: Int { sourcesStep + 1 }

    private func reveal() async {
        if reduceMotion {
            step = barsStep
            try? await Task.sleep(for: .milliseconds(200))
            return
        }
        do {
            try await Task.sleep(for: .nanoseconds(Layout.clearDelay))
        } catch {
            return
        }
        while step < barsStep {
            let next = step + 1
            if next <= photoSteps {
                withAnimation(Springs.settle.animation) { step = next }
            } else {
                withAnimation(Springs.chrome.animation) { step = next }
            }
            do {
                try await Task.sleep(for: .nanoseconds(Layout.itemGap))
            } catch {
                return
            }
        }
    }

    // MARK: Share

    /// The page as one self-contained HTML file, ready for the share sheet.
    static func shareFile(for page: SkimPage) -> URL? {
        let name = shareFileName(for: page)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try page.exportHTML().data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func shareFileName(for page: SkimPage) -> String {
        let slug = String(
            page.title.lowercased().map { character in
                character.isLetter || character.isNumber ? character : "-"
            })
        let collapsed = slug.split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let safe = collapsed.isEmpty ? "skim" : String(collapsed.prefix(60))
        return safe + ".html"
    }

    static func sourceAnchor(_ number: Int) -> String {
        "skim.source.\(number)"
    }

    /// The strip the citation dots scroll to: its own anchor for the page's
    /// vertical scroll, beside the card's anchor for the strip's horizontal
    /// one, so a tapped citation lands its card on screen on both axes.
    static let sourcesAnchor = "skim.sources"
}

/// One piece of the page arriving: fading in, rising 8 pt — or dropping in, for
/// the bars.
private struct Arrived: ViewModifier {

    let shown: Bool
    var drop: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : drop)
    }
}

#Preview("Mosaic") {
    SkimPageScreen(
        page: SkimFixture.page(photoCount: 3),
        onEditQuery: {},
        onDigDeeper: {},
        onOpenSource: { _ in })
}
