import SwiftUI

/// The engine's name at the trailing end of the search field.
struct EngineTag: View {

    /// Layout numbers from the search-field spec.
    private enum Layout {
        static let cornerRadius: CGFloat = 9
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
    }

    let name: String

    var body: some View {
        Text(name)
            .font(Typography.tag)
            .foregroundStyle(Palette.textSecondary)
            .padding(
                EdgeInsets(
                    top: Layout.verticalPadding,
                    leading: Layout.horizontalPadding,
                    bottom: Layout.verticalPadding,
                    trailing: Layout.horizontalPadding)
            )
            .background(
                Palette.tag,
                in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
            )
            .lineLimit(1)
    }
}

#Preview {
    EngineTag(name: "DuckDuckGo")
        .padding(20)
}
