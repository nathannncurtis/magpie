import SwiftUI
import WebKit

/// 02 · Reading: a full-bleed web view under the status bar with the ReadingBar
/// floating at the bottom. The bar takes the page's tint and slims on scroll; the URL
/// pill opens the search sheet over the page, growing from the bar as one glass shape
/// (05 · The bar into the sheet), and the page is one view with its tab card (05 · The
/// page into its card).
struct ReadingScreen: View {

    let session: ReadingSession?
    let tabID: Tab.ID?
    var tabCount: Int
    var isSearchOpen: Bool
    var engine: SearchEngine
    var suggestions: any SuggestionProviding
    var recents: any RecentSearchStoring
    /// Whether the search sheet over the page shows its Skim pill.
    var skimEnabled: Bool = true
    var onSkim: (String) -> Void = { _ in }
    var chromeNamespace: Namespace.ID? = nil
    var cardNamespace: Namespace.ID? = nil
    var onSearchSubmit: (URL) -> Void
    var onSearchDismiss: () -> Void
    var onAddressTap: () -> Void = {}
    var onTabsTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var collapse: CGFloat = 0
    @State private var chrome = ChromeCollapse()
    @State private var snapTask: Task<Void, Never>?
    @State private var tintRetryTask: Task<Void, Never>?

    /// How far the slim pill drops below the full bar's bottom edge (05 · Chrome on
    /// scroll): the motion board's 16 against its 26.
    private static let slimBottomDrop: CGFloat = 10
    /// A pause this long below the collapse threshold snaps the bar back to full.
    private static let snapDelay: Duration = .milliseconds(250)
    /// How long to let the page re-render under a new appearance before re-reading it.
    private static let tintRetryDelay: Duration = .milliseconds(600)
    /// The opacity page tints take through the glass (02 · Glass).
    private static let pageTintOpacity = 0.55

