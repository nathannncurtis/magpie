import Foundation
import Testing

@testable import Magpie

@Suite("PageLoadFailure")
struct ReadingCopyTests {

    @Test("the title names the host")
    func title() {
        #expect(PageLoadFailure(host: "quietweb.org", isOffline: true).title == "Can't reach quietweb.org")
        #expect(PageLoadFailure(host: "", isOffline: true).title == "Can't reach this page")
    }

    @Test("offline says it will load when back")
    func offlineLine() {
        let failure = PageLoadFailure(host: "quietweb.org", isOffline: true)
        #expect(failure.line == "You're offline. It'll load when you're back.")
    }

    @Test("any other failure says the page did not answer")
    func otherLine() {
        let failure = PageLoadFailure(host: "quietweb.org", isOffline: false)
        #expect(failure.line == "It didn't answer. Try again in a moment.")
    }

    @Test("a failure names the host asked for, port stripped")
    func refusedHost() {
        let url = URL(string: "http://example.org:81/")
        let host = HostFormatter.host(for: url)
        #expect(host == "example.org")
        #expect(PageLoadFailure(host: host, isOffline: false).title == "Can't reach example.org")
    }
}
