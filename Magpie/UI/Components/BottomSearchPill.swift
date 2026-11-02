import SwiftUI

/// The glass search pill at the foot of the Archive and Bookmarks lists. It is the
/// field: tapping it focuses the search, and typing filters the list behind it live.
struct BottomSearchPill: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool

    private enum PillMetrics {
        static let horizontalPadding: CGFloat = 20
        static let iconGap: CGFloat = 10
    }

    var body: some View {
        FloatingBar(surface: .glass(interactive: true), contentInset: PillMetrics.horizontalPadding) {
            row
        }
    }

    private var row: some View {
        HStack(spacing: PillMetrics.iconGap) {
            Image(systemName: "magnifyingglass")
                .font(Typography.icon(.regular))
                .imageScale(.medium)
                .foregroundStyle(Palette.textOnMistSecondary)
            TextField(placeholder, text: $text)
                .font(Typography.row)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { focused = false }
                .accessibilityIdentifier("list.search.field")
        }
    }
}

#Preview {
    struct PillHost: View {
        @State private var text = ""

        var body: some View {
            ZStack {
                MistBackground().ignoresSafeArea()
                VStack {
                    Spacer()
                    BottomSearchPill(placeholder: "Search archived tabs", text: $text)
                        .floatingBarBottomEdge(safeAreaBottom: 34)
                }
            }
        }
    }
    return PillHost()
}
