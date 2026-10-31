import SwiftUI

/// One suggestion, or one recent search: a search icon, the text, and the Skim offer.
/// Tapping the row searches; tapping the pill runs Skim for the same words. To VoiceOver
/// the row is the query alone, with Skim as a named action standing in for the pill.
struct SuggestionRow: View {

    /// Layout numbers from the suggestion-row spec.
    private enum Layout {
        static let iconSize: CGFloat = 16
        static let gap: CGFloat = 12
        static let horizontalPadding: CGFloat = 12
    }

    let text: String
    var skimState: SkimPill.State = .hidden
    let onSearch: () -> Void
    let onSkim: () -> Void

    var body: some View {
        Button(action: onSearch) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(Palette.textTertiary)
                Text(text)
                    .font(Typography.row)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Layout.gap)
                SkimPill(state: skimState, action: onSkim)
                    // The row is the element; the pill's tap is its Skim action below,
                    // so the pill itself stays out of the tree.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .frame(minHeight: Metrics.Spacing.rowSuggestion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(text))
        .modifier(SkimAction(state: skimState, action: onSkim))
    }
}

/// The row's stand-in for the pill's tap, present only while the pill is on screen: a
/// named action, so VoiceOver reads the query once and still reaches Skim.
private struct SkimAction: ViewModifier {
    let state: SkimPill.State
    let action: () -> Void

    func body(content: Content) -> some View {
        if state != .hidden {
            content.accessibilityAction(named: Text(String(localized: "Skim"))) { action() }
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        SuggestionRow(
            text: "seasoning carbon steel",
            skimState: .resolve(skimEnabled: true, primed: true),
            onSearch: {},
            onSkim: {})
        SuggestionRow(
            text: "seasoning cast iron",
            skimState: .resolve(skimEnabled: true, primed: false),
            onSearch: {},
            onSkim: {})
    }
    .padding()
}
