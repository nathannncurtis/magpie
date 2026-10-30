import SwiftUI

/// An uppercase section label over a group of list rows: "YESTERDAY", "EARLIER THIS WEEK".
struct DayHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.labelOnMist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Metrics.Spacing.gapSectionTop)
            .padding(.bottom, Metrics.Spacing.gapSectionBottom)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    DayHeader(title: "Yesterday")
        .padding(.horizontal, 16)
}
