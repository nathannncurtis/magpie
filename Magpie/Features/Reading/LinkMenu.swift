import SwiftUI
import UIKit
import WebKit

/// The long-press menu on a link. The page's SwiftUI view has no menu hook on iOS, so
/// this stands in front of the web view's own UI delegate: links get Magpie's menu over
/// the system's link preview, and everything else goes through to the delegate behind.
@MainActor
final class LinkMenuDelegate: NSObject, WKUIDelegate {

    /// Whether the page is private: its "Open in New Tab" stays private.
    var isPrivate = false
    /// Opens a link in a tab of its own; the flag asks for a private one.
    var onOpenLink: (URL, Bool) -> Void = { _, _ in }

    /// The delegate the page already had, still answering everything not handled here.
    /// Read from the forwarding hooks, which run off the main actor.
    nonisolated(unsafe) private weak var original: (any WKUIDelegate)?

    /// Stands in front of the web view's delegate, once.
    func install(on webView: WKWebView) {
        guard webView.uiDelegate !== self else { return }
        original = webView.uiDelegate
        SnapshotLog.event("link menu installed, delegate behind=\(original != nil)")
        webView.uiDelegate = self
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original as? NSObject)?.responds(to: selector) == true
    }

    func webView(
        _ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
    ) {
        guard let url = elementInfo.linkURL else {
            if let original {
                original.webView?(
                    webView, contextMenuConfigurationForElement: elementInfo,
                    completionHandler: completionHandler)
            } else {
                completionHandler(nil)
            }
            return
        }
        // No preview provider: the system's own link preview stays.
        completionHandler(
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self, weak webView] _ in
                self?.menu(for: url, from: webView)
            })
    }

    private func menu(for url: URL, from webView: WKWebView?) -> UIMenu {
        let open = UIAction(
            title: String(localized: "Open in New Tab"),
            image: UIImage(systemName: "plus.square.on.square")
        ) { [weak self] _ in
            guard let self else { return }
            onOpenLink(url, isPrivate)
        }
        let privately = UIAction(
            title: String(localized: "Open in Private Tab"),
            image: UIImage(systemName: "eye.slash")
        ) { [weak self] _ in self?.onOpenLink(url, true) }
        let copy = UIAction(
            title: String(localized: "Copy Link"),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in UIPasteboard.general.url = url }
        let share = UIAction(
            title: String(localized: "Share"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak webView] _ in Self.share(url, from: webView) }
        return UIMenu(children: [open, privately, copy, share])
    }

    /// The share sheet over the topmost screen, anchored on the page for a wide layout.
    private static func share(_ url: URL, from webView: WKWebView?) {
        guard var top = webView?.window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController, let webView {
            popover.sourceView = webView
            popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
