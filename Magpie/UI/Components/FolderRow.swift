import SwiftUI

/// A folder row in the Bookmarks list: the glyph, the name, the count, a chevron.
struct FolderRow: View {
    let name: String
    let count: Int

    private enum RowMetrics {
        static let glyphGap: CGFloat = 12
        static let countGap: CGFloat = 8
        static let verticalPadding: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: RowMetrics.glyphGap) {
            FolderGlyph()
            Text(name)
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: RowMetrics.countGap)
            Text(count, format: .number)
                .font(Typography.small)
                .foregroundStyle(Palette.textOnMistSecondary)
                .monospacedDigit()
            Image(systemName: "chevron.forward")
                .font(Typography.icon(.small))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, RowMetrics.verticalPadding)
        .frame(minHeight: Metrics.tapTarget)
        .accessibilityElement(children: .combine)
    }
}

/// The folder glyph: an ink tile with a folder line icon, the same tile the Settings
/// rows and mod icons wear.
struct FolderGlyph: View {
    private enum GlyphMetrics {
        static let side: CGFloat = 28
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.Radius.iconSquareSmall, style: .continuous)
                .fill(Palette.ink)
            Image(systemName: "folder")
                .font(Typography.icon(.small))
                .foregroundStyle(Palette.onInk)
        }
        .frame(width: GlyphMetrics.side, height: GlyphMetrics.side)
        .accessibilityHidden(true)
    }
}

#Preview("The three board defaults") {
    VStack(spacing: 12) {
        FolderRow(name: "Kitchen", count: 14)
        FolderRow(name: "Reading", count: 32)
        FolderRow(name: "Work", count: 9)
    }
    .padding(.horizontal, 16)
}
