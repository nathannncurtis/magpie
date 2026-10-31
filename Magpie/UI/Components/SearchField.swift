import SwiftUI

/// The search field: a 1.5 pt sheen ring around an inner field that carries the text and
/// the engine tag.
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
                .accessibilityLabel(Text(String(localized: "Search")))
                .accessibilityIdentifier("search.field")
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
        @FocusState private var focused: Bool

        var body: some View {
            SearchField(text: $text, engineName: "DuckDuckGo", focus: $focused, onSubmit: {})
                .padding(20)
        }
    }
    return FieldHost()
}
