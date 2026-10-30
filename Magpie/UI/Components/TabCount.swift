import SwiftUI

/// The tab count glyph (01 Icons): a stroked rounded square holding the open-tab count,
/// not an SF Symbol. Above 99 it shows the infinity sign.
struct TabCount: View {

    /// The open-tab count.
    let count: Int

    /// The most the glyph counts before showing the infinity sign.
    nonisolated private static let countLimit = 99
    nonisolated private static let infinityLabel = "∞"
    /// The glyph's rounded square.
    private static let glyphSize: CGFloat = 22
    private static let glyphRadius: CGFloat = 7
    private static let stroke: CGFloat = 1.8
    /// The count inside the glyph.
    private static let labelSize: CGFloat = 11.5

    /// The label the glyph shows: the count, or the infinity sign above 99.
    nonisolated static func label(for count: Int) -> String {
        count > countLimit ? infinityLabel : "\(count)"
    }

    var body: some View {
        Text(Self.label(for: count))
            .font(.system(size: Self.labelSize, weight: .bold))
            .monospacedDigit()
            .frame(width: Self.glyphSize, height: Self.glyphSize)
            .overlay(
                RoundedRectangle(cornerRadius: Self.glyphRadius)
                    .strokeBorder(lineWidth: Self.stroke))
    }
}

#Preview {
    VStack(spacing: 20) {
        TabCount(count: 1)
        TabCount(count: 4)
        TabCount(count: 99)
        TabCount(count: 100)
    }
    .foregroundStyle(Color(hex: 0x3A2E26))
    .padding(40)
}
