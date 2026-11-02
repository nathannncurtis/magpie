import Observation
import UIKit

/// Where a home-screen quick action waits for the app to take it: the scene delegate
/// puts it here, from the launch or while the app runs, and the app model's owner picks
/// it up once the saved tabs are in.
@MainActor
@Observable
final class ShortcutInbox {
    static let shared = ShortcutInbox()

    var pending: ShortcutAction?

    func receive(_ item: UIApplicationShortcutItem) {
        pending = ShortcutAction(rawValue: item.type)
    }
}

/// Gives the window scene a delegate that sees the quick action the launch carried and
/// the ones that arrive later.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            MainActor.assumeIsolated { ShortcutInbox.shared.receive(item) }
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated { ShortcutInbox.shared.receive(shortcutItem) }
        completionHandler(true)
    }
}
