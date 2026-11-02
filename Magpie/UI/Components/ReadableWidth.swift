import SwiftUI

extension Metrics {
    /// Column widths for containers wider than a phone.
    enum Column {
        /// The widest a content column grows: past it, lines run too long to read and
        /// rows and cards stretch thin. Wider than any phone, so phones never reach it.
        static let readable: CGFloat = 640
    }
}

extension View {
    /// Caps the view at the readable column and centers it in whatever is left.
    /// At phone widths the cap never binds, so the layout is unchanged.
    func readableWidth(_ width: CGFloat = Metrics.Column.readable) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
