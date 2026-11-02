import SwiftUI

/// A mod's icon: an on-ink glyph on a 44 pt ink tile, the same tile the Settings rows
/// wear (03 · Mod icon). The mod's own colours stay in its index entry; the screens read
/// as one product, so the tile does not carry them.
struct ModIcon: View {

    /// Layout numbers from the board.
    private enum Layout {
        static let side: CGFloat = 44
    }

    let spec: ModIconSpec

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.Radius.iconSquare, style: .continuous)
                .fill(Palette.ink)
            Image(systemName: spec.glyph)
                .font(Typography.icon(.large))
                .foregroundStyle(Palette.onInk)
        }
        .frame(width: Layout.side, height: Layout.side)
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
