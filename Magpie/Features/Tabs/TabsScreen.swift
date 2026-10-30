import SwiftUI

/// The tabs screen: the mist, the stack, and the bottom row.
///
/// Everything sizes from the container, never from the screen, so a wider foldable
/// layout can reuse the screen as it is.
struct TabsScreen: View {
    let store: TabStore
    var onOpen: (Tab.ID) -> Void
    var onNewTab: () -> Void
    var onShowArchive: () -> Void
    /// Wired to the reading screen's half of the page ↔ card transition.
    var transitionNamespace: Namespace.ID? = nil

    private enum ScreenMetrics {
        /// The bottom row's inset from the sides.
        static let rowInset: CGFloat = 16
        /// Where the row sits above the physical bottom edge.
        static let bottomEdge: CGFloat = 34
        /// Kept above a taller home indicator, the way the bars' 26 pt rule does.
        static let aboveHomeIndicator: CGFloat = 8
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MistBackground()
                TabStack(
                    tabs: store.tabs,
                    currentID: store.currentTabID,
                    onSelect: { store.select($0, now: Date.now) },
                    onOpen: open,
                    onClose: { store.close($0) },
                    snapshotLoader: { await store.loadSnapshot(for: $0) },
                    namespace: transitionNamespace
                )
                .frame(
                    width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                    height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                bottomRow
                    .padding(
                        .bottom,
                        max(
                            ScreenMetrics.bottomEdge,
                            geo.safeAreaInsets.bottom - ScreenMetrics.aboveHomeIndicator))
            }
        }
    }

    /// Opening a card makes its tab current before the reading screen takes over.
    private func open(_ id: Tab.ID) {
        store.select(id, now: Date.now)
        onOpen(id)
    }

    private var bottomRow: some View {
        HStack {
            ArchivedChip(count: store.archivedTabs.count, action: onShowArchive)
            Spacer()
            Text(TabsCopy.openCount(store.tabs.count))
                .font(Typography.small)
                .foregroundStyle(Palette.labelOnMist)
            Spacer()
            PlusButton(action: onNewTab)
        }
        .padding(.horizontal, ScreenMetrics.rowInset)
    }
}
