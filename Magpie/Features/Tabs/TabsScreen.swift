import SwiftUI

/// The tabs screen: the mist, the stack, and the bottom row.
///
/// Everything sizes from the container, never from the screen, so a wider foldable
/// layout can reuse the screen as it is.
struct TabsScreen: View {
    let store: TabStore
    var onOpen: (Tab.ID) -> Void
    var onNewTab: () -> Void
    var onClose: (Tab.ID) -> Void
    var onShowArchive: () -> Void
    /// Wired to the reading screen's half of the page ↔ card transition.
    var transitionNamespace: Namespace.ID? = nil

    /// The bottom inset, read before the layout goes full-bleed: a GeometryReader
    /// swallows the safe area for everything inside it, so it cannot be read there.
    @State private var bottomInset: CGFloat = 0

    private enum ScreenMetrics {
        /// The bottom row's inset from the sides.
        static let rowInset: CGFloat = 16
        /// Where the row sits above the physical bottom edge.
        static let bottomEdge: CGFloat = 34
        /// Kept above a taller home indicator, the way the bars' 26 pt rule does.
        static let aboveHomeIndicator: CGFloat = 8
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                MistBackground()
                TabStack(
                    tabs: store.tabs,
                    currentID: store.currentTabID,
                    onSelect: { store.select($0) },
                    onOpen: onOpen,
                    onClose: onClose,
                    snapshotLoader: { await store.loadSnapshot(for: $0) },
                    namespace: transitionNamespace
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tabs.stack")
            }
            bottomRow
                .padding(
                    .bottom,
                    max(
                        ScreenMetrics.bottomEdge,
                        bottomInset - ScreenMetrics.aboveHomeIndicator))
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea()
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
                .accessibilityIdentifier("tabs.plus")
        }
        .padding(.horizontal, ScreenMetrics.rowInset)
    }
}
