import SwiftUI
import WebKit

/// The root switch (04 · the navigation map): the launch search, reading, or the tab
/// stack. The bar and the search sheet are one glass shape, and the page and its tab
/// card are one view, both moving between the surfaces.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The bar and the search sheet morph as one glass shape.
    @Namespace private var chrome
    /// The page and its tab card trade places.
    @Namespace private var cards

    /// The restored surface lands with nothing animating; every move after it does.
    @State private var movesWithChrome = false

    var body: some View {
        ZStack {
            // Pages that still owe their tab a picture keep drawing in the window,
            // unseen, under whatever surface shows; each leaves once its picture lands.
            // Laid out exactly as the reading screen lays out its page, from below
            // the status bar to the bottom edge, so the picture matches one taken
            // in place.
            ForEach(model.pagesStillDrawing, id: \.self) { session in
                WebView(session.page)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear { session.isDrawnUnseen = true }
                    .onDisappear { session.isDrawnUnseen = false }
                    .opacity(Self.unseen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // Gone at once, never animated out: a reading screen can take
                    // the page the same moment.
                    .transition(.identity)
            }
            .animation(nil, value: model.pagesStillDrawing)
            switch model.surface {
            case .launchSearch:
                LaunchIntro(
                    plays: model.playsLaunchIntro,
                    onFinished: { model.launchIntroDone() }
                ) {
                    LaunchScreen(
                        engine: model.engine,
                        skimEnabled: model.offersSkim && !model.searchIsPrivate,
                        suggestionsEnabled: model.suggestionsEnabled,
                        focusSuspended: coversOverLaunch,
                        isPrivate: model.launchIsPrivate,
                        suggestions: model.suggestions,
                        recents: model.searchRecents,
                        initialText: model.searchPrefill ?? "",
                        onSkim: { model.startSkim(query: $0) },
                        onOpen: { model.openFromLaunch($0) },
                        onDismiss: { model.dismissLaunchSearch() },
                        hasTabs: !model.store.tabs.isEmpty,
                        archivedCount: model.store.archivedTabs.count,
                        onNewTab: { model.newTabFromTabs() },
                        onNewPrivateTab: { model.newPrivateTab() },
                        onShowArchive: { model.showArchive() },
                        onShowSettings: { model.showSettings() }
                    )
                    // Back to the stack, when there is one to go back to.
                    .backSwipe(isEnabled: !model.store.tabs.isEmpty) { model.dismissLaunchSearch() }
                }
            case .reading(let searchOpen):
                ReadingScreen(
                    session: model.currentSession,
                    tabID: model.store.currentTabID,
                    tabCount: model.store.tabs.count,
                    isPrivate: model.currentIsPrivate,
                    isSearchOpen: searchOpen,
                    engine: model.engine,
                    skimEnabled: model.offersSkim && !model.searchIsPrivate,
                    skimRunsHere: model.skimAvailable && !model.currentIsPrivate,
                    suggestionsEnabled: model.suggestionsEnabled,
                    focusSuspended: coversOverLaunch,
                    suggestions: model.suggestions,
                    recents: model.searchRecents,
                    onSkim: { model.startSkim(query: $0) },
                    chromeNamespace: chrome,
                    cardNamespace: cards,
                    onSearchSubmit: { model.navigateCurrent($0) },
                    onSearchDismiss: { model.closeSearchOverPage() },
                    onAddressTap: { model.openSearchOverPage() },
                    onTabsTap: { model.showTabs() },
                    onPageSize: { model.notePageSize($0) },
                    arrivalPicture: model.cardArrivalPicture,
                    onArrivalDone: { model.cardArrivalDone() },
                    isFinding: Bindable(model).isFindingInPage
                )
                // The page never answers the keyboard. An address just submitted
                // arrives with the keys still dropping, and a first frame squeezed
                // by them is the wrong size to arm captures at; the sheet over the
                // page is the piece that rides the keys.
                .ignoresSafeArea(.keyboard, edges: searchOpen ? [] : .bottom)
                .onAppear { model.readingScreenAppeared() }
                .onDisappear { model.readingScreenDisappeared() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("reading.screen")
            case .tabs:
                TabsScreen(
                    store: model.store,
                    onOpen: { model.openTab($0) },
                    onNewTab: { model.newTabFromTabs() },
                    onNewPrivateTab: { model.newPrivateTab() },
                    onClose: { model.closeTab($0) },
                    onShowArchive: { model.showArchive() },
                    pageBackground: { id in model.sessions[id]?.pageBackground },
                    transitionNamespace: cards
                )
                // Back to the page the stack was opened from.
                .backSwipe(isEnabled: model.canLeaveTabs) { model.leaveTabs() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tabs.screen")
            case .archive:
                ArchiveScreen(
                    store: model.store,
                    onRestore: { model.restoreArchivedTab($0) },
                    onDone: { model.doneWithArchive() }
                )
                .backSwipe { model.doneWithArchive() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("archive.screen")
            case .bookmarks:
                BookmarksScreen(
                    store: model.bookmarks,
                    onOpen: { model.openBookmark($0) },
                    onClose: { model.closeBookmarks() }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bookmarks.screen")
            case .history:
                HistoryScreen(
                    store: model.history,
                    onOpen: { model.openHistoryEntry($0) },
                    onDone: { model.closeHistory() }
                )
                .backSwipe { model.closeHistory() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("history.screen")
            case .mods:
                ModsScreen(
                    directory: model.modDirectory,
                    store: model.modStore,
                    onDone: { model.closeMods() }
                )
                .backSwipe { model.closeMods() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mods.screen")
            case .skim:
                SkimFlowScreen()
                    .backSwipe { model.cancelSkim() }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("skim.screen")
            case nil:
                // Nothing has started yet: paper, while the saved tabs load. The cold
                // start's first frame matches it, so the intro's mist fading up is the
                // first change on screen; a restore simply lands the reading screen.
                Palette.paper
                    .ignoresSafeArea()
                    .accessibilityIdentifier("boot.paper")
            }
        }
        .animation(movesWithChrome ? transition : nil, value: model.surface)
        .onChange(of: model.surface != nil) { _, present in
            guard present else { return }
            movesWithChrome = true
        }
        // The first launch: Welcome, then the engine picker, over whatever is beneath.
        .fullScreenCover(isPresented: onboardingUp) {
            OnboardingFlow(preferences: model.preferences)
        }
        .fullScreenCover(isPresented: settingsBinding) {
            SettingsScreen(opening: model.settingsPage)
        }
        .statusBarInk(statusBarInk)
    }

    /// Over a page the status bar sits on the page's own colours, so its ink follows what
    /// is under it; everywhere else, and under a full screen, it is the system's.
    private var statusBarInk: StatusBarInk {
        guard case .reading = model.surface, !coversOverLaunch else { return .automatic }
        return .over(ReadingScreen.statusBarFill(for: model.currentSession), scheme: colorScheme)
    }

    private var onboardingUp: Binding<Bool> {
        Binding(
            get: { model.needsOnboarding },
            set: { _ in model.completeOnboarding() })
    }

    /// While a full screen sits over the app, the launch sheet's field stays out of the
    /// keyboard's way — and onboarding comes before that field ever focuses.
    private var coversOverLaunch: Bool {
        model.needsOnboarding || model.showsSettings
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { model.showsSettings },
            set: { if !$0 { model.closeSettings() } })
    }

    /// Drawn, but not seen: WebKit keeps drawing a page that is in the window, which a
    /// hidden or fully transparent view is not taken to be.
    private static let unseen = 0.01

    private var transition: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
