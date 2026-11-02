import SwiftUI

/// 01 · Launch: the mist with the search sheet, its field focused with the keyboard up on
/// arrival. Submitting a search or an address opens a new tab on the reading screen. The
/// sheet rises from the bottom (05 · Launch); a swipe down or a tap away goes back to the
/// stack when there are tabs to return to. With none, it folds away into the mist instead:
/// the mark, and a bottom row (Archived, +, Settings) that always leads somewhere.
struct LaunchScreen: View {
    let engine: SearchEngine
    /// Whether the search sheet shows its Skim pill.
    var skimEnabled: Bool = true
    var suggestionsEnabled: Bool = true
    /// While a full screen (Settings, onboarding) covers the launch sheet.
    var focusSuspended: Bool = false
    /// The search opens a private tab: the screen says so above the sheet.
    var isPrivate: Bool = false
    let suggestions: any SuggestionProviding
    let recents: any RecentSearchStoring
    /// The user's hosts and the pasteboard, for the field.
    var addressAssist = AddressAssist()
    /// Text the field opens with: the Skim query bar's edit.
    var initialText: String = ""
    var onSkim: (String) -> Void = { _ in }
    let onOpen: (URL) -> Void
    let onDismiss: () -> Void
    /// Whether there are tabs a dismissal returns to; without them the sheet folds away.
    var hasTabs: Bool = true
    var archivedCount: Int = 0
    var onNewTab: () -> Void = {}
    var onNewPrivateTab: () -> Void = {}
    var onShowArchive: () -> Void = {}
    var onShowSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    /// The sheet folded away with no tabs to go back to: the mist, the mark and the row.
    @State private var folded = false
    @State private var bottomInset: CGFloat = 0

    /// How far up the sheet starts before it rises.
    private static let riseDistance: CGFloat = 160

    private enum Layout {
        static let markSize: CGFloat = 96
    }

    var body: some View {
        ZStack {
            MistBackground(night: isPrivate)
                .ignoresSafeArea()
            if folded {
                foldedContent
                    .transition(.opacity)
            } else {
                SearchSheet(
                    engine: engine,
                    skimEnabled: skimEnabled,
                    suggestionsEnabled: suggestionsEnabled,
                    focusSuspended: focusSuspended,
                    initialText: initialText,
                    suggestions: suggestions,
                    recents: recents,
                    addressAssist: addressAssist,
                    onOpen: onOpen,
                    onSkim: onSkim,
                    onDismiss: dismiss
                )
                .offset(y: arrived ? 0 : Self.riseDistance)
                .transition(.move(edge: .bottom))
            }
            if isPrivate {
                Label(String(localized: "Private tab"), systemImage: "eye.slash")
                    .font(Typography.rowTitle)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityIdentifier("launch.private")
            }
        }
        // A full screen over the launch takes it out of the window, and a rise started
        // there never lands: the sheet rises once nothing covers it.
        .onAppear { if !focusSuspended { rise() } }
        .onChange(of: focusSuspended) { _, suspended in
            if !suspended { rise() }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.screen")
        // A private search is night whatever the system is, like the private stack.
        .preferredColorScheme(isPrivate ? .dark : nil)
    }

    /// With tabs, a dismissal goes back to the stack; without, the sheet folds away here.
    private func dismiss() {
        guard !hasTabs else {
            onDismiss()
            return
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
            folded = true
        }
    }

    /// The sheet back up, its field focused, for a new tab or a private one.
    private func unfold(_ open: () -> Void) {
        open()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
            folded = false
        }
    }

    private var foldedContent: some View {
        ZStack(alignment: .bottom) {
            Mark(size: Layout.markSize, style: .sheen)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            FloatingBar {
                FloatingBarSlots {
                    ArchivedChip(count: archivedCount, action: onShowArchive)
                        .accessibilityIdentifier("launch.archive")
                } centre: {
                    PlusButton(action: { unfold(onNewTab) })
                        .contextMenu {
                            Button(action: { unfold(onNewPrivateTab) }) {
                                Label(String(localized: "New private tab"), systemImage: "eye.slash")
                            }
                        }
                        .accessibilityAction(named: Text(String(localized: "New private tab"))) {
                            unfold(onNewPrivateTab)
                        }
                        .accessibilityIdentifier("launch.plus")
                } trailing: {
                    CircleButton(systemName: "gearshape", action: onShowSettings)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityLabel(Text(String(localized: "Settings")))
                        .accessibilityIdentifier("launch.settings")
                }
            }
            .floatingBarBottomEdge(safeAreaBottom: bottomInset)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func rise() {
        guard !arrived else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
            arrived = true
        }
    }
}
