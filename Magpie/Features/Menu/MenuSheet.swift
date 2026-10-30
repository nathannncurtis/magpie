import SwiftUI
import UIKit

/// The menu (04 · 05): the reading bar's glass grows up into a sheet that reaches the
/// screen edges, turning solid as it arrives, with the bar row pinned at its base and
/// ••• held down. Quick actions on top, then the switches that matter.
///
/// The content settles in from the bottom up, the pinned bar row first; a tap on the
/// page, a swipe down, or ••• again folds it back into the bar. Under Reduce Motion it
/// is one 200 ms crossfade.
struct MenuSheet: View {

    /// Layout and timing numbers from the menu spec.
    private enum Layout {
        /// How the content blocks settle in, bottom first: the bar row, then the groups
        /// and the tiles above it.
        enum Block: Int, CaseIterable {
            case bar
            case switches
            case blocking
            case tiles
        }
        /// How far apart the blocks settle.
        static let stagger: Duration = .milliseconds(25)
        /// The morph is under way by the time the first block lands.
        static let firstDelay: Duration = .milliseconds(50)
        /// How far a block rises as it fades in.
        static let rise: CGFloat = 12
        /// How far down a drag must reach before it counts as a dismissal.
        static let dismissDistance: CGFloat = 120
        /// Or how hard it has to be flung.
        static let dismissFling: CGFloat = 240
    }

    /// The host the pinned bar row shows.
    let host: String
    /// The open-tab count.
    let tabCount: Int
    /// Whether the page can go back.
    let canGoBack: Bool
    /// Whether Skim runs here: the Skim tile hides when it can't.
    var skimOffered: Bool = true
    /// Where the pinned row's bottom edge sits above the screen bottom: the floating
    /// bar's own, so the row never moves as the glass grows around it.
    var barBottomEdge: CGFloat = 26
    /// Names the sheet's glass shape so it and the bar's are one piece of glass.
    var morphNamespace: Namespace.ID? = nil

