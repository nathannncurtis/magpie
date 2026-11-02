import SwiftUI

/// The archive: untouched tabs as plain rows on the mist, grouped by day. Tapping a row
/// brings its tab back; a swipe deletes it; the pill at the foot searches titles and
/// addresses.
struct ArchiveScreen: View {
    let store: TabStore
    var onRestore: (Tab.ID) -> Void
    var onDone: () -> Void

    @State private var searchText = ""
    @State private var bottomInset: CGFloat = 0
    /// The delete just made, on offer for an undo.
    @State private var undo: UndoNotice?

    private enum ScreenMetrics {
        /// How the list's last rows keep clear of the search pill.
        static let listBottomClearance: CGFloat = 100
    }

    private var now: Date { Date() }
    private var calendar: Calendar { .current }

    private var archived: [Tab] {
        store.archivedTabs.filter { ArchiveSearch.matches($0, query: searchText) }
    }

    private var groups: [ArchiveGrouping.Group] {
        ArchiveGrouping.groups(of: archived, now: now, calendar: calendar)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(
                    title: String(localized: "Archive"), titleID: "archive.title",
                    trailing: { HeaderDoneButton(id: "archive.done", action: onDone) })
                if !store.archivedTabs.isEmpty && !archived.isEmpty {
                    list
                }
            }
            .readableWidth()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            emptyBlock
                .padding(.bottom, bottomInset)
            if !store.archivedTabs.isEmpty {
                BottomSearchPill(
                    placeholder: String(localized: "Search archived tabs"),
                    text: $searchText
                )
                .padding(.horizontal, Metrics.Spacing.insetFloating)
                .readableWidth()
                .padding(
                    .bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset)
                )
                // The pill runs on behind the keys; the padding above, read off the safe
                // area, is what lifts it onto them.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("archive.search")
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .undoNotice(
            $undo, bottomInset: bottomInset,
            lift: store.archivedTabs.isEmpty ? 0 : UndoNoticeMetrics.abovePill
        )
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// The quiet block over the screen: nothing archived, or a search that matches
    /// nothing. It lays over the whole screen so its share of the height is the
    /// screen's, not the leftover under the header; the padding holds the layer to
    /// the safe height, the screen's bottom being full-bleed for the pill.
    @ViewBuilder
    private var emptyBlock: some View {
        if store.archivedTabs.isEmpty {
            EmptyListState(
                icon: "archivebox",
                title: String(localized: "Nothing archived yet"),
                message: String(
                    localized: "Tabs you leave alone for a day land here, and stay for 30 days.")
            )
            .accessibilityIdentifier("archive.empty")
        } else if archived.isEmpty {
            noResults
        }
    }

    /// What a search shows when it matches nothing: the pill stays, to take the query back.
    private var noResults: some View {
        EmptyListState(
            icon: "magnifyingglass",
            title: String(localized: "No results"),
            message: String(localized: "Nothing in the archive matches that search.")
        )
        .accessibilityIdentifier("archive.results.empty")
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                SectionLabel(title: group.title)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Array(group.tabs.enumerated()), id: \.element.id) { index, tab in
                    ArchiveRow(
                        tab: tab,
                        time: ArchiveGrouping.rowTime(of: tab, now: now, calendar: calendar),
                        showsSeparator: index > 0,
                        onRestore: { onRestore(tab.id) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    let tabs = group.tabs
                    let removed = store.deleteArchived(
                        offsets.compactMap { tabs.indices.contains($0) ? tabs[$0].id : nil })
                    if !removed.isEmpty {
                        undo = .deleted { store.reinstateArchived(removed) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, ScreenMetrics.listBottomClearance, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive.list")
    }
}

/// One archived tab as a row: favicon, title, site, time.
private struct ArchiveRow: View {
    let tab: Tab
    let time: String
    let showsSeparator: Bool
    var onRestore: () -> Void

    var body: some View {
        ListRow(
            title: tab.displayTitle,
            subtitle: tab.host ?? "",
            host: tab.host,
            faviconData: tab.faviconData,
            time: time
        )
        .padding(.horizontal, Metrics.Spacing.insetList)
        .overlay(alignment: .top) {
            if showsSeparator {
                RowSeparator(inset: SeparatorMetrics.inset)
            }
        }
        .rowPress(perform: onRestore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("archive.row.\(tab.title)")
    }

    private enum SeparatorMetrics {
        /// The text's leading edge: the favicon and the gap after it.
        static let inset: CGFloat = 26 + 12
    }
}

#Preview {
    struct ArchiveHost: View {
        @State private var store = TabStore()

        var body: some View {
            ArchiveScreen(
                store: store,
                onRestore: { _ in },
                onDone: {}
            )
            .task {
                store.newTab(
                    url: URL(string: "https://seriouseats.com/carbon-steel"),
                    title: "How to season a carbon steel pan", now: Date.now - 43_200)
                store.newTab(
                    url: URL(string: "https://quietweb.org/slow"),
                    title: "The web, read slowly", now: Date.now - 43_800)
                store.newTab(
                    url: URL(string: "https://git-scm.com/rebase"),
                    title: "rebase vs merge · git docs", now: Date.now)
                store.archiveStale(now: .now, after: 0)
            }
        }
    }
    return ArchiveHost()
}
