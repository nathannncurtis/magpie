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

/// The reading page's navigation decider: applies `NavigationPolicy`.
@MainActor
struct PageNavigationDecider: WebPage.NavigationDeciding {
    /// Whether another app's scheme may open at all; off for pages nobody sees.
    var allowsHandOff = true

    mutating func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        let url = action.request.url
        let policy = NavigationPolicy.decide(
            url: url, isMainFrame: action.target?.isMainFrame ?? true,
            isLinkActivation: action.navigationType == .linkActivated)
        switch policy {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .handOff:
            if allowsHandOff, let url { _ = await UIApplication.shared.open(url) }
            return .cancel
        }
    }
}
