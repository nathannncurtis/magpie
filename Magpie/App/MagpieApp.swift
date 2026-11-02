import SwiftUI

@main
struct MagpieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = UITestEnvironment.makeModel()

    /// A link handed over before the saved tabs are in, opened once they are.
    @State private var pendingURL: URL?
    @State private var started = false
    /// Quick actions arrive here, from the launch and while the app runs.
    @State private var shortcuts = ShortcutInbox.shared

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
                        open(url)
                    }
                    takeShortcut()
                    UITestEnvironment.applySurfaceOverride(to: model)
                    await UITestEnvironment.play(UITestEnvironment.script, on: model)
                }
                .onOpenURL { url in
                    guard MagpieLink(url: url) != nil || url.scheme == "http" || url.scheme == "https"
                    else { return }
                    if started { open(url) } else { pendingURL = url }
                }
                .onChange(of: shortcuts.pending) { _, _ in takeShortcut() }
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
                    if phase == .background { model.appEnteredBackground() }
                    if phase == .active {
                        model.refreshArchive()
                        model.downloads.reload()
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

extension MagpieApp {
    /// Opens a web address, or carries out a link in Magpie's own scheme.
    private func open(_ url: URL) {
        if let link = MagpieLink(url: url) {
            model.handle(link)
        } else {
            model.openExternalLink(url)
        }
    }

    /// Carries out a waiting quick action, once the saved tabs are in.
    private func takeShortcut() {
        guard started, let action = shortcuts.pending else { return }
        shortcuts.pending = nil
        model.handle(action)
    }
}
