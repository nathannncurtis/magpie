import Foundation
import Testing

@testable import Magpie

/// Which open tab already shows a bookmark's page, so a second tap switches to it.
@Suite("TabMatch")
struct TabMatchTests {

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    private func tab(_ address: String, isPrivate: Bool = false, archived: Bool = false) -> Tab {
        Tab(
            url: url(address), lastActive: Date(timeIntervalSince1970: 0),
            archivedAt: archived ? Date(timeIntervalSince1970: 1) : nil, isPrivate: isPrivate)
    }

    private func match(_ address: String, in tabs: [Tab], isPrivate: Bool = false) -> Tab.ID? {
        TabMatch.existingTab(for: url(address), in: tabs, isPrivate: isPrivate)
    }

    @Test("the same address matches")
    func sameAddress() {
        let open = tab("https://quietweb.org/slow")
        #expect(match("https://quietweb.org/slow", in: [open]) == open.id)
    }

    @Test("a fragment and a trailing slash don't tell pages apart")
    func fragmentAndSlash() {
        let open = tab("https://quietweb.org/slow/#part-two")
        #expect(match("https://quietweb.org/slow", in: [open]) == open.id)
        let root = tab("https://quietweb.org")
        #expect(match("https://quietweb.org/", in: [root]) == root.id)
    }

    @Test("scheme and host compare without case")
    func caseInsensitiveHost() {
        let open = tab("HTTPS://QuietWeb.org/slow")
        #expect(match("https://quietweb.org/slow", in: [open]) == open.id)
    }

    @Test("a different path or query is a different page")
    func pathAndQueryCount() {
        let open = tab("https://quietweb.org/slow?page=1")
        #expect(match("https://quietweb.org/slow?page=2", in: [open]) == nil)
        #expect(match("https://quietweb.org/slow", in: [open]) == nil)
        #expect(match("https://quietweb.org/fast?page=1", in: [open]) == nil)
        #expect(match("http://quietweb.org/slow?page=1", in: [open]) == nil)
    }

    @Test("private tabs and ordinary tabs don't match across modes")
    func modesStayApart() {
        let ordinary = tab("https://a.example/x")
        let hidden = tab("https://a.example/x", isPrivate: true)
        #expect(match("https://a.example/x", in: [ordinary, hidden]) == ordinary.id)
        #expect(match("https://a.example/x", in: [ordinary, hidden], isPrivate: true) == hidden.id)
        #expect(match("https://a.example/x", in: [ordinary], isPrivate: true) == nil)
    }

    @Test("an archived tab never matches")
    func archivedIgnored() {
        #expect(match("https://a.example/x", in: [tab("https://a.example/x", archived: true)]) == nil)
    }

    @Test("a tab with no page yet never matches")
    func blankTab() {
        let blank = Tab(lastActive: Date(timeIntervalSince1970: 0))
        #expect(match("https://a.example/x", in: [blank]) == nil)
    }

    @Test("the current tab wins a tie, otherwise the first in the stack")
    func ties() {
        let first = tab("https://a.example/x")
        let second = tab("https://a.example/x#top")
        #expect(match("https://a.example/x", in: [first, second]) == first.id)
        let current = TabMatch.existingTab(
            for: url("https://a.example/x"), in: [first, second], isPrivate: false,
            current: second.id)
        #expect(current == second.id)
    }
}
