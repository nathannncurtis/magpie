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

    private enum ScreenMetrics {
        /// The nav row at the head of the screen.
        static let navHeight: CGFloat = 36
        static let navLeading: CGFloat = 16
        static let navTrailing: CGFloat = 18
        static let titleTop: CGFloat = 2
        static let titleBottom: CGFloat = 10
        /// How the list's last rows keep clear of the search pill.
        static let listBottomClearance: CGFloat = 100
        /// The least a control measures, so a tap never lands on less.
        static let tapTarget: CGFloat = 44
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
                navRow
                Text(String(localized: "Archive"))
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.Spacing.insetList)
                    .padding(.top, ScreenMetrics.titleTop)
                    .padding(.bottom, ScreenMetrics.titleBottom)
                    .accessibilityIdentifier("archive.title")
                if !store.archivedTabs.isEmpty && !archived.isEmpty {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            emptyBlock
                .padding(.bottom, bottomInset)
            if !store.archivedTabs.isEmpty {
                BottomSearchPill(
                    placeholder: String(localized: "Search archived tabs"),
                    text: $searchText
                )
                .padding(.horizontal, Metrics.Spacing.insetFloating)
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

    private var navRow: some View {
        HStack {
            Spacer()
            Button(action: onDone) {
                Text(String(localized: "Done"))
                    .frame(
                        minWidth: ScreenMetrics.tapTarget,
                        minHeight: ScreenMetrics.tapTarget,
                        alignment: .trailing
                    )
                    .contentShape(.rect)
            }
            .font(Typography.buttonPill)
            .foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("archive.done")
        }
        .padding(.leading, ScreenMetrics.navLeading)
        .padding(.trailing, ScreenMetrics.navTrailing)
        .frame(minHeight: ScreenMetrics.navHeight)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                DayHeader(title: group.title)
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
                    store.deleteArchived(
                        offsets.compactMap { tabs.indices.contains($0) ? tabs[$0].id : nil })
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
                Rectangle()
                    .fill(Palette.separatorOnMist)
                    .frame(height: 0.5)
                    .padding(.leading, SeparatorMetrics.inset)
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
