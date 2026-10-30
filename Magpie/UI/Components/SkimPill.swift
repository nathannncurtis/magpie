import SwiftUI
import UIKit

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

    /// Layout and colour numbers from the Skim-pill spec.
    private enum Layout {
        static let markSize: CGFloat = 13
        static let gap: CGFloat = 6
        static let horizontalPadding: CGFloat = 11
        static let verticalPadding: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let highlightHeight: CGFloat = 1.5

        static let restingBackground = Color.dynamic(
            light: 0xFFFFFF, lightOpacity: 0.45, dark: 0xFFFFFF, darkOpacity: 0.07)
        static let restingBorder = Color.dynamic(
            light: 0x101115, lightOpacity: 0.16, dark: 0xFFFFFF, darkOpacity: 0.18)
        static let restingHighlight = Color.dynamic(
            light: 0xFFFFFF, lightOpacity: 0.90, dark: 0xFFFFFF, darkOpacity: 0)
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
            }
            .buttonStyle(.plain)
        }
    }

    /// Solid ink when primed; otherwise translucent with a border and a top highlight.
    private var fill: Color {
        state == .primed ? Palette.ink : Layout.restingBackground
    }

    @ViewBuilder
    private var border: some View {
        if state == .resting {
            Capsule()
                .strokeBorder(Layout.restingBorder, lineWidth: Layout.borderWidth)
        }
    }

    /// The white inner top highlight on the resting pill, light mode only.
    @ViewBuilder
    private var highlight: some View {
        if state == .resting {
            LinearGradient(
                colors: [Layout.restingHighlight, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Layout.highlightHeight)
            .padding(.horizontal, Layout.borderWidth)
            .allowsHitTesting(false)
        }
    }
}

private extension Color {
    /// An sRGB colour that switches with the system appearance.
    static func dynamic(
        light: UInt32, lightOpacity: Double, dark: UInt32, darkOpacity: Double
    ) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, opacity: darkOpacity)
                    : UIColor(hex: light, opacity: lightOpacity)
            })
    }
}

private extension UIColor {
    /// An sRGB colour from a 0xRRGGBB value, at the given opacity.
    convenience init(hex: UInt32, opacity: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(opacity))
    }
}

#Preview("States") {
    VStack(spacing: 16) {
        SkimPill(state: .primed) {}
        SkimPill(state: .resting) {}
    }
    .padding(24)
}
