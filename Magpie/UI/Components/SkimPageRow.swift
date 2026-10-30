import SwiftUI

/// A saved Skim page in a list: the mark on an ink tile, the title, and its sources.
struct SkimPageRow: View {
    let title: String
    /// The folder the Skim page sits in, if any.
    var folderName: String?
    let sourceHosts: [String]

    private enum RowMetrics {
        static let tile: CGFloat = 26
        static let mark: CGFloat = 18
        static let markGap: CGFloat = 12
        static let sourcesGap: CGFloat = 10
        static let verticalPadding: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: RowMetrics.markGap) {
            RoundedRectangle(cornerRadius: Metrics.Radius.faviconLarge, style: .continuous)
                .fill(Palette.ink)
                .frame(width: RowMetrics.tile, height: RowMetrics.tile)
                .overlay {
                    Mark(size: RowMetrics.mark, style: .solid)
                        .foregroundStyle(Palette.onInk)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: RowMetrics.sourcesGap)
            FaviconStack(hosts: sourceHosts)
        }
        .padding(.vertical, RowMetrics.verticalPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    /// "Skim page · Kitchen".
    private var subtitle: String {
        guard let folderName, !folderName.isEmpty else {
            return String(localized: "Skim page")
        }
        return String(localized: "Skim page · \(folderName)")
    }

    /// The row as one line: the title, its kind, and the sources it was read from.
    private var accessibilityText: String {
        ([title, subtitle] + sourceHosts).joined(separator: ", ")
    }
}

#Preview {
    SkimPageRow(
        title: "Seasoning carbon steel", folderName: "Kitchen",
        sourceHosts: ["seriouseats.com", "debuyer.com", "reddit.com"]
    )
    .padding(.horizontal, 16)
}
