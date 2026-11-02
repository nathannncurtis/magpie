import Foundation
import Testing

@testable import Magpie

@Suite("NavigationPolicy")
struct NavigationPolicyTests {

    private func decide(_ url: String, main: Bool = true, link: Bool = false) -> NavigationPolicy {
        NavigationPolicy.decide(url: URL(string: url), isMainFrame: main, isLinkActivation: link)
    }

    @Test("web pages load", arguments: ["https://example.com", "http://example.com", "about:blank"])
    func web(url: String) {
        #expect(decide(url) == .allow)
        #expect(decide(url, link: true) == .allow)
    }

    @Test(
        "pages never reach data: or file: at the top level",
        arguments: ["data:text/html,<h1>hi</h1>", "file:///etc/passwd"])
    func topLevelLocal(url: String) {
        #expect(decide(url) == .cancel)
        #expect(decide(url, link: true) == .cancel)
        #expect(decide(url, main: false) == .allow)
    }

    @Test(
        "other apps open only from a tapped link",
        arguments: ["tel:+15551234567", "mailto:a@b.c", "sms:123", "maps:?q=x", "itms-apps://x", "someapp://y"])
    func handOff(url: String) {
        #expect(decide(url, link: true) == .handOff)
        #expect(decide(url) == .cancel)
        #expect(decide(url, main: false) == .cancel)
    }

    @Test("pages never reach Magpie's own schemes")
    func internalSchemes() {
        #expect(decide("magpie-cite://1", link: true) == .cancel)
        #expect(decide("magpie://settings", link: true) == .cancel)
    }

    @Test("an address with no scheme is refused")
    func noScheme() {
        #expect(NavigationPolicy.decide(url: nil, isMainFrame: true, isLinkActivation: true) == .cancel)
    }
}

@Suite("NavigationPolicy new windows")
struct NavigationPolicyNewWindowTests {

    private func decide(_ url: String, tapped: Bool) -> NavigationPolicy {
        NavigationPolicy.decide(
            url: URL(string: url), isMainFrame: true, isLinkActivation: tapped, isNewWindow: true)
    }

    @Test("a tapped web link in a new window opens a tab", arguments: ["https://example.com", "http://example.com/a"])
    func tapped(url: String) {
        #expect(decide(url, tapped: true) == .openInNewTab)
    }

    @Test("a window nobody tapped for is a pop-up and is dropped")
    func popUp() {
        #expect(decide("https://example.com", tapped: false) == .cancel)
    }

    @Test("a blank new window is not opened")
    func blank() {
        #expect(decide("about:blank", tapped: true) == .allow)
    }

    @Test("another app's scheme still hands off from a tapped new-window link")
    func handOff() {
        #expect(decide("tel:+15551234567", tapped: true) == .handOff)
        #expect(decide("tel:+15551234567", tapped: false) == .cancel)
    }
}
