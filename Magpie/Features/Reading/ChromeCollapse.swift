import CoreGraphics

/// The scroll-driven chrome state machine (05 · Chrome on scroll). Scroll direction, not
/// position, decides: downward scroll collapses the bar after `threshold` points, any
/// upward scroll or the end of the page brings it back.
struct ChromeCollapse: Equatable {

    /// Downward scroll, in points, that fully collapses the bar.
    static let threshold: CGFloat = 24

    /// How far the bar has collapsed: 0 the full bar, 1 the slim pill.
    private(set) var progress: CGFloat = 0
    /// The last scroll offset seen; nil until the first sample, which only sets it.
    private(set) var lastOffset: CGFloat?

    /// How the caller should apply a progress change.
    enum Step: Equatable {
        /// Nothing moved.
        case unchanged
        /// Follow the finger: apply the progress without animation.
        case track
        /// A turning point: settle to the progress on the settle spring.
        case settle
    }

    /// One scroll position. `atEndOfPage` covers both a page that has scrolled to its
    /// end and one too short to scroll at all.
    mutating func scrollDidChange(offsetY: CGFloat, atEndOfPage: Bool) -> Step {
        defer { lastOffset = offsetY }
        if atEndOfPage {
            return collapseToFull()
        }
        guard let lastOffset else { return .unchanged }
        let delta = offsetY - lastOffset
        if delta < 0 {
            return collapseToFull()
        }
        guard delta > 0, progress < 1 else { return .unchanged }
        progress = min(1, progress + delta / Self.threshold)
        return progress >= 1 ? .settle : .track
    }

    /// Ends a partial collapse: the bar only slims after the full threshold of downward
    /// scroll, so a pause below it springs back to the full bar.
    mutating func snap() -> Step {
        guard progress > 0, progress < 1 else { return .unchanged }
        progress = 0
        return .settle
    }

    /// Brings the full bar back: the slim pill's tap.
    mutating func expand() -> Step {
        collapseToFull()
    }

    private mutating func collapseToFull() -> Step {
        guard progress > 0 else { return .unchanged }
        progress = 0
        return .settle
    }
}
