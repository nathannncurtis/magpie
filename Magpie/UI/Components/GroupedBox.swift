import SwiftUI

extension View {
    /// The surface grouped content sits on: frosted material, a hairline, the grouped
    /// radius. Settings groups, the default-browser card and the mod cards all wear it.
    func groupedSurface() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
        return
            self
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Palette.groupHairline, lineWidth: 0.75))
    }
}

/// A box of rows on the mist, the list inset from the screen's sides. The rows and their
/// hairlines run the box's width, no wider.
struct GroupedBox<Content: View>: View {
    /// The box's distance from the screen's sides; zero when the caller insets it.
    var sideInset: CGFloat = Metrics.Spacing.insetList
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .groupedSurface()
        .padding(.horizontal, sideInset)
    }
}
