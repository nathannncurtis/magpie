import SwiftUI

/// An uppercase section label over a group of rows or a box: "YESTERDAY", "SEARCH",
/// "RECENTLY ADDED". Every list screen uses this one, at the list inset.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.labelOnMist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.Spacing.insetList)
            .padding(.top, Metrics.Spacing.gapSectionTop)
            .padding(.bottom, Metrics.Spacing.gapSectionBottom)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    SectionLabel(title: "Yesterday")
}
