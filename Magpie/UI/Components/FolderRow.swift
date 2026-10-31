import SwiftUI

/// A folder row in the Bookmarks list: the tinted glyph, the name, the count, a chevron.
struct FolderRow: View {
    let name: String
    let tint: FolderTint
    let count: Int

    private enum RowMetrics {
        static let glyphGap: CGFloat = 12
        static let countGap: CGFloat = 8
        static let chevron: CGFloat = 15
        static let verticalPadding: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: RowMetrics.glyphGap) {
            FolderGlyph(tint: tint)
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
                .font(.system(size: RowMetrics.chevron, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, RowMetrics.verticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// The folder glyph, drawn as on the board: a 28 × 24 two-tone folder, its back panel in
/// the tint's dark colour and its front panel in the light one, fading down into the dark.
struct FolderGlyph: View {
    let tint: FolderTint

    private enum GlyphMetrics {
        static let width: CGFloat = 28
        static let height: CGFloat = 24
    }

    var body: some View {
        ZStack {
            FolderBackShape()
                .fill(Color(hex: tint.back))
            FolderFrontShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: tint.front), Color(hex: tint.back)],
                        startPoint: .top, endPoint: .bottom))
        }
        .frame(width: GlyphMetrics.width, height: GlyphMetrics.height)
    }
}

/// The back panel: the whole folder with its tab, behind the front.
private struct FolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        // The artwork's 28 × 24 box, scaled into the given rect.
        let sx = rect.width / 28
        let sy = rect.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(2, 5.5))
        path.addArc(
            center: p(4.5, 5.5), radius: 2.5 * sx,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: p(10.5, 3))
        path.addLine(to: p(12.9, 5.6))
        path.addLine(to: p(23.5, 5.6))
        path.addArc(
            center: p(23.5, 8.1), radius: 2.5 * sx,
            startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: p(26, 19.5))
        path.addArc(
            center: p(23.5, 19.5), radius: 2.5 * sx,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: p(4.5, 22))
        path.addArc(
            center: p(4.5, 19.5), radius: 2.5 * sx,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The front panel, from a little under the tab down to the base.
private struct FolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 28
        let sy = rect.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(2, 9.6))
        path.addArc(
            center: p(4.4, 9.6), radius: 2.4 * sx,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: p(23.6, 7.2))
        path.addArc(
            center: p(23.6, 9.6), radius: 2.4 * sx,
            startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: p(26, 19.5))
        path.addArc(
            center: p(23.5, 19.5), radius: 2.5 * sx,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: p(4.5, 22))
        path.addArc(
            center: p(4.5, 19.5), radius: 2.5 * sx,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

#Preview("The three board defaults") {
    VStack(spacing: 12) {
        FolderRow(name: "Kitchen", tint: .orange, count: 14)
        FolderRow(name: "Reading", tint: .blue, count: 32)
        FolderRow(name: "Work", tint: .sage, count: 9)
    }
    .padding(.horizontal, 16)
}
