import SwiftUI

/// The Magpie mark: one brushstroke that drops, sweeps under a sheen bead and lifts away dry.
///
/// The artwork is traced exactly from the design asset; `size` is the side it scales into.
struct Mark: View {

    /// How the mark is coloured.
    enum Style {
        /// The brush in the current colour, the bead in the sheen gradient.
        case sheen
        /// Brush and bead both in the current colour.
        case solid
        /// The brush alone, for small marks in pills and buttons.
        case strokeOnly
    }

    /// The mark's side, in points. It scales from this alone.
    var size: CGFloat
    var style: Style = .sheen

    var body: some View {
        ZStack {
            MarkBrushShape()
            if style != .strokeOnly {
                if style == .sheen {
                    MarkBeadShape().fill(Palette.sheen)
                } else {
                    MarkBeadShape()
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The artwork's brush, as one filled path.
extension MarkPath {
    static func brushPath() -> Path {
        var path = Path()
        for subpath in brush {
            guard let first = subpath.first else { continue }
            path.move(to: first)
            for point in subpath.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        return path
    }
}

/// Geometry built from the artwork: what the drawn mark covers, and how to fit it into a rect.
enum MarkGeometry {

    /// Everything the drawn mark covers, brush and bead together, in the artwork's space.
    static let drawnBounds: CGRect = {
        let brush = MarkPath.brushPath().boundingRect
        let gap = CGRect(
            x: MarkPath.dryGapCenter.x - MarkPath.dryGapRadius,
            y: MarkPath.dryGapCenter.y - MarkPath.dryGapRadius,
            width: MarkPath.dryGapRadius * 2, height: MarkPath.dryGapRadius * 2)
        let bead = CGRect(
            x: MarkPath.beadCenter.x - MarkPath.beadRadius,
            y: MarkPath.beadCenter.y - MarkPath.beadRadius,
            width: MarkPath.beadRadius * 2, height: MarkPath.beadRadius * 2)
        return brush.union(gap).union(bead)
    }()

    /// Maps the artwork's space so the drawn mark fills `rect`, keeping its aspect.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let scale = min(
            rect.width / max(drawnBounds.width, 1),
            rect.height / max(drawnBounds.height, 1))
        let offsetX = rect.midX - (drawnBounds.midX * scale)
        let offsetY = rect.midY - (drawnBounds.midY * scale)
        return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
    }

    /// The draw-on reveal centreline from the foundations spec, mapped from its 600-unit
    /// space into the artwork's 512-unit space. Unused until the draw-on animation lands.
    static func centreline() -> Path {
        let scale = MarkPath.units / 600
        var path = Path()
        path.move(to: CGPoint(x: 170 * scale, y: 96 * scale))
        path.addLine(to: CGPoint(x: 150 * scale, y: 140 * scale))
        path.addCurve(
            to: CGPoint(x: 300 * scale, y: 420 * scale),
            control1: CGPoint(x: 96 * scale, y: 250 * scale),
            control2: CGPoint(x: 140 * scale, y: 420 * scale))
        path.addCurve(
            to: CGPoint(x: 380 * scale, y: 286 * scale),
            control1: CGPoint(x: 400 * scale, y: 420 * scale),
            control2: CGPoint(x: 440 * scale, y: 330 * scale))
        path.addLine(to: CGPoint(x: 330 * scale, y: 250 * scale))
        return path
    }
}

/// The brushstroke and its dry gap, scaled into the mark's frame.
private struct MarkBrushShape: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = MarkGeometry.transform(into: rect)
        var path = MarkPath.brushPath().applying(transform)

        var gap = Path(
            ellipseIn: CGRect(
                x: MarkPath.dryGapCenter.x - MarkPath.dryGapRadius,
                y: MarkPath.dryGapCenter.y - MarkPath.dryGapRadius,
                width: MarkPath.dryGapRadius * 2, height: MarkPath.dryGapRadius * 2))
        gap = gap.applying(transform)
        path.addPath(gap)
        return path
    }
}

/// The sheen bead, scaled with the brush.
struct MarkBeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = MarkGeometry.transform(into: rect)
        let center = CGPoint(x: MarkPath.beadCenter.x, y: MarkPath.beadCenter.y)
            .applying(transform)
        let radius = MarkPath.beadRadius * transform.a
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
