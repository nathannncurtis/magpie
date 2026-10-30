import SwiftUI

/// The four named animations.
enum Springs {

    /// A spring's tuning, matching `.spring(response:dampingFraction:)`.
    struct Spring: Equatable, Sendable {
        let response: Double
        let dampingFraction: Double

        /// The animation this tuning describes.
        var animation: Animation {
            .spring(response: response, dampingFraction: dampingFraction)
        }
    }

    /// All bar and sheet morphs, cards, bars arriving.
    static let chrome = Spring(response: 0.3, dampingFraction: 0.88)
    /// Scroll-collapse settle, re-flow.
    static let settle = Spring(response: 0.28, dampingFraction: 0.9)
    /// The only bounce: the installed check, the bead drop.
    static let snap = Spring(response: 0.34, dampingFraction: 0.72)

    /// The duration of the smooth crossfade.
    static let smoothDuration: Double = 0.35

    /// Mist clearing, crossfades.
    static var smooth: Animation {
        .easeInOut(duration: smoothDuration)
    }
}
