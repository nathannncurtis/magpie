import SwiftUI

/// The Magpie mark: one brushstroke that drops, sweeps under a sheen bead and lifts away dry.
///
/// The stroke follows the mark's centreline in its 600-unit design space, drawn with a
/// 170-unit round-cap pen; the bead sits where the sweep cradles it.
struct Mark: View {

    /// How the mark is coloured.
    enum Style {
        /// The stroke in the current colour, the bead in the sheen gradient.
        case sheen
        /// Stroke and bead both in the current colour.
        case solid
        /// The stroke alone, for small marks in pills and buttons.
        case strokeOnly
    }

    /// The mark's side, in points. It scales from this alone.
    var size: CGFloat
    var style: Style = .sheen

    var body: some View {
        ZStack {
            MarkStroke()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: MarkGeometry.strokeWidth * scale,
                        lineCap: .round,
                        lineJoin: .round))
            if style != .strokeOnly {
                MarkBead()
                    .fill(beadFill)
            }
        }
        .frame(width: size, height: size)
    }

    private var scale: CGFloat {
        size / max(MarkGeometry.drawnBounds.width, MarkGeometry.drawnBounds.height)
    }

    private var beadFill: AnyShapeStyle {
        style == .sheen ? AnyShapeStyle(Palette.sheen) : AnyShapeStyle(.primary)
    }
}

/// The mark's geometry, in its 600-unit design space.
enum MarkGeometry {

    /// One side of the design space.
    static let units: CGFloat = 600
    /// The round-cap pen width the brushstroke is drawn with.
    static let strokeWidth: CGFloat = 170
    /// The bead, where the sweep cradles it.
    static let beadCenter = CGPoint(x: 316.4, y: 351.6)
    static let beadRadius: CGFloat = 68

    /// The stroke's centreline: it drops, sweeps under the bead and lifts away dry.
    static func centreline() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 170, y: 96))
        path.addLine(to: CGPoint(x: 150, y: 140))
        path.addCurve(
            to: CGPoint(x: 300, y: 420),
            control1: CGPoint(x: 96, y: 250),
            control2: CGPoint(x: 140, y: 420))
        path.addCurve(
            to: CGPoint(x: 380, y: 286),
            control1: CGPoint(x: 400, y: 420),
            control2: CGPoint(x: 440, y: 330))
        path.addLine(to: CGPoint(x: 330, y: 250))
        return path
    }

    /// Everything the drawn mark covers, stroke and bead together.
    static let drawnBounds: CGRect = {
        let stroked = centreline().cgPath.copy(
            strokingWithWidth: strokeWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0)
        var bounds = stroked.boundingBoxOfPath
        bounds = bounds.union(
            CGRect(
                x: beadCenter.x - beadRadius, y: beadCenter.y - beadRadius,
                width: beadRadius * 2, height: beadRadius * 2))
        return bounds
    }()

    /// Maps the design space so the drawn mark fills `rect`.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let scale = min(
            rect.width / max(drawnBounds.width, 1),
            rect.height / max(drawnBounds.height, 1))
        let offsetX = rect.midX - (drawnBounds.midX * scale)
        let offsetY = rect.midY - (drawnBounds.midY * scale)
        return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
    }
}

/// The brushstroke, scaled into the mark's frame.
private struct MarkStroke: Shape {
    func path(in rect: CGRect) -> Path {
        MarkGeometry.centreline().applying(MarkGeometry.transform(into: rect))
    }
}

/// The sheen bead, scaled with the stroke.
private struct MarkBead: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = MarkGeometry.transform(into: rect)
        let center = CGPoint(x: MarkGeometry.beadCenter.x, y: MarkGeometry.beadCenter.y)
            .applying(transform)
        let radius = MarkGeometry.beadRadius * transform.a
        return Path(
            ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
    }
}

#Preview("Sheen") {
    Mark(size: 120, style: .sheen)
        .foregroundStyle(Palette.textPrimary)
        .padding(40)
}

#Preview("Solid and stroke-only") {
    VStack(spacing: 24) {
        Mark(size: 40, style: .solid)
        Mark(size: 13, style: .strokeOnly)
    }
    .foregroundStyle(Palette.textPrimary)
    .padding(40)
}
