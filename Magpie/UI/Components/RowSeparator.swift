import SwiftUI

/// The hairline between flat rows on the mist. It is inset the same at both ends, so it
/// never runs out to the glass edge on one side while stopping short on the other.
struct RowSeparator: View {
    /// How far the hairline sits in from each side of the row.
    let inset: CGFloat

    var body: some View {
        Rectangle()
            .fill(Palette.separatorOnMist)
            .frame(height: 0.5)
            .padding(.horizontal, inset)
    }
}
