import SwiftUI

/// The mark's placing (05 · 07).
private enum Layout {
    /// The mark's side.
    static let markSize: CGFloat = 96
    /// How far the mark rises as it steps aside.
    static let asideRise: CGFloat = 40
    /// Where the mark sits, as a fraction of the height: slightly above the middle.
    static let markHeight = 0.4
}

/// The intro's beats. The draw and the hold hold past their beats under the UI tests'
/// shot mode, so a shot lands inside them whatever the runner's latency; the released
/// app plays them on time.
private enum Timing {
    /// The mist fading up from paper.
    static let mistFade: TimeInterval = 0.25
    /// The mark drawing itself.
    static let draw: TimeInterval = 0.7
    /// The hold with the mark whole.
    static let hold: TimeInterval = 0.3
    /// Every moment under Reduce Motion.
    static let reducedFade: TimeInterval = 0.2
    /// How long the drawn phases hold in the UI tests' shot mode.
    static let heldPhase: TimeInterval = 4

    static var drawBeat: TimeInterval {
        UITestEnvironment.holdsLaunchIntro ? heldPhase : draw
    }

    static var holdBeat: TimeInterval {
        UITestEnvironment.holdsLaunchIntro ? heldPhase : hold
    }
}

/// 05 · 07 Launch: the cold-start intro wrapped around the launch screen. The mist fades
/// up from paper, the mark draws itself once and holds in its sheen, then steps aside —
/// rising 40 pt and fading — as the launch screen's sheet rises from the bottom, its
/// field focused with the keyboard. A tap anywhere skips straight to that hand-off, and
/// after it the sheet takes every touch. Under Reduce Motion the mark stands whole and
/// the sheet crossfades in.
///
/// `plays` is the app model's one trigger: a cold start with no tab to restore and
/// onboarding behind it. Every other arrival of the launch screen — a restored tab, the
/// first-launch flow, the + on the tabs screen — shows it straight away.
struct LaunchIntro<Launch: View>: View {

    /// Whether this arrival is the intro's one cold start.
    var plays: Bool
    /// The intro's call once it has played, been skipped, or left the screen: no later
    /// return to the launch search draws the mark again.
    var onFinished: () -> Void = {}
    /// The launch screen, held back until the hand-off raises it.
    @ViewBuilder var launch: () -> Launch

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The system's Reduce Motion, or the UI tests' forced stand-in for it: the
    /// environment key itself is the system's to set.
    private var motionReduced: Bool {
        UITestEnvironment.reduceMotionOverride ?? reduceMotion
    }
    /// Whether this view is running the intro, held from `plays` at birth so the model's
    /// flag clearing mid-play cannot pull the stage out from under it.
    @State private var intro: Bool
    /// Whether the launch screen is up.
    @State private var sheetUp: Bool
    @State private var mistUp = false
    /// How far the stroke has revealed along its centreline.
    @State private var trim: CGFloat = 0
    @State private var beadDropped = false
    @State private var markAside = false
    /// The stepped-aside mark, cleared away once its fade has run.
    @State private var markGone = false

    init(
        plays: Bool,
        onFinished: @escaping () -> Void = {},
        @ViewBuilder launch: @escaping () -> Launch
    ) {
        self.plays = plays
        self.onFinished = onFinished
        self.launch = launch
        _intro = State(initialValue: plays)
        _sheetUp = State(initialValue: !plays)
    }

    var body: some View {
        ZStack {
            if sheetUp {
                launch()
            }
            if intro && !markGone {
                markStage
                    // The stage carries the skip tap while the intro is up, and nothing
                    // after the hand-off: the sheet takes every touch from there on.
                    .allowsHitTesting(!sheetUp)
                    // The intro's element rides on the stage, never around the sheet: a
                    // contain element left over the sheet starves the snapshots that read
                    // the rows the field's typing inserts. The value names the moment the
                    // stage is in, so the UI tests' shots wait for the moment itself.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("launch.intro")
                    .accessibilityValue(phase)
            }
        }
        .task { await run() }
        .task(id: sheetUp) {
            guard sheetUp, intro else { return }
            await sleep(0.9)
            markGone = true
        }
        .onDisappear { onFinished() }
    }

