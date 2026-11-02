import SwiftUI

/// The history: visited pages as plain rows on the mist, grouped by day. Tapping a row
/// opens the page in a new tab; a swipe removes it; the pill at the foot searches titles
/// and sites; "Clear history…" ends the list.
struct HistoryScreen: View {
    let store: HistoryStore
    var onOpen: (URL) -> Void
    var onDone: () -> Void

    @State private var searchText = ""
    @State private var bottomInset: CGFloat = 0
    @State private var confirmsClear = false
    /// The delete just made, on offer for an undo.
    @State private var undo: UndoNotice?

    private enum ScreenMetrics {
        static let listBottomClearance: CGFloat = 100
        static let clearHeight: CGFloat = 52
    }

    private var now: Date { Date() }
    private var calendar: Calendar { .current }

    private var searching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visible: [HistoryEntry] {
        store.search(searchText)
    }

    private var groups: [(title: String, items: [HistoryEntry])] {
        ArchiveGrouping.bands(of: visible, date: \.visitedAt, now: now, calendar: calendar)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HistoryHeader(onDone: onDone)
                if !visible.isEmpty {
                    list
                }
            }
            .readableWidth()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            emptyBlock
                .padding(.bottom, bottomInset)
            if !store.entries.isEmpty {
                BottomSearchPill(
                    placeholder: String(localized: "Search history"),
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
                .accessibilityIdentifier("history.search")
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .undoNotice(
            $undo, bottomInset: bottomInset,
            lift: store.entries.isEmpty ? 0 : UndoNoticeMetrics.abovePill
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .confirmationDialog(
            String(localized: "Clear all history?"),
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear history"), role: .destructive) {
                store.clear()
            }
            .accessibilityIdentifier("history.clear.confirm")
        } message: {
            Text(String(localized: "Pages you've visited are removed from this list."))
        }
    }

    /// The quiet block over the screen: nothing visited, or a search that matches
    /// nothing. It lays over the whole screen so its share of the height is the
    /// screen's, not the leftover under the header.
    @ViewBuilder
    private var emptyBlock: some View {
        if store.entries.isEmpty {
            // COPY: review — drafted, not on the boards.
            EmptyListState(
                icon: "clock",
                title: String(localized: "No history yet"),
                message: String(localized: "Pages you visit show up here.")
            )
            .accessibilityIdentifier("history.empty")
        } else if visible.isEmpty {
            EmptyListState(
                icon: "magnifyingglass",
                title: String(localized: "No results"),
                message: String(localized: "Nothing in your history matches that search.")
            )
            .accessibilityIdentifier("history.results.empty")
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                SectionLabel(title: group.title)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                    HistoryRow(
                        entry: entry,
                        time: ArchiveGrouping.rowTime(
                            of: entry.visitedAt, now: now, calendar: calendar),
                        showsSeparator: index > 0,
                        onOpen: { onOpen(entry.url) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    let items = group.items
                    let removed = store.remove(
                        offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil })
                    if !removed.isEmpty {
                        undo = .deleted { store.reinstate(removed) }
                    }
                }
            }
            if !searching {
                clearButton
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, ScreenMetrics.listBottomClearance, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.list")
    }

    /// The foot of the list. Hidden while a search narrows it, so it never reads as
    /// clearing only what matched.
    private var clearButton: some View {
        Button {
            confirmsClear = true
        } label: {
            Text(String(localized: "Clear history…"))
                .font(Typography.row)
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, minHeight: ScreenMetrics.clearHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, Metrics.Spacing.gapSectionTop)
        .accessibilityIdentifier("history.clear")
    }
}

/// The history's head: the nav row with Done at the top right, then the title. Kept in
/// one place so the shared screen header can replace it whole.
private struct HistoryHeader: View {
    var onDone: () -> Void

    private enum HeaderMetrics {
        /// The nav row at the head of the screen.
        static let navHeight: CGFloat = 36
        static let navLeading: CGFloat = 16
        static let navTrailing: CGFloat = 18
        static let titleTop: CGFloat = 2
        static let titleBottom: CGFloat = 10
        /// The least a control measures, so a tap never lands on less.
        static let tapTarget: CGFloat = 44
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text(String(localized: "Done"))
                        .frame(
                            minWidth: HeaderMetrics.tapTarget,
                            minHeight: HeaderMetrics.tapTarget,
                            alignment: .trailing
                        )
                        .contentShape(.rect)
                }
                .font(Typography.buttonPill)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("history.done")
            }
            .padding(.leading, HeaderMetrics.navLeading)
            .padding(.trailing, HeaderMetrics.navTrailing)
            .frame(minHeight: HeaderMetrics.navHeight)
            Text(String(localized: "History"))
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.Spacing.insetList)
                .padding(.top, HeaderMetrics.titleTop)
                .padding(.bottom, HeaderMetrics.titleBottom)
                .accessibilityIdentifier("history.title")
        }
    }
}

/// One visited page as a row: favicon tile, title, site, time.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let time: String
    let showsSeparator: Bool
    var onOpen: () -> Void

    var body: some View {
        ListRow(
            title: entry.displayTitle,
            subtitle: entry.host ?? "",
            host: entry.host,
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
        .rowPress(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("history.row.\(entry.displayTitle)")
    }

    private enum SeparatorMetrics {
        /// The text's leading edge: the favicon and the gap after it.
        static let inset: CGFloat = 26 + 12
    }
}

#Preview {
    struct HistoryHost: View {
        @State private var store = HistoryStore()

        var body: some View {
            HistoryScreen(store: store, onOpen: { _ in }, onDone: {})
                .task {
                    let now = Date.now
                    for (address, title, ago) in [
                        ("https://quietweb.org/slow", "The web, read slowly", 600.0),
                        ("https://git-scm.com/rebase", "rebase vs merge · git docs", 4_000.0),
                        ("https://seriouseats.com/carbon-steel", "How to season a carbon steel pan", 90_000.0),
                    ] {
                        if let url = URL(string: address) {
                            store.record(url: url, title: title, isPrivate: false, now: now - ago)
                        }
                    }
                }
        }
    }
    return HistoryHost()
}
