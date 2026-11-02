import SwiftUI

/// The tabs screen: the mist, the stack, and the bottom row, with a switch at the top
/// between the ordinary stack and the private one. Each mode shows only its own tabs; the
/// private mode sits on night mist whatever the appearance, and says so when it is empty.
///
/// Everything sizes from the container, never from the screen, so a wider foldable
/// layout can reuse the screen as it is.
struct TabsScreen: View {
    let store: TabStore
    /// Whether the private stack shows instead of the ordinary one.
    var isPrivateMode = false
    var onModeChange: (Bool) -> Void = { _ in }
    var onOpen: (Tab.ID) -> Void
    /// The + in ordinary mode, and its long press in private mode.
    var onNewTab: () -> Void
    /// The + in private mode, and its long press in ordinary mode: a tab that keeps nothing.
    var onNewPrivateTab: () -> Void = {}
    var onClose: (Tab.ID) -> Void
    var onShowArchive: () -> Void
    /// The page's own sampled colour, for the space below a short page's picture.
    var pageBackground: (Tab.ID) -> Color? = { _ in nil }
    /// Wired to the reading screen's half of the page ↔ card transition.
    var transitionNamespace: Namespace.ID? = nil

    /// The bottom inset, read before the layout goes full-bleed: a GeometryReader
    /// swallows the safe area for everything inside it, so it cannot be read there.
    @State private var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ScreenMetrics {
        /// The bottom row's inset from the sides.
        static let rowInset: CGFloat = 16
        /// The switch's width and its gap under the status bar.
        static let switchWidth: CGFloat = 220
        static let switchTop: CGFloat = 8
        /// The empty private card's widest and its inner margins.
        static let cardWidth: CGFloat = 320
        static let cardPadding: CGFloat = 24
        static let cardRadius: CGFloat = 28
        static let cardInset: CGFloat = 24
    }

    private var tabs: [Tab] { store.tabs(inPrivate: isPrivateMode) }

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground(night: isPrivateMode)
                .ignoresSafeArea()
            if tabs.isEmpty && isPrivateMode {
                emptyPrivate
                    .transition(.opacity)
            } else {
                stack
                    .transition(.opacity)
            }
            modeSwitch
                .padding(.top, ScreenMetrics.switchTop)
                .frame(maxHeight: .infinity, alignment: .top)
            bottomRow
                .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(edges: .bottom)
        // Private mode is dark whatever the system is, so the glass and the type over the
        // night mist read as they do in the dark appearance.
        .preferredColorScheme(isPrivateMode ? .dark : nil)
    }

    /// Tabs | Private: one tap either way, always on screen.
    private var modeSwitch: some View {
        SegmentedControl(
            options: [String(localized: "Tabs"), String(localized: "Private")],
            symbols: [nil, "eye.slash"],
            identifiers: ["tabs.mode.normal", "tabs.mode.private"],
            selection: Binding(
                get: { isPrivateMode ? 1 : 0 },
                set: { index in
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
                        onModeChange(index == 1)
                    }
                }
            )
        )
        .frame(width: ScreenMetrics.switchWidth)
    }

    /// The private stack with nothing in it: what private tabs are, and a way to start one.
    private var emptyPrivate: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Palette.onNightInk)
                .accessibilityHidden(true)
            Text(String(localized: "Private tabs"))
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.onNightInk)
                .accessibilityAddTraits(.isHeader)
            Text(
                String(
                    localized:
                        "Nothing here is saved. Closing the last private tab clears its cookies and history.")
            )
            .font(Typography.meta)
            .foregroundStyle(Palette.onNightInk.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            PrimaryCTA(title: String(localized: "New private tab"), action: onNewPrivateTab)
                .accessibilityIdentifier("tabs.private.new")
                .padding(.top, 8)
        }
        .padding(ScreenMetrics.cardPadding)
        .frame(maxWidth: ScreenMetrics.cardWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: ScreenMetrics.cardRadius))
        .padding(.horizontal, ScreenMetrics.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabs.private.empty")
    }

    private var stack: some View {
        ZStack {
            GeometryReader { geo in
                TabStack(
                    tabs: tabs,
                    currentID: store.currentTabID(inPrivate: isPrivateMode),
                    onSelect: { store.select($0) },
                    onOpen: onOpen,
                    onClose: onClose,
                    snapshotLoader: { await store.loadSnapshot(for: $0) },
                    pageBackground: pageBackground,
                    namespace: transitionNamespace
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tabs.stack")
            }
        }
    }

    private var bottomRow: some View {
        HStack {
            ArchivedChip(count: store.archivedTabs.count, action: onShowArchive)
                .accessibilityIdentifier("tabs.archive")
            Spacer()
            Text(TabsCopy.openCount(tabs.count))
                .font(Typography.small)
                .foregroundStyle(Palette.labelOnMist)
                .accessibilityIdentifier("tabs.openCount")
            Spacer()
            // The + follows the mode; the long press offers the other kind.
            PlusButton(action: isPrivateMode ? onNewPrivateTab : onNewTab)
                .contextMenu {
                    Button(action: isPrivateMode ? onNewTab : onNewPrivateTab) {
                        if isPrivateMode {
                            Label(String(localized: "New tab"), systemImage: "plus")
                        } else {
                            Label(String(localized: "New private tab"), systemImage: "eye.slash")
                        }
                    }
                }
                .accessibilityAction(
                    named: Text(
                        isPrivateMode
                            ? String(localized: "New tab") : String(localized: "New private tab")),
                    isPrivateMode ? onNewTab : onNewPrivateTab
                )
                .accessibilityIdentifier("tabs.plus")
        }
        .padding(.horizontal, ScreenMetrics.rowInset)
    }
}
