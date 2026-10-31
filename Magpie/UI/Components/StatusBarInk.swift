import SwiftUI
import UIKit

/// The status bar's ink: the system's own for the appearance, or forced dark or light so
/// the clock and battery read over a strip of page colour (04 · 04, the top strip).
enum StatusBarInk: Equatable {
    case automatic
    case dark
    case light

    /// The ink that reads over a fill, from its luminance under the appearance.
    static func over(_ fill: Color, scheme: ColorScheme) -> StatusBarInk {
        ReadableForeground.isLight(fill, scheme: scheme) ? .dark : .light
    }

    fileprivate var style: UIStatusBarStyle {
        switch self {
        case .automatic: .default
        case .dark: .darkContent
        case .light: .lightContent
        }
    }
}

extension View {
    /// Sets the status bar's ink for the window this view is in.
    func statusBarInk(_ ink: StatusBarInk) -> some View {
        background(StatusBarInkSetter(ink: ink).allowsHitTesting(false).accessibilityHidden(true))
    }
}

/// SwiftUI's root hosting controller owns the status bar and offers no say in its style,
/// so a clear window above it, touched by nothing and seen by nothing, carries one: the
/// status bar takes its style from the topmost window's controller.
private struct StatusBarInkSetter: UIViewRepresentable {
    let ink: StatusBarInk

    func makeUIView(context: Context) -> InkAnchorView { InkAnchorView() }

    func updateUIView(_ view: InkAnchorView, context: Context) {
        view.ink = ink
    }
}

private final class InkAnchorView: UIView {
    var ink: StatusBarInk = .automatic {
        didSet { overlay?.controller.ink = ink }
    }
    private var overlay: InkWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard overlay == nil, let scene = window?.windowScene else { return }
        let overlay = InkWindow(windowScene: scene)
        overlay.controller.ink = ink
        overlay.isHidden = false
        self.overlay = overlay
    }
}

private final class InkWindow: UIWindow {
    let controller = InkController()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        rootViewController = controller
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class InkController: UIViewController {
    var ink: StatusBarInk = .automatic {
        didSet {
            guard ink != oldValue else { return }
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        self.view = view
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { ink.style }
}
