import SwiftUI

/// The tabs screen: the mist, the stack, and the bottom row.
///
/// Everything sizes from the container, never from the screen, so a wider foldable
/// layout can reuse the screen as it is.
struct TabsScreen: View {
    let store: TabStore
    var onOpen: (Tab.ID) -> Void
    var onNewTab: () -> Void
    /// The + button's long press: a tab that keeps nothing.
    var onNewPrivateTab: () -> Void = {}
    var onClose: (Tab.ID) -> Void
    var onShowArchive: () -> Void
    /// The tab just flung closed, while its undo is on offer.
    var closedNotice: AppModel.ClosedTabNotice? = nil
    var onUndo: () -> Void = {}
    /// The undo ran out (its notice id) or the screen went: the close stands.
    var onNoticeExpired: (AppModel.ClosedTabNotice.ID) -> Void = { _ in }
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
        /// How long the undo stays up.
        static let undoDuration: Duration = .seconds(4)
        /// The undo capsule's gap above the bottom row.
        static let undoLift: CGFloat = 46 + 14
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground()
                .ignoresSafeArea()
            GeometryReader { geo in
                TabStack(
                    tabs: store.tabs,
                    currentID: store.currentTabID,
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
            bottomRow
                .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
            if let closedNotice {
                UndoCapsule {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation) {
                        onUndo()
                    }
                }
                .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset) + ScreenMetrics.undoLift)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                .id(closedNotice.id)
                .task {
                    try? await Task.sleep(for: ScreenMetrics.undoDuration)
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
                        onNoticeExpired(closedNotice.id)
                    }
                }
            }
        }
        .animation(Springs.chrome.animation, value: closedNotice?.id)
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(edges: .bottom)
        .onDisappear {
            if let id = closedNotice?.id { onNoticeExpired(id) }
        }
    }

    private var bottomRow: some View {
        HStack {
            ArchivedChip(count: store.archivedTabs.count, action: onShowArchive)
                .accessibilityIdentifier("tabs.archive")
            Spacer()
            Text(TabsCopy.openCount(store.tabs.count))
                .font(Typography.small)
                .foregroundStyle(Palette.labelOnMist)
                .accessibilityIdentifier("tabs.openCount")
            Spacer()
            PlusButton(action: onNewTab)
                .contextMenu {
                    Button(action: onNewPrivateTab) {
                        Label(String(localized: "New private tab"), systemImage: "eye.slash")
                    }
                }
                .accessibilityAction(named: Text(String(localized: "New private tab")), onNewPrivateTab)
                .accessibilityIdentifier("tabs.plus")
        }
        .padding(.horizontal, ScreenMetrics.rowInset)
    }
}
