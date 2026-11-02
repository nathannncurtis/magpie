import SwiftUI
import WebKit

/// 02 · Reading: a web view that starts below the status bar and runs under the bar to
/// the bottom edge, with the ReadingBar floating at the bottom. The strip above the
/// page, under the status bar, takes the page's own top color, so the screen still
/// reads edge to edge. The bar takes the page's tint and slims on scroll; the URL
/// pill opens the search sheet over the page, growing from the bar as one glass shape
/// (05 · The bar into the sheet), and the page is one view with its tab card (05 · The
/// page into its card).
struct ReadingScreen: View {

    let session: ReadingSession?
    let tabID: Tab.ID?
    var tabCount: Int
    /// Whether the tab is private: its bar and menu say so.
    var isPrivate = false
    var isSearchOpen: Bool
    var engine: SearchEngine
    /// Whether the search sheet over the page shows its Skim pill.
    var skimEnabled: Bool = true
    /// Whether Skim runs on this device at all: the menu's Skim tile hides when it
    /// can't, whatever the pill's own toggle says.
    var skimRunsHere: Bool = true
    var suggestionsEnabled: Bool = true
    /// While a full screen (Settings) covers the sheet over the page.
    var focusSuspended: Bool = false
    var suggestions: any SuggestionProviding
    var recents: any RecentSearchStoring
    /// The user's hosts and the pasteboard, for the sheet's field.
    var addressAssist = AddressAssist()
    var onSkim: (String) -> Void = { _ in }
    var chromeNamespace: Namespace.ID? = nil
    var cardNamespace: Namespace.ID? = nil
    var onSearchSubmit: (URL) -> Void
    var onSearchDismiss: () -> Void
    var onAddressTap: () -> Void = {}
    var onTabsTap: () -> Void = {}
    /// Whether a tab lies this many places along the stack (1 next, -1 previous): the
    /// bar's sideways swipe rubber-bands where none does.
    var hasAdjacentTab: (Int) -> Bool = { _ in false }
    /// The picture of the tab that far along, slid in beside the page as it moves.
    var adjacentPicture: (Int) -> Data? = { _ in nil }
    /// The bar's swipe stepped to the tab this many places along.
    var onStepTab: (Int) -> Void = { _ in }
    /// The page area's size, kept past this screen: a session made with no reading
    /// screen up still needs a region to capture at.
    var onPageSize: (CGSize) -> Void = { _ in }
    /// The card's picture, held over the page while the card grows back into it: the
    /// web view re-hosts blank and lays out at the card's width for a few frames.
    var arrivalPicture: Data? = nil
    var onArrivalDone: () -> Void = {}
    /// A link from the page's long-press menu, opened in a tab of its own; the flag
    /// asks for a private one.
    var onOpenLink: (URL, Bool) -> Void = { _, _ in }
    /// The find bar over the page (⌘F).
    var isFinding: Binding<Bool> = .constant(false)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var collapse: CGFloat = 0
    /// The page area's size while the screen is at rest, handed to a session that arrives
    /// after the last geometry change — a session change alone measures nothing.
    @State private var restingSize: CGSize?
    @State private var sizeSettleTask: Task<Void, Never>?
    @State private var chrome = ChromeCollapse()
    @State private var isMenuOpen = false
    @State private var snapTask: Task<Void, Never>?
    @State private var tintRetryTask: Task<Void, Never>?
    /// How far a sideways bar swipe has carried the page, and how far the bar itself
    /// follows the finger.
    @State private var pageShift: CGFloat = 0
    @State private var barShift: CGFloat = 0
    /// How far an upward bar swipe has lifted the bar, and whether it has crossed the
    /// distance that opens the stack.
    @State private var barRise: CGFloat = 0
    @State private var upArmed = false
    /// Counts committed tab steps, for the haptic.
    @State private var stepCommits = 0
    /// While a committed step slides the page away.
    @State private var isStepping = false

