import SwiftUI

/// What a drag on the reading bar means, as pure arithmetic: sideways steps through the
/// tabs, up opens the stack. The axis locks once, early, so a tap on a bar button is
/// never a drag and a diagonal wobble never flips between the two.
enum BarSwipe {

    /// The travel that locks the drag to one axis.
    static let axisLock: CGFloat = 24
    /// The share of the screen's width a sideways drag must cover to step a tab.
    static let stepFraction: CGFloat = 0.25
    /// How far up a drag must travel to open the stack, or its predicted end.
    static let upDistance: CGFloat = 56
    static let upPredicted: CGFloat = 140
    /// The most the bar itself rises with the finger.
    static let upRise: CGFloat = 28
    /// The most the page gives at an end of the stack, where there is no tab to reach.
    static let rubberLimit: CGFloat = 36

    enum Axis: Equatable {
        case horizontal
        case up
    }

    /// The axis a drag locks to once it has travelled `axisLock`, else nil. Down is
    /// nothing the bar answers to.
    static func axis(for translation: CGSize) -> Axis? {
        let across = abs(translation.width)
        let along = abs(translation.height)
        guard max(across, along) >= axisLock else { return nil }
        if across > along { return .horizontal }
        return translation.height < 0 ? .up : nil
    }

    /// How far the page and bar sit from rest for a sideways drag: one for one where a
    /// tab waits beyond, and a rubber band that tightens toward `rubberLimit` where none does.
    static func offset(translation: CGFloat, hasPrevious: Bool, hasNext: Bool) -> CGFloat {
        let reachable = translation < 0 ? hasNext : hasPrevious
        if reachable { return translation }
        let sign: CGFloat = translation < 0 ? -1 : 1
        return sign * rubberLimit * (1 - exp(-abs(translation) / (rubberLimit * 2)))
    }

    /// The tab step a sideways drag ends on: +1 for the next tab (a drag to the left),
    /// -1 for the previous, 0 for none, and never past an end of the stack.
    static func step(
        translation: CGFloat, predicted: CGFloat, width: CGFloat,
        hasPrevious: Bool, hasNext: Bool
    ) -> Int {
        let threshold = width * stepFraction
        let leftward = translation <= -threshold || predicted <= -threshold
        let rightward = translation >= threshold || predicted >= threshold
        if leftward && hasNext && !rightward { return 1 }
        if rightward && hasPrevious && !leftward { return -1 }
        return 0
    }

    /// Whether an upward drag has gone far enough to open the stack.
    static func opensStack(translationY: CGFloat, predictedY: CGFloat) -> Bool {
        translationY <= -upDistance || predictedY <= -upPredicted
    }

    /// How far the bar rises for an upward drag.
    static func rise(translationY: CGFloat) -> CGFloat {
        -upRise * (1 - exp(-max(0, -translationY) / upRise))
    }
}

/// How a bar drag reports itself to the screen above the bar.
struct BarSwipeHandlers {
    /// A locked axis moved: sideways translation, or the upward drag's travel.
    var changed: (BarSwipe.Axis, CGSize) -> Void
    /// The drag lifted, with its predicted end.
    var ended: (BarSwipe.Axis, CGSize, CGSize) -> Void
    /// The drag was cancelled, or never locked.
    var cancelled: () -> Void
}

/// Carries a drag on the bar, locking its axis after `BarSwipe.axisLock`. It runs beside
/// the buttons' own taps, which a tap's lack of travel leaves alone.
struct BarSwipeGesture: ViewModifier {
    let handlers: BarSwipeHandlers?

    @State private var axis: BarSwipe.Axis?

    func body(content: Content) -> some View {
        if let handlers {
            content.simultaneousGesture(
                DragGesture(minimumDistance: BarSwipe.axisLock)
                    .onChanged { value in
                        if axis == nil { axis = BarSwipe.axis(for: value.translation) }
                        if let axis { handlers.changed(axis, value.translation) }
                    }
                    .onEnded { value in
                        defer { axis = nil }
                        guard let axis else { return handlers.cancelled() }
                        handlers.ended(axis, value.translation, value.predictedEndTranslation)
                    }
            )
        } else {
            content
        }
    }
}
