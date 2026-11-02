import SwiftUI

/// The one primary action: an ink capsule with an on-ink label. Mods' Get, the install
/// sheet's Install, onboarding's Continue and Skim failed's "Show search results" all
/// wear it, in the size that fits their place.
///
/// Disabled, it drops to the quiet fill with secondary text, which holds 4.5:1 in both
/// appearances; fading the ink out would leave the label unreadable.
struct PrimaryButtonStyle: ButtonStyle {

    /// How tall and how wide the button runs.
    enum Size {
        /// A full-width bar CTA.
        case bar
        /// A full-width button in a sheet's row.
        case sheet
        /// A capsule hugging its label, inside a row.
        case compact
    }

    var size: Size = .bar

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(isEnabled ? Palette.onInk : Palette.textSecondary)
            .padding(.horizontal, size == .compact ? 16 : 0)
            .padding(.vertical, size == .compact ? 6 : 0)
            .frame(maxWidth: size == .compact ? nil : .infinity)
            .frame(minHeight: minHeight)
            .background(isEnabled ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.fill), in: .capsule)
            // The capsule keeps its size; a compact one's target meets the 44 pt least.
            .frame(
                minWidth: size == .compact ? Metrics.tapTarget : nil,
                minHeight: size == .compact ? Metrics.tapTarget : nil
            )
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Springs.snap.unlessReduced(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var font: Font {
        switch size {
        case .bar: Typography.buttonBar
        case .sheet, .compact: Typography.buttonPill
        }
    }

    private var minHeight: CGFloat? {
        switch size {
        case .bar: Metrics.Bar.primaryCTAHeight
        case .sheet: 50
        case .compact: nil
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// The primary action style, in the given size.
    static func primary(_ size: PrimaryButtonStyle.Size = .bar) -> PrimaryButtonStyle {
        PrimaryButtonStyle(size: size)
    }
}