    /// How far the slim pill drops below the full bar's bottom edge (05 · Chrome on
    /// scroll): the motion board's 16 against its 26.
    private static let slimBottomDrop: CGFloat = 10
    /// A pause this long below the collapse threshold snaps the bar back to full.
    private static let snapDelay: Duration = .milliseconds(250)
    /// How long a size must hold before it counts as the screen at rest.
    private static let sizeSettleDelay: Duration = .milliseconds(200)
    /// How long the card's picture stays over the page: the chrome spring's growth, plus
    /// the page's first paint at full width.
    private static let arrivalHold: Duration = .milliseconds(550)
    /// How long to let the page re-render under a new appearance before re-reading it.
    private static let tintRetryDelay: Duration = .milliseconds(600)
    /// The opacity page tints take through the glass (02 · Glass).
    private static let pageTintOpacity = 0.55
    /// How much of the page's shift the bar follows, and the most it travels.
    private static let barFollow: CGFloat = 0.35
    private static let barFollowLimit: CGFloat = 48
    /// How long a committed step slides the page out before the next tab takes over.
    private static let stepSlide: Duration = .milliseconds(180)

    var body: some View {
        GeometryReader { geo in
            let bottomEdge =
                Metrics.Spacing.barBottomEdge(safeAreaBottom: geo.safeAreaInsets.bottom)
                - Self.slimBottomDrop * collapse
            let menuBottomEdge = Metrics.Spacing.barBottomEdge(
                safeAreaBottom: geo.safeAreaInsets.bottom)
            ZStack(alignment: .bottom) {
                neighborPage(width: geo.size.width)
                pageArea(bottomClearance: menuBottomEdge + Metrics.Bar.readingHeight)
                    .offset(x: pageShift)
                GlassEffectContainer {
                    if isSearchOpen {
                        searchSheet
                    } else if isMenuOpen {
                        menuSheet(bottomEdge: menuBottomEdge)
                    } else {
                        bar(width: geo.size.width)
                            .offset(x: barShift, y: barRise)
                            .padding(.bottom, bottomEdge)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                // A capture happens only at rest. With the sheet or keyboard up the page
                // is squeezed, and a picture of that is a picture of the wrong shape; a
                // size that keeps changing is one of them in motion. Only a size that
                // holds reaches the session.
                sizeSettleTask?.cancel()
                guard !isSearchOpen else { return }
                // The size itself is a fact about the screen, passed on at once; only
                // the session's capture waits for it to hold.
                onPageSize(size)
                let heldSize = size
                sizeSettleTask = Task {
                    try? await Task.sleep(for: Self.sizeSettleDelay)
                    guard !Task.isCancelled else { return }
                    restingSize = heldSize
                    guard let session else { return }
                    if session.viewportSize != heldSize {
                        session.viewportSize = heldSize
                    }
                    session.captureOpportunity()
                }
            }
            // A session can arrive, or its page can commit, with no geometry change to
            // follow — both are capture opportunities of their own. The capture itself
            // debounces: one still in flight is replaced by the next.
            .onChange(of: session) { _, incoming in
                guard let incoming else { return }
                if let restingSize, incoming.viewportSize == nil {
                    incoming.viewportSize = restingSize
                }
                incoming.captureOpportunity()
            }
            // The sheet closing is the resting-size opportunity a capture waited out,
            // once the dismissal's own motion is over.
            .onChange(of: isSearchOpen) { _, open in
                guard !open else { return }
                settleThenCapture()
            }
            .onChange(of: session?.page.url) { _, _ in
                session?.captureOpportunity()
            }
            // The title follows the page itself, not the settle moments.
            .onChange(of: session?.page.title) { _, _ in
                session?.titleKnown()
            }
        }
        // The strip the page leaves above itself, under the status bar: filled with the
        // page's own top color, so nothing shows through from the surface before.
        .background(topEdgeFill.ignoresSafeArea(edges: .top))
        .modifier(PageDialogAlert(dialogs: session?.dialogs))
        .onChange(of: colorScheme) { _, _ in rereadPageTint() }
        .sensoryFeedback(.selection, trigger: stepCommits)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: upArmed) { _, armed in armed }
        .onDisappear {
            snapTask?.cancel()
            tintRetryTask?.cancel()
            sizeSettleTask?.cancel()
            session?.screenWentAway()
        }
    }

    /// The menu (05): the bar's glass grows up into it, the bar row pinned in place.
    private func menuSheet(bottomEdge: CGFloat) -> some View {
        MenuSheet(
            host: session?.failure?.host ?? HostFormatter.host(for: session?.committedURL),
            tabCount: tabCount,
            canGoBack: session?.canGoBack ?? false,
            showsWarning: session?.failure != nil,
            isPrivate: isPrivate,
            skimOffered: skimRunsHere,
            barBottomEdge: bottomEdge,
            morphNamespace: chromeNamespace,
            onBack: { session?.goBack() },
            onAddressTap: {
                closeMenu()
                expandBar()
                onAddressTap()
            },
            onTabsTap: onTabsTap,
            onMenuTap: closeMenu,
            onDismiss: closeMenu
        )
        .background {
            // Esc folds the menu back, as a tap away does.
            Button(String(localized: "Close menu"), action: closeMenu)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// The search sheet over the page, prefilled with the page's address.
    private var searchSheet: some View {
        SearchSheet(
            engine: engine,
            opensFromPage: true,
            skimEnabled: skimEnabled,
            suggestionsEnabled: suggestionsEnabled,
            focusSuspended: focusSuspended,
            initialText: session?.committedURL?.absoluteString ?? "",
            morphNamespace: chromeNamespace,
            suggestions: suggestions,
            recents: recents,
            addressAssist: addressAssist,
            onOpen: onSearchSubmit,
            onSkim: onSkim,
            onDismiss: onSearchDismiss)
    }

    private func bar(width: CGFloat) -> some View {
        ReadingBar(
            host: session?.failure?.host ?? HostFormatter.host(for: session?.committedURL),
            tabCount: tabCount,
            canGoBack: session?.canGoBack ?? false,
            isSlim: collapse >= 1,
            collapse: collapse,
            showsWarning: session?.failure != nil,
            isPrivate: isPrivate,
            tint: barTint,
            glassNamespace: chromeNamespace,
            swipe: barSwipe(width: width),
            onBack: { session?.goBack() },
            onAddressTap: {
                expandBar()
                onAddressTap()
            },
            onTabsTap: onTabsTap,
            onMenuTap: {
                expandBar()
                openMenu()
            })
    }

    // MARK: Bar swipes

    private func barSwipe(width: CGFloat) -> BarSwipeHandlers {
        BarSwipeHandlers(
            changed: { axis, translation in barSwipeChanged(axis, translation) },
            ended: { axis, translation, predicted in
                barSwipeEnded(axis, translation, predicted, width: width)
            },
            canceled: { resetBarSwipe() })
    }

    private func barSwipeChanged(_ axis: BarSwipe.Axis, _ translation: CGSize) {
        guard !isStepping else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch axis {
            case .horizontal:
                pageShift = BarSwipe.offset(
                    translation: translation.width,
                    hasPrevious: hasAdjacentTab(-1), hasNext: hasAdjacentTab(1))
                barShift = min(
                    max(pageShift * Self.barFollow, -Self.barFollowLimit), Self.barFollowLimit)
            case .up:
                barRise = BarSwipe.rise(translationY: translation.height)
                upArmed = translation.height <= -BarSwipe.upDistance
            }
        }
    }

    private func barSwipeEnded(
        _ axis: BarSwipe.Axis, _ translation: CGSize, _ predicted: CGSize, width: CGFloat
    ) {
        guard !isStepping else { return }
        switch axis {
        case .horizontal:
            let step = BarSwipe.step(
                translation: translation.width, predicted: predicted.width, width: width,
                hasPrevious: hasAdjacentTab(-1), hasNext: hasAdjacentTab(1))
            guard step != 0 else { return resetBarSwipe() }
            commitStep(step, width: width)
        case .up:
            let opens = BarSwipe.opensStack(
                translationY: translation.height, predictedY: predicted.height)
            resetBarSwipe()
            if opens { onTabsTap() }
        }
    }

    /// The page slides out the way the finger took it, the next tab's picture in behind,
    /// then the tab itself takes over in place.
    private func commitStep(_ step: Int, width: CGFloat) {
        stepCommits += 1
        isStepping = true
        withAnimation(Springs.chrome.unlessReduced(reduceMotion: reduceMotion)) {
            pageShift = reduceMotion ? 0 : -CGFloat(step) * width
            barShift = 0
        }
        Task {
            try? await Task.sleep(for: reduceMotion ? .zero : Self.stepSlide)
            onStepTab(step)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pageShift = 0 }
            isStepping = false
        }
    }

    private func resetBarSwipe() {
        withAnimation(Springs.settle.unlessReduced(reduceMotion: reduceMotion)) {
            pageShift = 0
            barShift = 0
            barRise = 0
        }
        upArmed = false
    }

    /// The tab the page is being slid toward, drawn from its picture beside the page.
    @ViewBuilder
    private func neighborPage(width: CGFloat) -> some View {
        if pageShift != 0 {
            let delta = pageShift < 0 ? 1 : -1
            let edge = pageShift < 0 ? width : -width
            if let picture = adjacentPicture(delta).flatMap(UIImage.init(data:)) {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .ignoresSafeArea(edges: .bottom)
                    .offset(x: edge + pageShift)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The page, or Magpie's own page when it can't load — one view with its tab card.
    ///
    /// `bottomClearance` is how far the full bar reaches up from the bottom edge: the
    /// page's end scrolls clear of it, while the page itself still runs on under it.
    @ViewBuilder
    private func pageArea(bottomClearance: CGFloat) -> some View {
        if let session {
            Group {
                if let failure = session.failure {
                    PageLoadFailureView(failure: failure) { session.retry() }
                        .ignoresSafeArea()
                } else {
                    ZStack {
                        WebView(session.page)
                            .findNavigator(isPresented: isFinding)
                            // Edge swipes go back and forward through the page's history.
                            .backSwipe(isEnabled: session.canGoBack) { session.goBack() }
                            .forwardSwipe(isEnabled: session.canGoForward) { session.goForward() }
                            // WebKit's own edge swipe stays off: it would hold the touch.
                            .webViewBackForwardNavigationGestures(.disabled)
                            .safeAreaPadding(.bottom, bottomClearance)
                            // The page starts below the status bar and runs under the
                            // bar to the bottom edge; the strip it leaves above takes
                            // the page's own top color.
                            .ignoresSafeArea(edges: .bottom)
                            .webViewOnScrollGeometryChange(
                                for: ScrollSnapshot.self,
                                of: ScrollSnapshot.init,
                                action: { _, new in scrollDidChange(new) }
                            )
                            // A tab opened over this one swaps the view out with an
                            // animation; the root waits for it to let the page go
                            // before drawing the page unseen in a view of its own.
                            .onAppear { session.readingViewAppeared() }
                            .onDisappear { session.readingViewDisappeared() }
                        WebViewProbe(session: session, isPrivate: isPrivate, onOpenLink: onOpenLink)
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                        if let picture = arrivalPicture.flatMap(UIImage.init(data:)) {
                            Image(uiImage: picture)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .clipped()
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        }
                    }
                    .task(id: arrivalPicture != nil) {
                        guard arrivalPicture != nil else { return }
                        try? await Task.sleep(for: Self.arrivalHold)
                        guard !Task.isCancelled else { return }
                        withAnimation(Springs.fadeIn) { onArrivalDone() }
                    }
                    // One view per session: a page re-hosted on a session change has
                    // been seen to keep the old view's stale handle, and a fresh view
                    // leaves no doubt about which page the probe names.
                    .id(ObjectIdentifier(session))
                }
            }
            .modifier(CardMatch(namespace: cardNamespace, id: tabID))
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    /// The bar's glass tint: the page's theme color, else the page's own background,
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

    /// The color of the strip above the page, under the status bar: the page's own top
    /// color at full strength, solid rather than glass, so the screen still reads edge
    /// to edge with the page starting below the inset. Paper when the page has no color
    /// of its own to lend.
    private var topEdgeFill: Color { Self.topEdgeFill(for: session) }

    /// What sits under the status bar, for its ink: the color read at the top of the
    /// page as it rests, else the strip's own.
    static func statusBarFill(for session: ReadingSession?) -> Color {
        if let session, session.failure == nil, let top = session.topColor { return top }
        return topEdgeFill(for: session)
    }

    /// The strip's color: the page's theme color, else its background, else paper.
    static func topEdgeFill(for session: ReadingSession?) -> Color {
        guard let session, session.failure == nil else { return Palette.paper }
        if let themeColor = session.page.themeColor {
            return themeColor
        }
        return session.pageBackground ?? Palette.paper
    }

    private func scrollDidChange(_ snapshot: ScrollSnapshot) {
        // A page moves itself while it loads — layout, restored positions — and none of
        // that is the reader scrolling: the bar holds, and the reading starts after.
        if session?.page.isLoading ?? true {
            chrome.forgetOffset()
            return
        }
        // Where the reader rests is what the tab's card should show: each scroll restarts
        // the wait, and the picture is taken once the page holds still.
        settleThenCapture()
        guard !reduceMotion else { return }
        let step = chrome.scrollDidChange(offsetY: snapshot.offsetY, atEndOfPage: snapshot.atEnd)
        guard step != .unchanged else { return }
        apply(step)
        scheduleSnap()
    }

    /// Fires the capture opportunity once the screen has been still for the settle delay.
    private func settleThenCapture() {
        sizeSettleTask?.cancel()
        sizeSettleTask = Task {
            try? await Task.sleep(for: Self.sizeSettleDelay)
            guard !Task.isCancelled, let session else { return }
            session.captureOpportunity()
            await session.refreshTopColor()
        }
    }

    /// Expands the bar: the slim pill's tap, and search opening from it.
    private func expandBar() {
        apply(chrome.expand())
    }

    /// Opens the menu on the same spring the glass grows on.
    private func openMenu() {
        withAnimation(Springs.chrome.resolved(reduceMotion: reduceMotion)) {
            isMenuOpen = true
        }
    }

    /// Folds the menu back into the bar.
    private func closeMenu() {
        withAnimation(Springs.chrome.resolved(reduceMotion: reduceMotion)) {
            isMenuOpen = false
        }
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
    let isPrivate: Bool
    let onOpenLink: (URL, Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(session: session)
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        // The screen's session can change under the same probe: re-bind it, or the
        // probe keeps serving the first session's view.
        view.session = session
        view.linkMenu.isPrivate = isPrivate
        view.linkMenu.onOpenLink = onOpenLink
        view.remember()
        // Read here so the control ends when the page is done loading.
        view.loadingChanged(isLoading: session.page.isLoading)
    }

    /// Tries again on every look: the web view can be built after the probe moves in,
    /// and swapped for a new one later.
    final class ProbeView: UIView {
        weak var session: ReadingSession?
        private weak var refreshedView: WKWebView?
        private weak var refreshControl: UIRefreshControl?
        private var refreshTimeout: Task<Void, Never>?
        /// The long-press menu on links, held here: the web view keeps its delegate weakly.
        let linkMenu = LinkMenuDelegate()

        /// How long a pull may spin before it is ended whatever the page did.
        private static let refreshLimit: Duration = .seconds(15)

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
            installRefresh()
            guard window != nil, let session, session.webView?.window == nil else { return }
            session.webViewLookup = { [weak self] in self?.nearestWebView() }
            session.webView = nearestWebView()
        }

        /// Pull to refresh, with the system's control on the page's own scroll view.
        private func installRefresh() {
            guard let view = nearestWebView(), view !== refreshedView else { return }
            let control = UIRefreshControl()
            control.addAction(
                UIAction { [weak self] _ in self?.pulled() }, for: .valueChanged)
            view.scrollView.refreshControl = control
            linkMenu.install(on: view)
            refreshedView = view
            refreshControl = control
        }

        private func pulled() {
            session?.retry()
            refreshTimeout?.cancel()
            refreshTimeout = Task { [weak self] in
                try? await Task.sleep(for: Self.refreshLimit)
                guard !Task.isCancelled else { return }
                self?.refreshControl?.endRefreshing()
            }
        }

        func loadingChanged(isLoading: Bool) {
            guard !isLoading, refreshControl?.isRefreshing == true else { return }
            refreshTimeout?.cancel()
            refreshControl?.endRefreshing()
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
