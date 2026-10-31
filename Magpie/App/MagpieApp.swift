import SwiftUI

@main
struct MagpieApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = UITestEnvironment.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(UITestEnvironment.colorScheme)
                .environment(model)
                .task {
                    if UITestEnvironment.isUITesting { await UITestPageServer.shared.start() }
                    await model.start()
                    UITestEnvironment.applySurfaceOverride(to: model)
                    await UITestEnvironment.play(UITestEnvironment.script, on: model)
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
        }
    }
}
