import UIKit
import WebKit

/// What to do with a navigation a page asks for.
enum NavigationPolicy: Equatable {
    case allow
    case cancel
    /// Hand the address to the system, for the app that owns its scheme.
    case handOff
    /// A page asked for a window of its own: it opens as a new tab.
    case openInNewTab

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob"]

    /// Decides a navigation to `url`. Pages never reach data: or file: at the top level,
    /// and never Magpie's own schemes; another app's scheme opens only from a link the
    /// person tapped, never from a page load or redirect. A new window is a tab for a
    /// web address the person tapped; a script opening one on its own is a pop-up,
    /// and is dropped.
    static func decide(
        url: URL?, isMainFrame: Bool, isLinkActivation: Bool, isNewWindow: Bool = false
    ) -> NavigationPolicy {
        guard let scheme = url?.scheme?.lowercased() else { return .cancel }
        if isNewWindow, scheme == "http" || scheme == "https" {
            return isLinkActivation ? .openInNewTab : .cancel
        }
        if webSchemes.contains(scheme) { return .allow }
        if scheme == "data" || scheme == "file" { return isMainFrame ? .cancel : .allow }
        if scheme == "javascript" { return .allow }  // WebKit runs these in-page, never as a load.
        if scheme.hasPrefix("magpie") { return .cancel }
        return isLinkActivation ? .handOff : .cancel
    }
}

/// Where a page's downloads go, and a note that one was just handed over, so the
/// canceled load that follows is not shown as a page that failed.
@MainActor
final class PageDownloads {
    private let store: DownloadStore
    private let cookieStore: WKHTTPCookieStore?
    private var handedOverAt: Date?

    init(store: DownloadStore, cookieStore: WKHTTPCookieStore?) {
        self.store = store
        self.cookieStore = cookieStore
    }

    /// Takes a download from the page.
    func start(_ request: URLRequest, suggestedName: String?) {
        handedOverAt = .now
        store.start(DownloadJob(request: request, suggestedName: suggestedName), cookieStore: cookieStore)
    }

    /// Whether a load failure just now is the canceled load of a download; true once.
    func consumesFailure(now: Date = .now) -> Bool {
        defer { handedOverAt = nil }
        guard let handedOverAt else { return false }
        return now.timeIntervalSince(handedOverAt) < 3
    }
}

/// The reading page's navigation decider: applies `NavigationPolicy`, and turns what a
/// page cannot show into a download.
@MainActor
struct PageNavigationDecider: WebPage.NavigationDeciding {
    /// Whether another app's scheme may open at all; off for pages nobody sees.
    var allowsHandOff = true
    /// Whether a site loads its desktop version; the page's own address in, the choice out.
    var prefersDesktop: @MainActor (URL?) -> Bool = { _ in false }
    /// Where a new window's address goes: the owner opens it as a tab.
    var onNewWindow: @MainActor (URL) -> Void = { _ in }
    /// Where downloads go; nil for pages nobody sees, which never download.
    var downloads: PageDownloads?

    mutating func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        let url = action.request.url
        // A new window has no target frame.
        let isNewWindow = action.target == nil
        SnapshotLog.event(
            "nav type=\(action.navigationType.rawValue) newWindow=\(isNewWindow) "
                + "button=\(action.buttonNumber.rawValue)")
        let policy = NavigationPolicy.decide(
            url: url, isMainFrame: action.target?.isMainFrame ?? true,
            isLinkActivation: action.navigationType == .linkActivated,
            isNewWindow: isNewWindow)
        switch policy {
        case .allow:
            // A link with the download attribute. WebPage has no download delegate, so
            // the page's load is canceled and the file fetched on its own.
            if action.shouldPerformDownload, let downloads, Self.isWeb(url) {
                downloads.start(action.request, suggestedName: nil)
                return .cancel
            }
            if action.target?.isMainFrame ?? true {
                preferences.preferredContentMode = prefersDesktop(url) ? .desktop : .recommended
            }
            return .allow
        case .cancel:
            return .cancel
        case .openInNewTab:
            if let url { onNewWindow(url) }
            return .cancel
        case .handOff:
            if allowsHandOff, let url { _ = await UIApplication.shared.open(url) }
            return .cancel
        }
    }

    mutating func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard let downloads, let url = response.response.url, Self.isWeb(url) else { return .allow }
        let http = response.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")
        guard DownloadNaming.isAttachment(disposition: disposition) || !response.canShowMimeType
        else { return .allow }
        downloads.start(URLRequest(url: url), suggestedName: response.response.suggestedFilename)
        return .cancel
    }

    private static func isWeb(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