    var body: some View {
        GeometryReader { geo in
            let bottomEdge =
                Metrics.Spacing.barBottomEdge(safeAreaBottom: geo.safeAreaInsets.bottom)
                - Self.slimBottomDrop * collapse
            ZStack(alignment: .bottom) {
                pageArea
                GlassEffectContainer {
                    if isSearchOpen {
                        searchSheet
                    } else {
                        bar
                            .padding(.bottom, bottomEdge)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                session?.viewportSize = size
            }
        }
        .onChange(of: colorScheme) { _, _ in rereadPageTint() }
        .onDisappear {
            snapTask?.cancel()
            tintRetryTask?.cancel()
        }
    }

    /// The search sheet over the page, prefilled with the page's address.
    private var searchSheet: some View {
        SearchSheet(
            engine: engine,
            opensFromPage: true,
            skimEnabled: skimEnabled,
            initialText: session?.page.url?.absoluteString ?? "",
            morphNamespace: chromeNamespace,
            suggestions: suggestions,
            recents: recents,
            onOpen: onSearchSubmit,
            onSkim: onSkim,
            onDismiss: onSearchDismiss)
    }

    private var bar: some View {
        ReadingBar(
            host: session?.failure?.host ?? HostFormatter.host(for: session?.page.url),
            tabCount: tabCount,
            canGoBack: session?.canGoBack ?? false,
            isSlim: collapse >= 1,
            collapse: collapse,
            showsLock: session?.failure != nil,
            tint: barTint,
            onBack: { session?.goBack() },
            onAddressTap: {
                expandBar()
                onAddressTap()
            },
            onTabsTap: onTabsTap,
            onMenuTap: {})
    }

    /// The page, or Magpie's own page when it can't load — one view with its tab card.
    @ViewBuilder
    private var pageArea: some View {
        if let session {
            Group {
                if let failure = session.failure {
                    PageLoadFailureView(failure: failure) { session.retry() }
                        .ignoresSafeArea()
                } else {
                    ZStack {
                        WebView(session.page)
                            .ignoresSafeArea()
                            .webViewOnScrollGeometryChange(
                                for: ScrollSnapshot.self,
                                of: ScrollSnapshot.init,
                                action: { _, new in scrollDidChange(new) })
                        WebViewProbe(session: session)
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                    }
                }
            }
            .modifier(CardMatch(namespace: cardNamespace, id: tabID))
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    /// The bar's glass tint: the page's theme colour, else the page's own background,
    /// else the default (02 · Glass).
    private var barTint: Color {
        guard let session, session.failure == nil else { return Palette.pageTintGlass }
        if let themeColor = session.page.themeColor {
            return themeColor.opacity(Self.pageTintOpacity)
        }
        if let background = session.pageBackground {
            return background.opacity(Self.pageTintOpacity)
        }
        return Palette.pageTintGlass
    }

    private func scrollDidChange(_ snapshot: ScrollSnapshot) {
        guard !reduceMotion else { return }
        let step = chrome.scrollDidChange(offsetY: snapshot.offsetY, atEndOfPage: snapshot.atEnd)
        guard step != .unchanged else { return }
        apply(step)
        scheduleSnap()
    }

    /// Expands the bar: the slim pill's tap, and search opening from it.
    private func expandBar() {
        apply(chrome.expand())
    }

    private func apply(_ step: ChromeCollapse.Step) {
        switch step {
        case .unchanged:
            break
        case .track:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { collapse = chrome.progress }
        case .settle:
            withAnimation(Springs.settle.animation) { collapse = chrome.progress }
        }
    }

    private func scheduleSnap() {
        snapTask?.cancel()
        snapTask = Task {
            try? await Task.sleep(for: Self.snapDelay)
            guard !Task.isCancelled else { return }
            apply(chrome.snap())
        }
    }

    /// Reads the page's background again for the new appearance, once now and once
    /// after the page has had a moment to re-render under it.
    private func rereadPageTint() {
        tintRetryTask?.cancel()
        tintRetryTask = Task {
            guard let session else { return }
            await session.refreshPageBackground()
            try? await Task.sleep(for: Self.tintRetryDelay)
            guard !Task.isCancelled else { return }
            await session.refreshPageBackground()
        }
    }
}

/// Names the page so it and its tab card are one view moving between the two surfaces.
private struct CardMatch: ViewModifier {
    let namespace: Namespace.ID?
    let id: Tab.ID?

    func body(content: Content) -> some View {
        if let namespace, let id {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// What the chrome state machine needs from one scroll position.
private struct ScrollSnapshot: Hashable {
    var offsetY: CGFloat
    var atEnd: Bool

    init(_ geometry: ScrollGeometry) {
        offsetY = geometry.contentOffset.y
        let scrollable = geometry.contentSize.height > geometry.containerSize.height + 1
        atEnd = !scrollable || geometry.visibleRect.maxY >= geometry.contentSize.height - 1
    }
}

/// Keeps the session's hold of the web view SwiftUI builds for its page: the snapshot
/// path needs the view, and the page carries none of its own. A zero-size probe lands
/// in the hierarchy beside it and names the nearest web view up its own branch — no
/// window walk, and no URL match to break on a redirect.
private struct WebViewProbe: UIViewRepresentable {
    let session: ReadingSession

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(session: session)
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.remember()
    }

    /// Tries again on every look: the web view can be built after the probe moves in,
    /// and swapped for a new one later.
    final class ProbeView: UIView {
        weak var session: ReadingSession?

        init(session: ReadingSession) {
            self.session = session
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            remember()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            remember()
        }

        func remember() {
            guard window != nil, let session, session.webView?.window == nil else { return }
            session.webViewLookup = { [weak self] in self?.nearestWebView() }
            session.webView = nearestWebView()
        }

        /// The nearest web view in the probe's own branch of the hierarchy.
        private func nearestWebView() -> WKWebView? {
            var ancestor = superview
            while let current = ancestor {
                if let found = current.firstSubview(of: WKWebView.self) {
                    return found
                }
                ancestor = current.superview
            }
            return nil
        }
    }
}

#Preview {
    let session = ReadingSession(url: URL(string: "https://example.org") ?? URL(fileURLWithPath: "/"))
    return ReadingScreen(
        session: session,
        tabID: nil,
        tabCount: 2,
        isSearchOpen: false,
        engine: .default,
        suggestions: StubSuggestionProvider(rowsByPrefix: ["seasoning carbon steel"]),
        recents: RecentSearches(),
        onSearchSubmit: { _ in },
        onSearchDismiss: {}
    )
    .task { await session.run() }
}
