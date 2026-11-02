import SwiftUI

/// The search field: a 1.5 pt sheen ring around an inner field that carries the text and
/// the engine tag. The text finishes a typed host inline (`AddressTextField`).
struct SearchField: View {

    /// Layout numbers from the search-field spec.
    private enum Layout {
        /// The field's height at the default size; it grows under the larger
        /// accessibility sizes rather than clipping to it.
        static let minHeight: CGFloat = 48
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 8
        static let contentGap: CGFloat = 10
        static let ringWidth: CGFloat = 1.5
    }

    @Binding var text: String
    let engineName: String
    @Binding var isFocused: Bool
    var completion = DomainCompletion()
    /// Whether the text the field opens with arrives selected.
    var selectsCarriedText = false
    /// Return, with the field's full text: a completion in progress is part of it.
    let onSubmit: (String) -> Void

    var body: some View {
        HStack(spacing: Layout.contentGap) {
            AddressTextField(
                text: $text,
                isFocused: $isFocused,
                completion: completion,
                selectsCarriedText: selectsCarriedText,
                onSubmit: onSubmit)
            EngineTag(name: engineName)
        }
        .padding(
            EdgeInsets(
                top: 0,
                leading: Layout.leadingPadding,
                bottom: 0,
                trailing: Layout.trailingPadding)
        )
        .frame(minHeight: Layout.minHeight)
        .background(
            Palette.searchFieldFill,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.searchFieldInner, style: .continuous)
        )
        .padding(Layout.ringWidth)
        .background(
            Palette.sheen,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.searchFieldOuter, style: .continuous))
    }
}

#Preview {
    struct FieldHost: View {
        @State private var text = "seasoning car"
        @State private var focused = false

        var body: some View {
            SearchField(text: $text, engineName: "DuckDuckGo", isFocused: $focused, onSubmit: { _ in })
                .padding(20)
        }
    }
    return FieldHost()
}
