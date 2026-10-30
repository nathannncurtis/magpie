import SwiftUI

/// 01 · Launch: the mist with the search sheet, its field focused with the keyboard up on
/// arrival. Submitting a search or an address opens a new tab on the reading screen. The
/// sheet rises from the bottom (05 · Launch); a swipe down or a tap away goes back to the
/// stack when there are tabs to return to.
struct LaunchScreen: View {
    let engine: SearchEngine
    /// Whether the search sheet shows its Skim pill.
    var skimEnabled: Bool = true
    var suggestionsEnabled: Bool = true
    /// While a full screen (Settings, onboarding) covers the launch sheet.
    var focusSuspended: Bool = false
    let suggestions: any SuggestionProviding
    let recents: any RecentSearchStoring
    /// Text the field opens with: the Skim query bar's edit.
    var initialText: String = ""
    var onSkim: (String) -> Void = { _ in }
    let onOpen: (URL) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    /// How far up the sheet starts before it rises.
    private static let riseDistance: CGFloat = 160

    var body: some View {
        ZStack {
            MistBackground()
                .ignoresSafeArea()
            SearchSheet(
                engine: engine,
                skimEnabled: skimEnabled,
                suggestionsEnabled: suggestionsEnabled,
                focusSuspended: focusSuspended,
                initialText: initialText,
                suggestions: suggestions,
                recents: recents,
                onOpen: onOpen,
                onSkim: onSkim,
                onDismiss: onDismiss
            )
            .offset(y: arrived ? 0 : Self.riseDistance)
        }
        // A full screen over the launch takes it out of the window, and a rise started
        // there never lands: the sheet rises once nothing covers it.
        .onAppear { if !focusSuspended { rise() } }
        .onChange(of: focusSuspended) { _, suspended in
            if !suspended { rise() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.screen")
    }

    private func rise() {
        guard !arrived else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
            arrived = true
        }
    }
}
