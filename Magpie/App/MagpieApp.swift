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
                    if UITestEnvironment.isUITesting { UITestPageServer.shared.start() }
                    await model.start()
                    UITestEnvironment.applySurfaceOverride(to: model)
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
