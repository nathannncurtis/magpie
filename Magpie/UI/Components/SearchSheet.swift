import SwiftUI
import UIKit

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
    /// True while a full screen covers the sheet (Settings, onboarding): the field gives
    /// up focus — keyboard away — and takes it back when the cover goes.
    var focusSuspended: Bool = false
    let morphNamespace: Namespace.ID?
    let suggestions: any SuggestionProviding
    let recents: any RecentSearchStoring
    let onOpen: (URL) -> Void
    let onSkim: (String) -> Void
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var rows: [String] = []
    @State private var rowsAreRecents = false
    @State private var visibleRows = 0
    @State private var fieldArrived = false
    @State private var fillSettled = false
    @State private var dragOffset: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @FocusState private var focused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        engine: SearchEngine = .default,
        opensFromPage: Bool = false,
        skimEnabled: Bool = true,
        suggestionsEnabled: Bool = true,
        focusSuspended: Bool = false,
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
        self.focusSuspended = focusSuspended
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
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background {
            // Over a page, the whole page dims evenly, edge to edge behind the sheet; the
            // dim arrives with the solid fill as the bar grows into the sheet.
            if opensFromPage {
                Rectangle()
                    .fill(Palette.scrim)
                    .ignoresSafeArea()
                    .opacity(fillSettled ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.bottom
        } action: { inset in
            bottomInset = inset
        }
        .task(id: text) {
            await reloadRows()
        }
    }

    /// The area above the sheet: a tap there folds the sheet away.
    private var tapAway: some View {
        Color.clear
            .ignoresSafeArea(edges: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityIdentifier("search.scrim")
    }

    /// The sheet hugs its content and rides the keyboard: the tail is exactly the keyboard's
    /// height (the home indicator's once it is away), so the rows sit on the keys and the
    /// surface runs on behind them to the bottom edge.
    @ViewBuilder
    private var sheetBody: some View {
        VStack(spacing: 0) {
            sheetContent
            Color.clear
                .frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .modifier(
            SheetSurface(
                opensFromPage: opensFromPage,
                shape: sheetShape,
                namespace: morphNamespace,
                fillSettled: fillSettled)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.sheet")
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
            // Under onboarding the sheet arrives already covered; the field waits.
            if !focusSuspended { focused = true }
            arrive()
            selectCarriedText()
        }
    }

    /// The address a page's sheet opens with arrives selected (04 · 02), so typing replaces
    /// it outright.
    private func selectCarriedText() {
        guard !text.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            UIApplication.shared.sendAction(
                #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        .onChange(of: focusSuspended) { _, suspended in
            focused = !suspended
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
                            skimState: rowSkimState(at: index),
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

    /// Only live suggestions carry the Skim pill; recent searches are the past, not a skim
    /// waiting to happen.
    private func rowSkimState(at index: Int) -> SkimPill.State {
        guard !rowsAreRecents else { return .hidden }
        return SkimPill.State.resolve(skimEnabled: skimEnabled, primed: index == 0)
    }

    /// The field fades in just after the sheet; over a page the solid fill settles behind
    /// it, so the sheet is glass while it grows from the bar and solid once it is there.
    private func arrive() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                fieldArrived = true
                fillSettled = true
            }
            return
        }
        withAnimation(Springs.chrome.animation) {
            fillSettled = true
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
            rowsAreRecents = true
        } else {
            loaded = await suggestions.suggestions(
                for: query, engine: engine, enabled: suggestionsEnabled)
            rowsAreRecents = false
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

/// The sheet's surface: glass, which the reading bar grows into; solid once it has settled
/// over a page.
private struct SheetSurface: ViewModifier {
    let opensFromPage: Bool
    let shape: UnevenRoundedRectangle
    let namespace: Namespace.ID?
    let fillSettled: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Palette.sheetSolid).opacity(opensFromPage && fillSettled ? 1 : 0))
            .glassEffect(.regular, in: shape)
            .modifier(MorphTag(namespace: namespace))
    }
}

/// Tags the sheet's glass surface as the chrome shape, so the bar and the sheet are one
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
