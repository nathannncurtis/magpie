import UIKit
import WebKit

/// What to do with a navigation a page asks for.
enum NavigationPolicy: Equatable {
    case allow
    case cancel
    /// Hand the address to the system, for the app that owns its scheme.
    case handOff

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob"]

    /// Decides a navigation to `url`. Pages never reach data: or file: at the top level,
    /// and never Magpie's own schemes; another app's scheme opens only from a link the
    /// person tapped, never from a page load or redirect.
    static func decide(url: URL?, isMainFrame: Bool, isLinkActivation: Bool) -> NavigationPolicy {
        guard let scheme = url?.scheme?.lowercased() else { return .cancel }
        if webSchemes.contains(scheme) { return .allow }
        if scheme == "data" || scheme == "file" { return isMainFrame ? .cancel : .allow }
        if scheme == "javascript" { return .allow }  // WebKit runs these in-page, never as a load.
        if scheme.hasPrefix("magpie") { return .cancel }
        return isLinkActivation ? .handOff : .cancel
    }
}

/// Where a page's downloads go, and a note that one was just handed over, so the
/// cancelled load that follows is not shown as a page that failed.
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

    /// Whether a load failure just now is the cancelled load of a download; true once.
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
    /// Where downloads go; nil for pages nobody sees, which never download.
    var downloads: PageDownloads?

    mutating func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        let url = action.request.url
        let policy = NavigationPolicy.decide(
            url: url, isMainFrame: action.target?.isMainFrame ?? true,
            isLinkActivation: action.navigationType == .linkActivated)
        switch policy {
        case .allow:
            // A link with the download attribute. WebPage has no download delegate, so
            // the page's load is cancelled and the file fetched on its own.
            if action.shouldPerformDownload, let downloads, Self.isWeb(url) {
                downloads.start(action.request, suggestedName: nil)
                return .cancel
            }
            return .allow
        case .cancel:
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
