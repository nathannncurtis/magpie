import Testing
import WebKit

@testable import Magpie

@MainActor
struct PageConfigurationTests {

    @Test func pagesPlayVideoInline() {
        #expect(WebPage.Configuration.browser().mediaPlaybackBehavior == .allowsInlinePlayback)
    }

    @Test func modPagesKeepTheBrowserSettings() {
        let configuration = ModInjector().pageConfiguration()
        #expect(configuration.mediaPlaybackBehavior == .allowsInlinePlayback)
        #expect(configuration.upgradeKnownHostsToHTTPS)
    }

    @Test func userAgentNamesTheOSRelease() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        #expect(WebPage.Configuration.userAgentSuffix.hasPrefix("Version/\(major).0 "))
        #expect(WebPage.Configuration.userAgentSuffix.hasSuffix("Safari/604.1"))
    }
}
