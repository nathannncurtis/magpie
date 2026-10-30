import SwiftUI

/// The root switch (04 · the navigation map): the launch search, reading, or the tab
/// stack. The bar and the search sheet are one glass shape, and the page and its tab
/// card are one view, both moving between the surfaces.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bar and the search sheet morph as one glass shape.
    @Namespace private var chrome
    /// The page and its tab card trade places.
    @Namespace private var cards

    /// The restored surface lands with nothing animating; every move after it does.
    @State private var movesWithChrome = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch model.surface {
                case .launchSearch:
                    LaunchScreen(
                        engine: model.engine,
                        suggestions: model.suggestions,
                        recents: model.recents,
                        onOpen: { model.openFromLaunch($0) },
                        onDismiss: { model.dismissLaunchSearch() }
                    )
                    .accessibilityIdentifier("launch.screen")
                case .reading(let searchOpen):
                    ReadingScreen(
                        session: model.currentSession,
                        tabID: model.store.currentTabID,
                        tabCount: model.store.tabs.count,
                        isSearchOpen: searchOpen,
                        engine: model.engine,
                        suggestions: model.suggestions,
                        recents: model.recents,
                        chromeNamespace: chrome,
                        cardNamespace: cards,
                        onSearchSubmit: { model.navigateCurrent($0) },
                        onSearchDismiss: { model.closeSearchOverPage() },
                        onAddressTap: { model.openSearchOverPage() },
                        onTabsTap: { openTabs(viewport: geo.size) }
                    )
                    .accessibilityIdentifier("reading.screen")
                case .tabs:
                    TabsScreen(
                        store: model.store,
                        onOpen: { model.openTab($0) },
                        onNewTab: { model.newTabFromTabs() },
                        onClose: { model.closeTab($0) },
                        onShowArchive: { model.showArchive() },
                        transitionNamespace: cards
                    )
                    .accessibilityIdentifier("tabs.screen")
                case .archive:
                    ArchiveScreen(
                        store: model.store,
                        onRestore: { model.restoreArchivedTab($0) },
                        onDone: { model.doneWithArchive() }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("archive.screen")
                case .bookmarks:
                    BookmarksScreen(
                        store: model.bookmarks,
                        onOpen: { model.openBookmark($0) }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bookmarks.screen")
                case nil:
                    // Nothing has started yet: the mist, while the saved tabs load.
                    MistBackground()
                        .ignoresSafeArea()
                }
            }
            .animation(movesWithChrome ? transition : nil, value: model.surface)
            .onChange(of: model.surface != nil) { _, present in
                guard present else { return }
                movesWithChrome = true
            }
        }
    }

    private var transition: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation
    }

    /// The tab count: the page is snapshotted first, so the card shows what it showed.
    private func openTabs(viewport: CGSize) {
        Task { @MainActor in
            await model.captureCurrentSnapshot(viewport: viewport)
            model.showTabs()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
