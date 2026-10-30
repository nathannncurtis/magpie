import SwiftUI

/// 01 · Launch: the mist with the search sheet, its field focused with the keyboard up on
/// arrival. Submitting a search or an address opens a new tab on the reading screen. The
/// sheet rises from the bottom (05 · Launch); a swipe down or a tap away goes back to the
/// stack when there are tabs to return to.
struct LaunchScreen: View {
    let engine: SearchEngine
    var skimEnabled: Bool = true
    var suggestionsEnabled: Bool = true
    let suggestions: any SuggestionProviding
    let recents: any RecentSearchStoring
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
                suggestions: suggestions,
                recents: recents,
                onOpen: onOpen,
                onDismiss: onDismiss
            )
            .offset(y: arrived ? 0 : Self.riseDistance)
        }
        .onAppear {
            guard !arrived else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
                arrived = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.screen")
    }
}
