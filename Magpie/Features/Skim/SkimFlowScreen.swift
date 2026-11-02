import SwiftUI

/// The Skim surface: the working scene while it runs, the finished page, or the
/// failure that stopped it — and the handoff between working and page, where the
/// mark scales down and the mist clears into the page (05 · 04).
struct SkimFlowScreen: View {

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the working scene is clearing into the finished page.
    @State private var handoff = false
    /// The last progress the working scene showed, kept for the handoff.
    @State private var lastWorking = SkimProgress()

    var body: some View {
        ZStack {
            if let run = model.skimRun {
                if let page = run.page {
                    SkimPageScreen(
                        page: page,
                        onDone: { model.cancelSkim() },
                        onEditQuery: { model.editSkimQuery() },
                        onDigDeeper: { model.skimDigDeeper() },
                        onOpenSource: { model.openFromLaunch($0) })
                }
                if let progress = workingScene {
                    SkimWorkingScreen(
                        query: run.query,
                        progress: progress,
                        onCancel: { model.cancelSkim() },
                        exiting: handoff
                    )
                    .transition(.opacity)
                }
                if let failure = run.failure {
                    SkimFailedScreen(
                        query: run.query,
                        line: failure.line,
                        onDone: { model.cancelSkim() },
                        onShowResults: { model.showSkimSearchResults() },
                        onRetry: { model.retrySkim() }
                    )
                    .transition(.opacity)
                }
            } else {
                MistBackground()
                    .ignoresSafeArea()
            }
        }
        .animation(Springs.crossfade, value: model.skimRun?.state)
        .onChange(of: model.skimRun?.state) { _, newState in
            guard let newState else { return }
            if case .working(let progress) = newState {
                lastWorking = progress
            }
            if case .finished = newState {
                beginHandoff()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("skim.flow")
    }

    /// The working scene while the run is reading, and for a beat after it
    /// finishes, while it clears into the page.
    private var workingScene: SkimProgress? {
        if case .working(let progress) = model.skimRun?.state { return progress }
        if handoff { return lastWorking }
        return nil
    }

    private func beginHandoff() {
        guard !handoff else { return }
        withAnimation(Springs.resolved(Springs.smooth, reduceMotion: reduceMotion)) {
            handoff = true
        }
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? Springs.crossfadeDuration : Springs.smoothDuration))
            handoff = false
        }
    }
}
