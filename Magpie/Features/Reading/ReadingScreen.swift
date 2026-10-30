import SwiftUI
import WebKit

/// 02 · Reading: a full-bleed web view under the status bar with the ReadingBar
/// floating at the bottom. The bar takes the page's tint and slims on scroll.
struct ReadingScreen: View {

    var tabCount: Int
    var onBack: () -> Void
    var onAddressTap: () -> Void
    var onTabsTap: () -> Void
    var onMenuTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var session: ReadingSession
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

    init(
        url: URL,
        tabCount: Int = 1,
        onBack: @escaping () -> Void = {},
        onAddressTap: @escaping () -> Void = {},
        onTabsTap: @escaping () -> Void = {},
        onMenuTap: @escaping () -> Void = {}
    ) {
        self.tabCount = tabCount
        self.onBack = onBack
        self.onAddressTap = onAddressTap
        self.onTabsTap = onTabsTap
        self.onMenuTap = onMenuTap
        _session = State(initialValue: ReadingSession(url: url))
    }

    var body: some View {
        GeometryReader { geo in
            let bottomEdge =
                Metrics.Spacing.barBottomEdge(safeAreaBottom: geo.safeAreaInsets.bottom)
                - Self.slimBottomDrop * collapse
            ZStack(alignment: .bottom) {
                pageArea
                GlassEffectContainer {
                    ReadingBar(
                        host: session.failure?.host ?? HostFormatter.host(for: session.page.url),
                        tabCount: tabCount,
                        canGoBack: session.canGoBack,
                        isSlim: collapse >= 1,
                        collapse: collapse,
                        isMenuOpen: false,
                        showsLock: session.failure != nil,
                        tint: barTint,
                        onBack: {
                            session.goBack()
                            onBack()
                        },
                        onAddressTap: {
                            expandBar()
                            onAddressTap()
                        },
                        onTabsTap: onTabsTap,
                        onMenuTap: onMenuTap)
                }
                .padding(.bottom, bottomEdge)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task { await session.run() }
        .onChange(of: colorScheme) { _, _ in rereadPageTint() }
        .onDisappear {
            snapTask?.cancel()
            tintRetryTask?.cancel()
        }
    }

    /// The page, or Magpie's own page when it can't load.
    @ViewBuilder
    private var pageArea: some View {
        if let failure = session.failure {
            PageLoadFailureView(failure: failure) { session.retry() }
                .ignoresSafeArea()
        } else {
            WebView(session.page)
                .ignoresSafeArea()
                .webViewOnScrollGeometryChange(
                    for: ScrollSnapshot.self,
                    of: ScrollSnapshot.init,
                    action: { _, new in scrollDidChange(new) })
        }
    }

    /// The bar's glass tint: the page's theme colour, else the page's own background,
    /// else the default (02 · Glass).
    private var barTint: Color {
        if session.failure != nil {
            return Palette.pageTintGlass
        }
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
            await session.refreshPageBackground()
            try? await Task.sleep(for: Self.tintRetryDelay)
            guard !Task.isCancelled else { return }
            await session.refreshPageBackground()
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

#Preview {
    ReadingScreen(url: URL(string: "https://example.org") ?? URL(fileURLWithPath: "/"))
}