    let onBack: () -> Void
    let onAddressTap: () -> Void
    let onTabsTap: () -> Void
    /// The pinned row's •••: taps again to fold the sheet away.
    let onMenuTap: () -> Void
    /// Every dismissal but that one.
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var arrived: Set<Layout.Block> = []
    @State private var fillSettled = false
    @State private var dragOffset: CGFloat = 0
    @State private var settleTask: Task<Void, Never>?

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Metrics.Radius.sheetTop,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Metrics.Radius.sheetTop,
            style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            tapAway
            sheetBody
        }
        .background {
            // The page dims evenly behind the menu, edge to edge; the dim arrives with
            // the solid fill as the bar grows into the sheet.
            Rectangle()
                .fill(Palette.scrim)
                .ignoresSafeArea()
                .opacity(fillSettled ? 1 : 0)
        }
        .onAppear(perform: arrive)
        .onDisappear {
            settleTask?.cancel()
        }
    }

    /// The area above the sheet: a tap there folds the sheet away.
    private var tapAway: some View {
        Color.clear
            .ignoresSafeArea(edges: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityIdentifier("menu.scrim")
    }

    /// The sheet hugs its content and runs on to the bottom edge of the screen, with the
    /// bar row sitting exactly where the floating bar sat.
    private var sheetBody: some View {
        sheetContent
            .frame(maxWidth: .infinity)
            .modifier(
                MenuSurface(
                    shape: sheetShape,
                    namespace: morphNamespace,
                    fillSettled: fillSettled)
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menu.sheet")
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            MenuGrabber()
                .padding(.top, Metrics.Menu.topPadding)
                .padding(.bottom, Metrics.Menu.grabberGap)
                .opacity(fillSettled ? 1 : 0)
            block(.tiles) { tiles }
            VStack(spacing: Metrics.Menu.groupGap) {
                block(.blocking) { blockingGroup }
                block(.switches) { switchGroup }
            }
            .padding(.bottom, Metrics.Menu.barGap)
            block(.bar) { barRow }
        }
        .offset(y: dragOffset)
        .gesture(dismissDrag)
    }

    // MARK: Quick actions

    @ViewBuilder private var tiles: some View {
        MenuTileRow {
            if skimOffered {
                MenuTile(title: "Skim", action: skim) {
                    Mark(size: Metrics.Menu.tileIconSize, style: .solid)
                }
                .accessibilityIdentifier("menu.tile.skim")
            }
            bookmarkTile
                .accessibilityIdentifier("menu.tile.bookmark")
            shareTile
                .accessibilityIdentifier("menu.tile.share")
            MenuTile(title: "Mods", action: { model.showMods() }) {
                MenuTileSymbol(systemName: "puzzlepiece")
            }
            .accessibilityIdentifier("menu.tile.mods")
        }
    }

    /// The Bookmark tile: a tap saves the page, a second tap takes it back out, and a
    /// long press opens Bookmarks.
    private var bookmarkTile: some View {
        MenuTileFace(title: "Bookmark") {
            Image(systemName: model.currentPageIsBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: Metrics.Menu.tileIconSize, weight: .medium))
                .imageScale(.medium)
        }
        .onTapGesture(perform: toggleBookmark)
        .onLongPressGesture(minimumDuration: 0.5, perform: model.showBookmarks)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Bookmark"))
        .accessibilityValue(
            model.currentPageIsBookmarked ? Text(String(localized: "Saved")) : Text(""))
    }

    /// The Share tile: the system share sheet on the page's address.
    @ViewBuilder private var shareTile: some View {
        if let url = shareURL {
            ShareLink(item: url) {
                MenuTileFace(title: "Share") {
                    MenuTileSymbol(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share"))
        } else {
            MenuTileFace(title: "Share") {
                MenuTileSymbol(systemName: "square.and.arrow.up")
            }
            .opacity(0.3)
            .allowsHitTesting(false)
        }
    }

    private var shareURL: URL? {
        model.currentSession?.page.url ?? model.store.currentTab?.url
    }

    /// The Skim tile: the page's own address, read.
    private func skim() {
        guard let address = model.currentSession?.page.url?.absoluteString else { return }
        model.startSkim(query: address)
    }

    private func toggleBookmark() {
        if model.toggleCurrentPageBookmark() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: Groups

    /// The blocking group: the two toggles, then the archive timing.
    private var blockingGroup: some View {
        MenuGroup {
            toggleRow(
                icon: .symbol("shield.lefthalf.filled"), title: "Block ads & trackers",
                id: "menu.toggle.ads", isDivided: false,
                isOn: Binding(
                    get: { model.blocker.blocksAdsAndTrackers },
                    set: { model.blocker.blocksAdsAndTrackers = $0 }))

            toggleRow(
                icon: .cookie, title: "Block cookie banners",
                id: "menu.toggle.cookies", isDivided: true,
                isOn: Binding(
                    get: { model.blocker.blocksCookieBanners },
                    set: { model.blocker.blocksCookieBanners = $0 }))

            MenuRow(icon: .symbol("archivebox"), title: "Archive inactive tabs") {
                MenuArchiveValue(
                    interval: model.preferences.archiveInterval,
                    choose: { model.preferences.archiveInterval = $0 })
            }
            .divided()
            .accessibilityIdentifier("menu.archive")
        }
    }

    /// The second group: where searches go, whether Skim offers, and Settings.
    private var switchGroup: some View {
        MenuGroup {
            MenuRow(icon: .symbol("globe"), title: "Search engine") {
                MenuValue(text: model.preferences.searchEngine.displayName)
            }
            .action {
                model.showEngineList()
                onDismiss()
            }
            .accessibilityIdentifier("menu.engine")

            toggleRow(
                icon: .mark, title: "Skim for me",
                id: "menu.toggle.skim", isDivided: true,
                isOn: Binding(
                    get: { model.preferences.skimEnabled },
                    set: { model.preferences.skimEnabled = $0 }))

            MenuRow(icon: .symbol("gearshape"), title: "Settings") {
                SettingsChevron()
            }
            .action {
                model.showSettings()
                onDismiss()
            }
            .divided()
            .accessibilityIdentifier("menu.settings")
        }
    }

    private func toggleRow(
        icon: SettingsIcon, title: String, id: String, isDivided: Bool, isOn: Binding<Bool>
    ) -> some View {
        MenuRow(icon: icon, title: title, isDivided: isDivided) {
            Toggle(title, isOn: isOn)
                .toggleStyle(SettingsToggleStyle())
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
    }

    // MARK: The pinned bar row

    /// The bar, as the sheet's base row: the same buttons in the same places, ••• held
    /// down, never having moved.
    private var barRow: some View {
        HStack(spacing: 0) {
            CircleButton(systemName: "chevron.backward", action: onBack)
                .disabled(!canGoBack)
                .accessibilityLabel(Text("Back"))
                .accessibilityIdentifier("bar.back")
            URLPill(host: host, action: onAddressTap)
                .accessibilityIdentifier("bar.url")
            CircleButton(action: onTabsTap) { TabCount(count: tabCount) }
                .accessibilityLabel(Text("Tabs"))
                .accessibilityIdentifier("bar.tabs")
            CircleButton(systemName: "ellipsis", isPressed: true, action: onMenuTap)
                .accessibilityLabel(Text("Menu"))
                .accessibilityIdentifier("bar.menu")
        }
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .padding(.horizontal, Metrics.Menu.barRowSideInset - 4)
        .padding(.top, Metrics.Menu.barRowTopPadding)
        .padding(.bottom, barBottomEdge)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.separator)
                .frame(height: 0.5)
                .padding(.horizontal, Metrics.Menu.barRowSideInset)
        }
        .foregroundStyle(Palette.textPrimary)
    }

    // MARK: Behaviour

    /// Follows a swipe down; a long enough or hard enough drag dismisses.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { change in
                guard !reduceMotion, change.translation.height > 0 else { return }
                dragOffset = change.translation.height
            }
            .onEnded { change in
                let distance = change.translation.height
                let fling = change.predictedEndTranslation.height - distance
                if distance > Layout.dismissDistance || fling > Layout.dismissFling {
                    onDismiss()
                } else {
                    withAnimation(Springs.chrome.animation) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// One content block, held just below where it lands until its turn comes.
    private func block<Content: View>(
        _ block: Layout.Block, @ViewBuilder _ content: () -> Content
    ) -> some View {
        let shown = arrived.contains(block)
        return content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Layout.rise)
    }

    /// The fill settles with the morph; the blocks land from the bottom up, the bar row
    /// first. Under Reduce Motion, one crossfade brings the whole menu.
    private func arrive() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                fillSettled = true
                arrived = Set(Layout.Block.allCases)
            }
            return
        }
        withAnimation(Springs.chrome.animation) {
            fillSettled = true
        }
        settleTask = Task {
            do {
                try await Task.sleep(for: Layout.firstDelay)
                for block in Layout.Block.allCases {
                    guard !Task.isCancelled else { return }
                    withAnimation(Springs.chrome.animation) {
                        _ = arrived.insert(block)
                    }
                    guard block != Layout.Block.allCases.last else { break }
                    try await Task.sleep(for: Layout.stagger)
                }
            } catch {
                return
            }
        }
    }
}

/// The sheet's surface: glass, which the reading bar grows into, going solid as it
/// settles over the page.
private struct MenuSurface: ViewModifier {
    let shape: UnevenRoundedRectangle
    let namespace: Namespace.ID?
    let fillSettled: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Palette.sheetSolid).opacity(fillSettled ? 1 : 0))
            .glassEffect(.regular, in: shape)
            .modifier(MorphTag(namespace: namespace))
    }
}

/// Tags the sheet's glass surface as the chrome shape, so the bar and the menu are one
/// piece of glass moving between the two.
private struct MorphTag: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.glassEffectID(ChromeGlassID.chrome, in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        Rectangle().fill(Palette.paper)
        MenuSheet(
            host: "quietweb.org",
            tabCount: 4,
            canGoBack: true,
            onBack: {},
            onAddressTap: {},
            onTabsTap: {},
            onMenuTap: {},
            onDismiss: {})
    }
    .environment(AppModel())
    .ignoresSafeArea()
}
