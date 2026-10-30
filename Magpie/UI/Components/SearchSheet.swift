import SwiftUI

/// The launch and in-page search sheet: the field, up to three suggestion rows, and the
/// keyboard, reading as one piece.
///
/// On the mist it is glass; opened from a page it is solid `sheetSolid`. The field is focused
/// with the keyboard up on arrival, rows stagger in 30 ms apart, and a swipe down or a tap
/// away dismisses.
struct SearchSheet: View {

    /// Layout numbers from the search-sheet spec.
    private enum Layout {
        static let topPadding: CGFloat = 14
        static let rowListInset: CGFloat = 6
        static let rowListBottomPadding: CGFloat = 8
        static let rowLimit = 3
        /// Rows arrive this far apart, top to bottom.
        static let rowStagger: Duration = .milliseconds(30)
        /// The field fades in this long after the sheet does.
        static let fieldDelay: TimeInterval = 0.05
        /// How far down a drag must reach before it counts as a dismissal.
        static let dismissDistance: CGFloat = 120
        /// Or how hard it has to be flung.
        static let dismissFling: CGFloat = 240
    }

    let engine: SearchEngine
    let opensFromPage: Bool
    let skimEnabled: Bool
    let suggestionsEnabled: Bool
    let morphNamespace: Namespace.ID?
    let suggestions: any SuggestionProviding
    let recents: any RecentSearchStoring
    let onOpen: (URL) -> Void
    let onSkim: (String) -> Void
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var rows: [String] = []
    @State private var visibleRows = 0
    @State private var fieldArrived = false
    @State private var dragOffset: CGFloat = 0
    @FocusState private var focused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        engine: SearchEngine = .default,
        opensFromPage: Bool = false,
        skimEnabled: Bool = true,
        suggestionsEnabled: Bool = true,
        initialText: String = "",
        morphNamespace: Namespace.ID? = nil,
        suggestions: any SuggestionProviding = SuggestionService(),
        recents: any RecentSearchStoring = RecentSearches(),
        onOpen: @escaping (URL) -> Void,
        onSkim: @escaping (String) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.opensFromPage = opensFromPage
        self.skimEnabled = skimEnabled
        self.suggestionsEnabled = suggestionsEnabled
        self.morphNamespace = morphNamespace
        self.suggestions = suggestions
        self.recents = recents
        self.onOpen = onOpen
        self.onSkim = onSkim
        self.onDismiss = onDismiss
        _text = State(initialValue: initialText)
    }

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
        .task(id: text) {
            await reloadRows()
        }
    }

    /// Everything above the sheet. On the mist it is clear; over a page it is the scrim.
    private var tapAway: some View {
        Rectangle()
            .fill(opensFromPage ? AnyShapeStyle(Palette.scrim) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }

    @ViewBuilder
    private var sheetBody: some View {
        if opensFromPage {
            sheetContent
                .background(sheetShape.fill(Palette.sheetSolid))
        } else {
            sheetContent
                .glassEffect(.regular, in: sheetShape)
                .modifier(MorphTag(namespace: morphNamespace))
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $text,
                engineName: engine.displayName,
                focus: $focused,
                onSubmit: { submit(text) }
            )
            .padding(.horizontal, Metrics.Spacing.insetFloating)
            .padding(.top, Layout.topPadding)
            .opacity(fieldArrived ? 1 : 0)
            rowList
                .padding(.horizontal, Layout.rowListInset)
                .padding(.top, Layout.rowListInset)
                .padding(.bottom, Layout.rowListBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .offset(y: dragOffset)
        .gesture(dismissDrag)
        .onAppear {
            focused = true
            arrive()
        }
    }

    @ViewBuilder
    private var rowList: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    if index < visibleRows {
                        SuggestionRow(
                            text: row,
                            skimState: SkimPill.State.resolve(skimEnabled: skimEnabled, primed: index == 0),
                            onSearch: { submit(row) },
                            onSkim: { skim(row) }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity))
                    }
                }
            }
        }
    }

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

    // MARK: Behaviour

    /// The field fades in just after the sheet; suggestions then stagger beneath it.
    private func arrive() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                fieldArrived = true
            }
            return
        }
        withAnimation(.easeOut(duration: 0.2).delay(Layout.fieldDelay)) {
            fieldArrived = true
        }
    }

    /// Loads the rows for the field's current text: recent searches while it is empty,
    /// engine suggestions once there is something to ask about.
    private func reloadRows() async {
        let query = text
        let loaded: [String]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loaded = await recents.recent(limit: Layout.rowLimit)
        } else {
            loaded = await suggestions.suggestions(
                for: query, engine: engine, enabled: suggestionsEnabled)
        }
        guard !Task.isCancelled else { return }
        if loaded == rows {
            visibleRows = rows.count
            return
        }
        rows = loaded
        await revealRows()
    }

    /// Reveals the loaded rows one apart, top to bottom; all at once under Reduce Motion.
    private func revealRows() async {
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) {
                visibleRows = rows.count
            }
            return
        }
        visibleRows = 0
        for index in rows.indices {
            guard !Task.isCancelled else { return }
            withAnimation(Springs.chrome.animation) {
                visibleRows = index + 1
            }
            guard index < rows.count - 1 else { break }
            do {
                try await Task.sleep(for: Layout.rowStagger)
            } catch {
                return
            }
        }
    }

    /// A query goes to the engine; a URL goes to the site.
    private func submit(_ raw: String) {
        guard let resolution = QueryResolver.resolve(raw, engine: engine) else { return }
        switch resolution {
        case .url(let url):
            onOpen(url)
        case .search(let query):
            guard let url = engine.searchURL(for: query) else { return }
            record(query)
            onOpen(url)
        }
    }

    private func skim(_ query: String) {
        record(query)
        onSkim(query)
    }

    private func record(_ query: String) {
        let store = recents
        Task {
            await store.record(query)
        }
    }
}

/// Tags the sheet's glass surface so the reading bar can morph into it later.
private struct MorphTag: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.glassEffectID("searchSheet", in: namespace)
        } else {
            content
        }
    }
}

/// A suggestion source with fixed rows, for previews and tests.
struct StubSuggestionProvider: SuggestionProviding {
    var rowsByPrefix: [String]

    func suggestions(for query: String, engine: SearchEngine, enabled: Bool) async -> [String] {
        guard enabled else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return rowsByPrefix.filter { $0.lowercased().hasPrefix(trimmed.lowercased()) }.prefix(3).map { $0 }
    }
}

#Preview("On the mist") {
    ZStack {
        MistBackground()
        SearchSheet(
            engine: .default,
            suggestions: StubSuggestionProvider(
                rowsByPrefix: [
                    "seasoning carbon steel", "seasoning cast iron", "carbon steel vs cast iron",
                    "carbon steel pan care",
                ]),
            onOpen: { _ in })
    }
    .ignoresSafeArea()
}

#Preview("Opened from a page") {
    ZStack {
        Rectangle().fill(Palette.card)
        SearchSheet(
            engine: .default,
            opensFromPage: true,
            suggestions: StubSuggestionProvider(
                rowsByPrefix: ["seasoning carbon steel", "seasoning cast iron", "carbon steel vs cast iron"]),
            onOpen: { _ in })
    }
    .ignoresSafeArea()
}
