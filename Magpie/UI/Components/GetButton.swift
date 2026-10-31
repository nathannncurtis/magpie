import SwiftUI

/// The "Get" capsule on a directory row (03 · Get button).
struct GetButton: View {

    private enum Layout {
        static let verticalPadding: CGFloat = 6
        static let horizontalPadding: CGFloat = 16
        /// The touch target the capsule carries: the 44 pt minimum, invisible.
        static let hitSide: CGFloat = 44
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(localized: "Get"))
                .font(Typography.meta.weight(.bold))
                .foregroundStyle(Palette.teal)
                .padding(.vertical, Layout.verticalPadding)
                .padding(.horizontal, Layout.horizontalPadding)
                .background(Palette.getButtonFill, in: .capsule)
                .frame(minWidth: Layout.hitSide, minHeight: Layout.hitSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mods.get")
    }
}

#Preview {
    GetButton {}
        .padding(20)
}
