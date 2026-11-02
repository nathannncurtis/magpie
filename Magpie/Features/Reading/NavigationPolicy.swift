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

/// The reading page's navigation decider: applies `NavigationPolicy`.
@MainActor
struct PageNavigationDecider: WebPage.NavigationDeciding {
    /// Whether another app's scheme may open at all; off for pages nobody sees.
    var allowsHandOff = true
    /// Whether a site loads its desktop version; the page's own address in, the choice out.
    var prefersDesktop: @MainActor (URL?) -> Bool = { _ in false }
    /// Where a new window's address goes: the owner opens it as a tab.
    var onNewWindow: @MainActor (URL) -> Void = { _ in }

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
}
