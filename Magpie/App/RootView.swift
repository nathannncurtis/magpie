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
                        skimEnabled: model.offersSkim,
                        suggestionsEnabled: model.suggestionsEnabled,
                        focusSuspended: coversOverLaunch,
                        suggestions: model.suggestions,
                        recents: model.recents,
                        initialText: model.searchPrefill ?? "",
                        onSkim: { model.startSkim(query: $0) },
                        onOpen: { model.openFromLaunch($0) },
                        onDismiss: { model.dismissLaunchSearch() }
                    )
                case .reading(let searchOpen):
                    ReadingScreen(
                        session: model.currentSession,
                        tabID: model.store.currentTabID,
                        tabCount: model.store.tabs.count,
                        isSearchOpen: searchOpen,
                        engine: model.engine,
                        skimEnabled: model.offersSkim,
                        suggestionsEnabled: model.suggestionsEnabled,
                        focusSuspended: coversOverLaunch,
                        suggestions: model.suggestions,
                        recents: model.recents,
                        onSkim: { model.startSkim(query: $0) },
                        chromeNamespace: chrome,
                        cardNamespace: cards,
                        onSearchSubmit: { model.navigateCurrent($0) },
                        onSearchDismiss: { model.closeSearchOverPage() },
                        onAddressTap: { model.openSearchOverPage() },
                        onTabsTap: { model.openTabs(viewport: geo.size) }
                    )
                    .accessibilityElement(children: .contain)
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
                    .accessibilityElement(children: .contain)
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
                case .mods:
                    ModsScreen(
                        directory: model.modDirectory,
                        store: model.modStore,
                        onDone: { model.closeMods() }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("mods.screen")
                case .skim:
                    SkimFlowScreen()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("skim.screen")
                case nil:
                    // Nothing has started yet: the mist, while the saved tabs load.
                    MistBackground()
                        .ignoresSafeArea()
                        .accessibilityIdentifier("boot.mist")
                }
            }
            .animation(movesWithChrome ? transition : nil, value: model.surface)
            .onChange(of: model.surface != nil) { _, present in
                guard present else { return }
                movesWithChrome = true
            }
        }
        // The first launch: Welcome, then the engine picker, over whatever is beneath.
        .fullScreenCover(isPresented: onboardingUp) {
            OnboardingFlow(preferences: model.preferences)
        }
        .fullScreenCover(isPresented: settingsBinding) {
            SettingsScreen()
        }
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
            set: { if !$0 { model.showsSettings = false } })
    }

    private var transition: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
