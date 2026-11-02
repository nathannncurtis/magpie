import Foundation
import WebKit

extension WebPage.Configuration {

    /// The settings every page Magpie shows starts from, whichever path builds it.
    static func browser() -> WebPage.Configuration {
        var configuration = WebPage.Configuration()
        // A page's videos play where they sit; a clip in a page never jumps into the
        // full-screen player on its own. The page's own full-screen button still works.
        configuration.mediaPlaybackBehavior = .allowsInlinePlayback
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.applicationNameForUserAgent = userAgentSuffix
        return configuration
    }

    /// The tail of the user agent: the system's mobile build plus the version and engine
    /// marks sites look for before serving their full mobile page, matching the OS release.
    static var userAgentSuffix: String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }
}
