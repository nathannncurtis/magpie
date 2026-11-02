import SwiftUI

/// The bookmarks: folders, then the recently added pages, as rows on the mist. Edit
/// brings the folder tools — new, rename, reorder, delete — and the pill at the foot
/// searches titles and addresses.
struct BookmarksScreen: View {
    let store: BookmarkStore
    var onOpen: (URL) -> Void
    /// Done, or a swipe back off the top level: whatever was up before the bookmarks.
    var onClose: () -> Void = {}

    @State private var searchText = ""
    @State private var editing = false
    @State private var openFolderID: BookmarkFolder.ID?
    @State private var renamingFolder: BookmarkFolder?
    @State private var renamedText = ""
    @State private var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ScreenMetrics {
        static let listBottomClearance: CGFloat = 100
        /// A folder row's text leading edge: the glyph and the gap after it.
        static let folderSeparatorInset: CGFloat = 28 + 12
    }

    // MARK: Data

    private var searching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleBookmarks: [Bookmark] {
        searching
            ? store.recentlyAdded.filter { BookmarkSearch.matches($0, query: searchText) }
            : store.recentlyAdded
    }

    private var openFolder: BookmarkFolder? {
        store.folders.first { $0.id == openFolderID }
    }

    // MARK: The screen

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground()
                .ignoresSafeArea()
            Group {
                if let folder = openFolder {
                    folderDetail(folder)
                        .transition(pushTransition)
                } else {
                    mainContent
                        .transition(popTransition)
                }
            }
            .readableWidth()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? Springs.smooth : Springs.chrome.animation, value: openFolderID)
            emptyBlock
                .padding(.bottom, bottomInset)
                .transition(.opacity)
                .animation(reduceMotion ? Springs.smooth : Springs.chrome.animation, value: openFolderID)
            if pillWanted {
                BottomSearchPill(
                    placeholder: String(localized: "Search bookmarks"),
                    text: $searchText
                )
                .padding(.horizontal, Metrics.Spacing.insetFloating)
                .readableWidth()
                .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
                // The pill runs on behind the keys; the padding above, read off the safe
                // area, is what lifts it onto them.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bookmarks.search")
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        // Out of a folder first, then off the bookmarks.
        .backSwipe {
            if openFolderID != nil { openFolderID = nil } else { onClose() }
        }
    }

    /// No pill when there is nothing to search, and none over a folder's own list.
    private var pillWanted: Bool {
        openFolder == nil && !store.bookmarks.isEmpty
    }

    /// The quiet block over the screen: no bookmarks at all, an empty folder, or a
    /// search that matches nothing. It lays over the whole screen so its share of the
    /// height is the screen's, not the leftover under the header; the padding holds
    /// the layer to the safe height, the screen's bottom being full-bleed for the pill.
    @ViewBuilder
    private var emptyBlock: some View {
        if let folder = openFolder {
            if store.bookmarks(inFolder: folder.id).isEmpty {
                // COPY: review — drafted, not on the boards.
                EmptyListState(
                    icon: "bookmark",
                    title: String(localized: "Nothing in this folder"),
                    message: String(localized: "Bookmarks you move here will show up in this list.")
                )
                .accessibilityIdentifier("bookmarks.folder.empty")
            }
        } else if store.bookmarks.isEmpty && store.folders.isEmpty {
            // COPY: review — drafted, not on the boards.
            EmptyListState(
                icon: "bookmark",
                title: String(localized: "No bookmarks yet"),
                message: String(localized: "Tap Bookmark in the menu to keep a page here.")
            )
            .accessibilityIdentifier("bookmarks.empty")
        } else if searching && visibleBookmarks.isEmpty {
            noResults
        }
    }

    /// What a search shows when it matches nothing: the pill stays, to take the query back.
    private var noResults: some View {
        EmptyListState(
            icon: "magnifyingglass",
            title: String(localized: "No results"),
            message: String(localized: "No bookmarks match that search.")
        )
        .accessibilityIdentifier("bookmarks.results.empty")
    }

    private var pushTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .opacity)
    }

    private var popTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .leading), removal: .opacity)
    }

    // MARK: The main list

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: String(localized: "Bookmarks"), titleID: "bookmarks.title",
                leading: { editButton },
                trailing: { HeaderDoneButton(id: "bookmarks.done", action: onClose) })
            if listShown {
                list
            }
        }
        .alert(
            String(localized: "Rename folder"),
            isPresented: Binding(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } })
        ) {
            TextField(String(localized: "Folder name"), text: $renamedText)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Save")) {
                if let folder = renamingFolder {
                    store.renameFolder(folder.id, to: renamedText)
                }
            }
        }
    }

    /// The list stands in only when something fills it; the quiet block lays over the
    /// screen when nothing does.
    private var listShown: Bool {
        !(store.bookmarks.isEmpty && store.folders.isEmpty)
            && !(searching && visibleBookmarks.isEmpty)
    }

    private var list: some View {
        List {
            if !searching {
                folderRows
            }
            bookmarkRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, ScreenMetrics.listBottomClearance, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookmarks.list")
    }

    @ViewBuilder
    private var folderRows: some View {
        if !store.folders.isEmpty || editing {
            SectionLabel(title: String(localized: "Folders"))
                .listRow()
        }
        if editing {
            newFolderRow
                .listRow()
        }
        ForEach(Array(store.folders.enumerated()), id: \.element.id) { index, folder in
            FolderRow(
                name: folder.name,
                count: store.count(inFolder: folder.id)
            )
            .padding(.horizontal, Metrics.Spacing.insetList)
            .overlay(alignment: .top) {
                separator(visible: index > 0)
            }
            .rowPress { folderTapped(folder) }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("bookmarks.folder.\(folder.name)")
            .listRow()
            .deleteDisabled(!editing)
        }
        .onMove { offsets, destination in
            store.moveFolders(fromOffsets: offsets, toOffset: destination)
        }
        .onDelete { offsets in
            let folders = store.folders
            for index in offsets where folders.indices.contains(index) {
                store.removeFolder(folders[index].id)
            }
        }
    }

    @ViewBuilder
    private var bookmarkRows: some View {
        SectionLabel(
            title: searching ? String(localized: "Results") : String(localized: "Recently added")
        )
        .listRow()
        ForEach(Array(visibleBookmarks.enumerated()), id: \.element.id) { index, bookmark in
            BookmarkRow(
                bookmark: bookmark,
                folderName: folderName(of: bookmark),
                showsSeparator: index > 0,
                onOpen: { onOpen(bookmark.url) }
            )
            .listRow()
            .moveDisabled(true)
            .deleteDisabled(editing)
        }
        .onDelete { offsets in
            let bookmarks = visibleBookmarks
            for index in offsets where bookmarks.indices.contains(index) {
                store.remove(bookmarks[index].id)
            }
        }
    }

    /// "New folder", at the head of the folders while editing.
    private var newFolderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(Typography.icon(.small))
                .foregroundStyle(Palette.teal)
            Text(String(localized: "New folder"))
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Metrics.Spacing.insetList)
        .frame(minHeight: Metrics.tapTarget)
        .rowPress { store.addDefaultFolder() }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bookmarks.newFolder")
    }

    private func folderTapped(_ folder: BookmarkFolder) {
        if editing {
            renamedText = folder.name
            renamingFolder = folder
        } else {
            openFolderID = folder.id
        }
    }

    // MARK: A folder's list

    private func folderDetail(_ folder: BookmarkFolder) -> some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: folder.name, titleID: "bookmarks.folder.title",
                leading: { HeaderBackButton(id: "bookmarks.folder.back") { openFolderID = nil } },
                trailing: { HeaderDoneButton(id: "bookmarks.done", action: onClose) })
            let bookmarks = store.bookmarks(inFolder: folder.id)
            if !bookmarks.isEmpty {
                List {
                    ForEach(Array(bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        BookmarkRow(
                            bookmark: bookmark,
                            folderName: nil,
                            showsSeparator: index > 0,
                            onOpen: { onOpen(bookmark.url) }
                        )
                        .listRow()
                    }
                    .onDelete { offsets in
                        for index in offsets where bookmarks.indices.contains(index) {
                            store.remove(bookmarks[index].id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(
                    .bottom, ScreenMetrics.listBottomClearance, for: .scrollContent
                )
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bookmarks.folder.list")
            }
        }
    }

    // MARK: Chrome

    /// Edit at the top left; while editing it reads Save, so it never shares a name with
    /// the Done that leaves the screen.
    private var editButton: some View {
        HeaderTextButton(
            title: editing ? String(localized: "Save") : String(localized: "Edit"),
            edge: .leading, id: "bookmarks.edit"
        ) {
            withAnimation(reduceMotion ? Springs.smooth : Springs.settle.animation) {
                editing.toggle()
            }
        }
    }

    private func folderName(of bookmark: Bookmark) -> String? {
        bookmark.folderID.flatMap { id in store.folders.first { $0.id == id }?.name }
    }

    private func separator(visible: Bool) -> some View {
        Group {
            if visible {
                RowSeparator(inset: ScreenMetrics.folderSeparatorInset)
            }
        }
    }
}

/// The plain-list row dressing these lists share: no background, no separators of their
/// own, no insets.
private extension View {
    func listRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// One bookmark as a row: a plain page or a Skim page, each in the list's shape.
private struct BookmarkRow: View {
    let bookmark: Bookmark
    var folderName: String?
    let showsSeparator: Bool
    var onOpen: () -> Void

    var body: some View {
        Group {
            switch bookmark.kind {
            case .page:
                ListRow(
                    title: bookmark.title,
                    subtitle: subtitle,
                    host: bookmark.host,
                    faviconData: bookmark.faviconData
                )
            case .skim(let sourceHosts):
                SkimPageRow(
                    title: bookmark.title,
                    folderName: folderName,
                    sourceHosts: sourceHosts)
            }
        }
        .padding(.horizontal, Metrics.Spacing.insetList)
        .overlay(alignment: .top) {
            if showsSeparator {
                RowSeparator(inset: SeparatorMetrics.inset)
            }
        }
        .rowPress(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bookmarks.row.\(bookmark.title)")
    }

    /// "quietweb.org · Reading", or just the site when the bookmark sits in no folder.
    private var subtitle: String {
        guard let folderName, !folderName.isEmpty else { return bookmark.host ?? "" }
        return "\(bookmark.host ?? "") · \(folderName)"
    }

    private enum SeparatorMetrics {
        /// The text's leading edge: the favicon or tile, and the gap after it.
        static let inset: CGFloat = 26 + 12
    }
}

#Preview {
    struct BookmarksHost: View {
        @State private var store = BookmarkStore()

        var body: some View {
            BookmarksScreen(store: store, onOpen: { _ in })
                .task {
                    func url(_ address: String) -> URL {
                        URL(string: address) ?? URL(fileURLWithPath: "/")
                    }
                    let kitchen = store.newFolder(name: "Kitchen", tint: .orange)
                    let reading = store.newFolder(name: "Reading", tint: .blue)
                    store.newFolder(name: "Work", tint: .sage)
                    store.add(
                        url: url("https://quietweb.org/slow"),
                        title: "The web, read slowly", folder: reading.id, now: .now - 3_600)
                    store.add(
                        url: url("https://magpie.test/skim/seasoning"),
                        title: "Seasoning carbon steel", folder: kitchen.id,
                        kind: .skim(sourceHosts: ["seriouseats.com", "debuyer.com", "reddit.com"]),
                        now: .now - 1_800)
                    store.add(
                        url: url("https://seriouseats.com/pan-sauce"),
                        title: "Pan sauce, any night", folder: kitchen.id, now: .now - 86_400)
                }
        }
    }
    return BookmarksHost()
}
