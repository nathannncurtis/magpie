import SwiftUI
import UIKit

/// The search field: a 1.5 pt sheen ring around an inner field that carries the text and
/// the engine tag.
struct SearchField: View {

    /// Layout and colour numbers from the search-field spec.
    private enum Layout {
        static let height: CGFloat = 48
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 8
        static let contentGap: CGFloat = 10
        static let ringWidth: CGFloat = 1.5

        static let innerBackground = Color.dynamic(
            light: 0xFFFFFF, lightOpacity: 0.72, dark: 0x1D2023, darkOpacity: 1)
    }

    @Binding var text: String
    let engineName: String
    let focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Layout.contentGap) {
            TextField("", text: $text)
                .font(Typography.field)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .focused(focus)
                .onSubmit(onSubmit)
            EngineTag(name: engineName)
        }
        .padding(
            EdgeInsets(
                top: 0,
                leading: Layout.leadingPadding,
                bottom: 0,
                trailing: Layout.trailingPadding)
        )
        .frame(height: Layout.height)
        .background(
            Layout.innerBackground,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.searchFieldInner, style: .continuous)
        )
        .padding(Layout.ringWidth)
        .background(
            Palette.sheen,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.searchFieldOuter, style: .continuous))
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

#Preview {
    struct FieldHost: View {
        @State private var text = "seasoning car"
        @FocusState private var focused: Bool

        var body: some View {
            SearchField(text: $text, engineName: "DuckDuckGo", focus: $focused, onSubmit: {})
                .padding(20)
        }
    }
    return FieldHost()
}
