import SwiftUI

@main
struct MagpieApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = UITestEnvironment.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshArchive() }
                }
        }
    }
}