    /// The intro's stage: paper, the mist fading up over it, and the mark drawing at two
    /// fifths of the height. A tap anywhere on it skips.
    private var markStage: some View {
        GeometryReader { geo in
            ZStack {
                Palette.paper
                MistBackground()
                    .opacity(mistUp ? 1 : 0)
                mark
                    .position(x: geo.size.width / 2, y: geo.size.height * Layout.markHeight)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: skip)
    }

    /// The mark drawing itself, once: the stroke revealing along its centreline, the bead
    /// dropping into its dry gap at the end, and the whole of it rising away at the
    /// hand-off.
    private var mark: some View {
        ZStack {
            Mark(size: Layout.markSize, style: .strokeOnly)
                .mask(RevealStroke(progress: trim, strokeWidth: MarkDraw.strokeWidth))
            MarkBeadShape()
                .fill(Palette.sheen)
                .scaleEffect(beadDropped ? 1 : 0.001, anchor: MarkDraw.beadAnchor)
                .opacity(beadDropped ? 1 : 0)
        }
        .foregroundStyle(Palette.textPrimary)
        .frame(width: Layout.markSize, height: Layout.markSize)
        .offset(y: markAside ? -Layout.asideRise : 0)
        .opacity(markAside ? 0 : 1)
        .accessibilityHidden(true)
    }

    // MARK: The sequence

    /// The stage's moment: the mist arriving, the stroke drawing, the mark whole. The
    /// draw's state flips when the stroke starts, not as it renders, so "drawing" spans
    /// the whole animated draw.
    private var phase: String {
        if beadDropped {
            "whole"
        } else if trim > 0 {
            "drawing"
        } else {
            "mist"
        }
    }

    /// Mist, draw, bead, hold, hand-off. Each step stands down if a tap has already
    /// handed off.
    private func run() async {
        guard intro else { return }
        if motionReduced {
            await runReduced()
            return
        }
        withAnimation(.easeInOut(duration: Timing.mistFade)) {
            mistUp = true
        }
        await sleep(Timing.mistFade)
        guard !sheetUp else { return }
        withAnimation(.easeInOut(duration: Timing.drawBeat)) {
            trim = 1
        }
        await sleep(Timing.drawBeat)
        guard !sheetUp else { return }
        withAnimation(Springs.snap.animation) {
            beadDropped = true
        }
        await sleep(Timing.holdBeat)
        guard !sheetUp else { return }
        handOff()
    }

    /// Reduce Motion: the mark whole, then the sheet crossfading in as the mark fades out.
    private func runReduced() async {
        withAnimation(.easeInOut(duration: Timing.reducedFade)) {
            mistUp = true
        }
        await sleep(Timing.reducedFade)
        guard !sheetUp else { return }
        trim = 1
        beadDropped = true
        await sleep(Timing.holdBeat)
        guard !sheetUp else { return }
        withAnimation(.easeInOut(duration: Timing.reducedFade)) {
            markAside = true
            sheetUp = true
        }
        onFinished()
    }

    /// The mark steps aside, rising and fading, as the sheet rises: both on the chrome
    /// spring.
    private func handOff() {
        withAnimation(Springs.chrome.animation) {
            markAside = true
            sheetUp = true
        }
        onFinished()
    }

    /// A tap while the intro is up: straight to the hand-off.
    private func skip() {
        guard !sheetUp else { return }
        handOff()
    }

    private func sleep(_ duration: TimeInterval) async {
        try? await Task.sleep(for: .seconds(duration))
    }
}

#Preview("The intro") {
    LaunchIntro(plays: true) {
        LaunchScreen(
            engine: .default,
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches(),
            onOpen: { _ in },
            onDismiss: {})
    }
}

#Preview("Straight to the sheet") {
    LaunchIntro(plays: false) {
        LaunchScreen(
            engine: .default,
            suggestions: StubSuggestionProvider(rowsByPrefix: []),
            recents: RecentSearches(),
            onOpen: { _ in },
            onDismiss: {})
    }
}
