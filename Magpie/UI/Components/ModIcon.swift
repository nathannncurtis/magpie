import SwiftUI

/// A mod's icon: a white glyph on a 44 pt tile, its own two colours on a 160-degree
/// gradient, with a hairline inset (03 · Mod icon).
struct ModIcon: View {

    /// Layout numbers from the board.
    private enum Layout {
        static let side: CGFloat = 44
        static let glyph: CGFloat = 22
        /// The inset hairline's opacity, off-black in light and off-white in dark.
        static let hairlineOpacity = 0.12
        static let hairlineOpacityDark = 0.15
    }

    let spec: ModIconSpec

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors, startPoint: UnitPoint(x: 0.58, y: 0), endPoint: UnitPoint(x: 0.42, y: 1))
            Image(systemName: spec.glyph)
                .font(.system(size: Layout.glyph, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: Layout.side, height: Layout.side)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.iconSquare, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.iconSquare, style: .continuous)
                .strokeBorder(hairline, lineWidth: 0.5)
        )
    }

    /// The spec's colours, or the plain link tile's when none of them parse.
    private var gradientColors: [Color] {
        let parsed = spec.gradient.compactMap(Self.color)
        return parsed.isEmpty
            ? [Color(hex: 0x9AA3AE), Color(hex: 0x5D6670)]
            : parsed
    }

    private var hairline: Color {
        (colorScheme == .dark ? Color.white : Color.black)
            .opacity(colorScheme == .dark ? Layout.hairlineOpacityDark : Layout.hairlineOpacity)
    }

    /// A "#RRGGBB" string as a colour; a malformed one drops out of the gradient.
    private static func color(_ hex: String) -> Color? {
        guard hex.count == 7, hex.first == "#" else { return nil }
        guard let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(hex: value)
    }
}

#Preview {
    VStack(spacing: 16) {
        ModIcon(spec: ModIconSpec(glyph: "text.bubble", gradient: ["#4C8DF6", "#1A56D6"]))
        ModIcon(spec: ModIconSpec(glyph: "moon.fill", gradient: ["#2B3358", "#0F1226"]))
        ModIcon(spec: .linkInstall())
    }
    .padding(24)
}
