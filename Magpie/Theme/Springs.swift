import SwiftUI

/// The named animations, and the one place that decides how Reduce Motion changes them.
enum Springs {

    /// A spring's tuning, matching `.spring(response:dampingFraction:)`.
    struct Spring: Equatable, Sendable {
        let response: Double
        let dampingFraction: Double

        /// The animation this tuning describes.
        var animation: Animation {
            .spring(response: response, dampingFraction: dampingFraction)
        }

        /// The spring, or Reduce Motion's crossfade in its place.
        func resolved(reduceMotion: Bool) -> Animation {
            reduceMotion ? Springs.crossfade : animation
        }

        /// The spring, or no animation at all under Reduce Motion.
        func unlessReduced(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
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

    /// The duration of Reduce Motion's crossfade, and of small fades.
    static let crossfadeDuration: Double = 0.2

    /// What every moment becomes under Reduce Motion.
    static var crossfade: Animation {
        .easeInOut(duration: crossfadeDuration)
    }

    /// A short fade in: fields and rows arriving, the arrival picture leaving.
    static var fadeIn: Animation {
        .easeOut(duration: crossfadeDuration)
    }

    /// A slow fade in, for a title settling into view.
    static var slowFadeIn: Animation {
        .easeOut(duration: 0.5)
    }

    /// An ease in and out over a set time, for sequenced beats and ambient loops.
    static func ease(_ duration: Double) -> Animation {
        .easeInOut(duration: duration)
    }

    /// An ease out over a set time.
    static func easeOut(_ duration: Double) -> Animation {
        .easeOut(duration: duration)
    }

    /// `animation`, or Reduce Motion's crossfade in its place.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfade : animation
    }
}
