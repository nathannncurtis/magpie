import SwiftUI

@main
struct MagpieApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = UITestEnvironment.makeModel()

    /// A link handed over before the saved tabs are in, opened once they are.
    @State private var pendingURL: URL?
    @State private var started = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(UITestEnvironment.colorScheme)
                .environment(model)
                .task {
                    if UITestEnvironment.isUITesting { await UITestPageServer.shared.start() }
                    await model.start()
                    started = true
                    if let url = pendingURL {
                        pendingURL = nil
                        model.openFromLaunch(url)
                    }
                    UITestEnvironment.applySurfaceOverride(to: model)
                    await UITestEnvironment.play(UITestEnvironment.script, on: model)
                }
                .onOpenURL { url in
                    guard url.scheme == "http" || url.scheme == "https" else { return }
                    if started { model.openFromLaunch(url) } else { pendingURL = url }
                }
                // The app switcher keeps a picture of the screen on disk; with a
                // private tab open, that picture is the mist.
                .overlay {
                    if scenePhase != .active, model.store.hasPrivateTabs {
                        ZStack {
                            MistBackground()
                            Image(systemName: "eye.slash")
                                .font(.largeTitle)
                                .foregroundStyle(Palette.ink)
                        }
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refreshArchive()
                        Task { await model.refreshBlocking() }
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification)
                ) { _ in
                    model.memoryWarning()
                }
        }
        .commands { KeyCommands(model: model) }
    }
}
