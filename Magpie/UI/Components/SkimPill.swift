import SwiftUI

/// The Skim offer at the trailing end of a suggestion row: the small mark and the word,
/// resting or primed.
struct SkimPill: View {

    /// Everything that decides how the pill reads, resolved in one place.
    enum State: Equatable {
        case hidden
        case resting
        case primed

        /// Skim is hidden entirely when it is off or unavailable; primed on the first row only.
        static func resolve(skimEnabled: Bool, primed: Bool) -> State {
            guard skimEnabled else { return .hidden }
            return primed ? .primed : .resting
        }
    }

    /// Layout numbers from the Skim-pill spec.
    private enum Layout {
        static let markSize: CGFloat = 13
        static let gap: CGFloat = 6
        static let horizontalPadding: CGFloat = 11
        static let verticalPadding: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let highlightHeight: CGFloat = 1.5
        /// The least height the pill answers a tap in: the 44 pt guideline, met inside
        /// the 46 pt suggestion row.
        static let hitHeight: CGFloat = 44
    }

    let state: State
    let action: () -> Void

    var body: some View {
        if state != .hidden {
            Button(action: action) {
                HStack(spacing: Layout.gap) {
                    Mark(size: Layout.markSize, style: .strokeOnly)
                    Text("Skim")
                        .font(Typography.small.weight(.semibold))
                }
                .foregroundStyle(state == .primed ? Palette.onInk : Palette.textPrimary)
                .padding(
                    EdgeInsets(
                        top: Layout.verticalPadding,
                        leading: Layout.horizontalPadding,
                        bottom: Layout.verticalPadding,
                        trailing: Layout.horizontalPadding)
                )
                .background(fill, in: .capsule)
                .overlay(border)
                .overlay(alignment: .top) { highlight }
                .clipShape(.capsule)
                // The capsule itself is half the row's height; the tap takes the whole
                // 44 pt band the pill sits in, centred on it.
                .frame(minHeight: Layout.hitHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Solid ink when primed; otherwise translucent with a border and a top highlight.
    private var fill: Color {
        state == .primed ? Palette.ink : Palette.skimPillFill
    }

    @ViewBuilder
    private var border: some View {
        if state == .resting {
            Capsule()
                .strokeBorder(Palette.skimPillBorder, lineWidth: Layout.borderWidth)
        }
    }

    /// The white inner top highlight on the resting pill, light mode only.
    @ViewBuilder
    private var highlight: some View {
        if state == .resting {
            LinearGradient(
                colors: [Palette.skimPillHighlight, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Layout.highlightHeight)
            .padding(.horizontal, Layout.borderWidth)
            .allowsHitTesting(false)
        }
    }
}

#Preview("States") {
    VStack(spacing: 16) {
        SkimPill(state: .primed) {}
        SkimPill(state: .resting) {}
    }
    .padding(24)
}
