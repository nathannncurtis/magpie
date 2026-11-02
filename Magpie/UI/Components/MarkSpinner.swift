import SwiftUI

/// The mark drawing itself, over and over: the stroke reveals along its
/// centerline, the bead drops into the dry gap, the whole mark clears, and it
/// starts again (01 · the mark). Stands whole under Reduce Motion.
struct MarkSpinner: View {

    /// The mark's side, in points.
    var size: CGFloat

    private enum Loop {
        static let draw: TimeInterval = 1.15
        static let hold: TimeInterval = 0.75
        static let fade: TimeInterval = 0.5
        static let pause: TimeInterval = 0.25
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trim: CGFloat = 0
    @State private var beadDropped = false
    @State private var faded = false

    var body: some View {
        ZStack {
            Mark(size: size, style: .strokeOnly)
                .mask(RevealStroke(progress: trim, strokeWidth: MarkDraw.strokeWidth))
            MarkBeadShape()
                .fill(Palette.sheen)
                .scaleEffect(beadDropped ? 1 : 0.001, anchor: MarkDraw.beadAnchor)
                .opacity(beadDropped ? 1 : 0)
        }
        .frame(width: size, height: size)
        .opacity(faded ? 0 : 1)
        .task { await cycle() }
        .accessibilityHidden(true)
    }

    /// One turn of the loop: draw, drop, hold, clear, pause.
    private func cycle() async {
        guard !reduceMotion else {
            trim = 1
            beadDropped = true
            return
        }
        while !Task.isCancelled {
            trim = 0
            beadDropped = false
            faded = false
            withAnimation(Springs.ease(Loop.draw)) {
                trim = 1
            }
            guard await sleep(Loop.draw) else { return }
            withAnimation(Springs.snap.animation) {
                beadDropped = true
            }
            guard await sleep(Loop.hold) else { return }
            withAnimation(Springs.easeOut(Loop.fade)) {
                faded = true
            }
            guard await sleep(Loop.fade + Loop.pause) else { return }
        }
    }

    private func sleep(_ duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(duration))
            return true
        } catch {
            return false
        }
    }
}

/// The numbers a drawing mark shares, so the spinner and the launch intro draw the same
/// one.
enum MarkDraw {

    /// The brush stroke's width in the artwork's own units: 170 units of the
    /// foundations centerline, in the artwork's 512-unit space.
    static let strokeWidth = 170.0 * MarkPath.units / 600

    /// Where the bead sits within the drawn mark, in unit coordinates, so its
    /// drop scales about its own center.
    static let beadAnchor: UnitPoint = {
        let bounds = MarkGeometry.drawnBounds
        return UnitPoint(
            x: (MarkPath.beadCenter.x - bounds.minX) / bounds.width,
            y: (MarkPath.beadCenter.y - bounds.minY) / bounds.height)
    }()
}

/// The centerline as a round-capped stroke, trimmed to how far the mark has
/// drawn; the mask that reveals the brush.
struct RevealStroke: Shape {

    var progress: CGFloat
    var strokeWidth: Double

    func path(in rect: CGRect) -> Path {
        let transform = MarkGeometry.transform(into: rect)
        let line = MarkGeometry.centerline()
            .applying(transform)
            .trimmedPath(from: 0, to: min(max(progress, 0.001), 1))
        return line.strokedPath(
            StrokeStyle(lineWidth: strokeWidth * transform.a, lineCap: .round))
    }
}

#Preview {
    VStack(spacing: 40) {
        MarkSpinner(size: 96)
        MarkSpinner(size: 24)
    }
    .foregroundStyle(Palette.textPrimary)
    .padding(40)
}
