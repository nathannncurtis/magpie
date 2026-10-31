import SwiftUI

/// The glass search pill at the foot of the Archive and Bookmarks lists. It is the
/// field: tapping it focuses the search, and typing filters the list behind it live.
struct BottomSearchPill: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool

    /// The pill's height at the default size, growing with Dynamic Type the way its
    /// field's text does.
    @ScaledMetric(relativeTo: .subheadline) private var height = PillMetrics.height

    private enum PillMetrics {
        static let height: CGFloat = Metrics.Bar.bottomSearchPillHeight
        static let horizontalPadding: CGFloat = 20
        static let icon: CGFloat = 17
        static let iconGap: CGFloat = 10
    }

    var body: some View {
        HStack(spacing: PillMetrics.iconGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: PillMetrics.icon, weight: .medium))
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
        .padding(.horizontal, PillMetrics.horizontalPadding)
        .frame(minHeight: height)
        .glassEffect(.regular.interactive(), in: .capsule)
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
                        .padding(.horizontal, 14)
                        .padding(.bottom, 26)
                }
            }
        }
    }
    return PillHost()
}
