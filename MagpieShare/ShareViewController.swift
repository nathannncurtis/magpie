import UIKit
import UniformTypeIdentifiers

/// The Share sheet's "Open in Magpie": finds the link in what was shared, opens Magpie
/// on it through its URL scheme, and finishes. No interface of its own.
final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor in
            if let page = await sharedLink(), let link = MagpieLink.openURL(for: page) {
                await open(link)
            }
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// The first web address among the shared items: a URL, or text with one inside.
    private func sharedLink() async -> URL? {
        let providers =
            (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:)),
                Self.isWeb(url)
            {
                return url
            }
        }
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                let text = item as? String, let url = Self.firstLink(in: text)
            {
                return url
            }
        }
        return nil
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    private static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first(where: isWeb)
    }

    /// Opens the link through the extension context. A share sheet's context may decline,
    /// so the responder chain's application is asked next.
    private func open(_ link: URL) async {
        let opened = await withCheckedContinuation { continuation in
            extensionContext?.open(link) { continuation.resume(returning: $0) }
                ?? continuation.resume(returning: false)
        }
        if !opened { openThroughResponder(link) }
    }

    private func openThroughResponder(_ link: URL) {
        typealias Open =
            @convention(c) (
                AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], (@Sendable (Bool) -> Void)?
            ) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector),
                let implementation = current.method(for: selector)
            {
                unsafeBitCast(implementation, to: Open.self)(current, selector, link, [:], nil)
                return
            }
            responder = current.next
        }
    }
}
