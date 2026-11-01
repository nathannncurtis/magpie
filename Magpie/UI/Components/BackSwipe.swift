import SwiftUI
import UIKit

extension View {
    /// A swipe in from the leading edge goes back: the view follows the finger, and a
    /// release past a third of the width, or a flick, runs `action`; anything less
    /// springs it home. Every screen with somewhere to go back to carries one.
    func backSwipe(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(BackSwipe(isEnabled: isEnabled, fromTrailing: false, action: action))
    }

    /// The same from the trailing edge, going forward: a page's next step in its history.
    func forwardSwipe(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(BackSwipe(isEnabled: isEnabled, fromTrailing: true, action: action))
    }
}

private struct BackSwipe: ViewModifier {
    let isEnabled: Bool
    /// Forward rather than back: in from the trailing edge, carrying the view the other way.
    let fromTrailing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0

    /// How far, as a share of the width, a release has to carry the view to go back.
    private static let commitShare: CGFloat = 1 / 3
    /// How fast a flick has to be, in points a second, to go back from anywhere.
    private static let commitVelocity: CGFloat = 600

    func body(content: Content) -> some View {
        content
            .offset(x: fromRight ? -offset : offset)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .background(
                EdgePan(
                    isEnabled: isEnabled,
                    edge: fromRight ? .right : .left,
                    onChange: { offset = $0 },
                    onEnd: end)
            )
            // VoiceOver's two-finger scrub is the same way back.
            .accessibilityAction(.escape) { if isEnabled && !fromTrailing { action() } }
    }

    /// Which screen edge the swipe starts from, once the layout direction has had its say.
    private var fromRight: Bool {
        fromTrailing != (layoutDirection == .rightToLeft)
    }

    private func end(distance: CGFloat, velocity: CGFloat) {
        let commits =
            distance > width * Self.commitShare
            || (velocity > Self.commitVelocity && distance > 0)
        if commits {
            action()
            // The surface's own move takes it from here; the next view starts in place.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { offset = 0 }
        } else {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
                offset = 0
            }
        }
    }
}

/// The system's screen-edge pan, which starts only on a touch at the edge, so it never
/// takes a scroll, a row swipe or a card fling that begins anywhere else. It sits on the
/// screen's own view, below SwiftUI's gestures, so a row under the thumb can't claim the
/// touch first; it comes off again when the screen leaves.
private struct EdgePan: UIViewRepresentable {
    let isEnabled: Bool
    let edge: UIRectEdge
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.coordinator = context.coordinator
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.pan.edges = edge
        coordinator.pan.isEnabled = isEnabled
        coordinator.onChange = onChange
        coordinator.onEnd = onEnd
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Finds the screen's view once it is in a window, and hangs the pan on it.
    final class Anchor: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                coordinator?.detach()
                return
            }
            var responder: UIResponder? = self
            while let next = responder?.next, !(next is UIViewController) { responder = next }
            if let host = (responder?.next as? UIViewController)?.view {
                coordinator?.attach(to: host)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let pan = UIScreenEdgePanGestureRecognizer()
        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }

        override init() {
            super.init()
            pan.delegate = self
            pan.addTarget(self, action: #selector(moved))
        }

        func attach(to host: UIView) {
            guard pan.view !== host else { return }
            pan.view?.removeGestureRecognizer(pan)
            host.addGestureRecognizer(pan)
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
        }

        @objc private func moved() {
            let sign: CGFloat = pan.edges == .right ? -1 : 1
            let distance = max(0, pan.translation(in: nil).x * sign)
            switch pan.state {
            case .began, .changed:
                onChange(distance)
            case .ended:
                onEnd(distance, pan.velocity(in: nil).x * sign)
            case .cancelled, .failed:
                onEnd(0, 0)
            default:
                break
            }
        }

        /// Whatever else is under the edge — a list's scroll, a row's tap or press —
        /// waits to see whether this is a swipe back. Another edge swipe never does.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIScreenEdgePanGestureRecognizer) && !(other.view is UIWindow)
        }
    }
}

/// A pushed page with its bar hidden still pops on the system's edge swipe: hiding the
/// bar otherwise switches that swipe off.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer !== interactivePopGestureRecognizer || viewControllers.count > 1
    }
}
