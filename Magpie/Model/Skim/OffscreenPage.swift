import Foundation
import WebKit

/// An offscreen page load for Skim: an ephemeral WebKit page, nothing stored,
/// nothing shown, cut off when it stalls.
@MainActor
enum OffscreenPage {

    private static func make() -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        return WebPage(configuration: configuration)
    }

    /// Loads `url`, waits for it to finish, then runs `script` in the page and
    /// returns its string. nil when the page fails, stalls past `timeout`, or
    /// the script fails or returns anything but a string.
    static func load(url: URL, timeout: TimeInterval, script: String) async -> String? {
        let page = make()
        let stopper = Task { [weak page] in
            try? await Task.sleep(for: .seconds(timeout))
            page?.stopLoading()
        }
        defer { stopper.cancel() }
        do {
            for try await event in page.load(url) where event == .finished {
                return try? await page.callJavaScript(script, contentWorld: .defaultClient)
                    as? String
            }
        } catch {
            return nil
        }
        return nil
    }
}
