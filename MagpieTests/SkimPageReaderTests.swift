import Foundation
import Testing

@testable import Magpie

/// Choosing the readable article out of a page's candidate blocks: the largest
/// text-dense block wins, chrome loses, and the text is capped at its last
/// sentence end.
@Suite("PageReader")
struct SkimPageReaderTests {

    private let url = URL(string: "https://kitchen.example/seasoning")!

    private func text(_ length: Int) -> String {
        String(repeating: "a", count: length)
    }

    private func block(
        _ text: String, id: String? = nil, cls: String? = nil, links: Int = 0,
        headings: Int = 0, lists: Int = 0
    ) -> PagePayload.Block {
        PagePayload.Block(
            tag: "div", id: id, cls: cls, text: text, links: links, headings: headings,
            lists: lists)
    }

    // MARK: Candidates

    @Test("short blocks and link swamps are not candidates")
    func weakBlocksReject() {
        #expect(ArticleSelection.scored(block(text(299))) == nil)
        #expect(ArticleSelection.scored(block(text(300))) != nil)

        // Three quarters of the block's characters sit inside links.
        #expect(ArticleSelection.scored(block(text(400), links: 301)) == nil)
        #expect(ArticleSelection.scored(block(text(400), links: 160)) != nil)
    }

    @Test("chrome scores a quarter of its length")
    func chromeIsPenalised() {
        let plain = ArticleSelection.scored(block(text(400)))!.1
        let chrome = ArticleSelection.scored(block(text(400), cls: "site-footer"))!.1

        #expect(chrome == plain * 0.25)
    }

    @Test("headings and lists add to a block's score")
    func structureAdds() {
        let bare = ArticleSelection.scored(block(text(400)))!.1
        let structured = ArticleSelection.scored(block(text(400), headings: 2, lists: 1))!.1

        #expect(structured == bare + 2 * 120 + 80)
    }

    // MARK: Picking

    @Test("the article beats a longer stretch of chrome")
    func articleWinsOverChrome() {
        let payload = PagePayload(
            title: "", pageTitle: nil, site: nil, favicon: nil, image: nil,
            blocks: [
                block(text(500), id: "related-sidebar"),
                block(text(350)),
            ])

        let read = ArticleSelection.pick(payload: payload, url: url)

        #expect(read?.text == text(350))
    }

    @Test("the page's facts come back, with the host as the fallback")
    func factsComeBack() {
        let payload = PagePayload(
            title: "The document title",
            pageTitle: "The shared title",
            site: "Kitchen",
            favicon: "https://kitchen.example/icon.png",
            image: "https://kitchen.example/photo.jpg",
            blocks: [block(text(400))])

        let read = ArticleSelection.pick(payload: payload, url: url)

        #expect(read?.title == "The shared title")
        #expect(read?.siteName == "Kitchen")
        #expect(read?.faviconURL == URL(string: "https://kitchen.example/icon.png"))
        #expect(read?.imageURL == URL(string: "https://kitchen.example/photo.jpg"))
        #expect(read?.host == "kitchen.example")
    }

    @Test("a page with no facts falls back to its host and title")
    func fallsBackToHost() {
        let payload = PagePayload(
            title: "The document title", pageTitle: " ", site: "", favicon: "", image: "",
            blocks: [block(text(400))])

        let read = ArticleSelection.pick(payload: payload, url: url)

        #expect(read?.title == "The document title")
        #expect(read?.siteName == "kitchen.example")
        #expect(read?.faviconURL == nil)
        #expect(read?.imageURL == nil)
    }

    @Test("a page with no readable block cannot be read")
    func noBlocksMeansNoPage() {
        let payload = PagePayload(
            title: "The document title", pageTitle: nil, site: nil, favicon: nil, image: nil,
            blocks: [])

        #expect(ArticleSelection.pick(payload: payload, url: url) == nil)
    }

    // MARK: Capping

    @Test("long text stops at its cap, on a sentence end")
    func longTextCaps() {
        let sentence = "Seasoning builds up in thin layers over time. "
        let long = String(repeating: sentence, count: 220)  // about 11,000 characters
        let capped = ArticleSelection.capped(long)

        #expect(capped.count <= ArticleSelection.maxTextLength)
        #expect(capped.hasSuffix("."))
        #expect(capped.count >= ArticleSelection.maxTextLength - 400)
    }

    @Test("whitespace runs collapse into single lines")
    func whitespaceCollapses() {
        let squashed = ArticleSelection.capped("One.\n\n   Two.\n\t\nThree.\n\n\n")

        #expect(squashed == "One.\nTwo.\nThree.")
    }

    @Test("text under the cap passes through whole")
    func shortTextPasses() {
        let short = "One line here.\nAnother there."

        #expect(ArticleSelection.capped(short) == short)
    }

    // MARK: Script

    @Test("the extraction script reports facts, blocks, and their shape")
    func extractionScriptShape() {
        let script = PageReader.extractionScript

        #expect(script.contains("og:image"))
        #expect(script.contains("naturalWidth"))
        #expect(script.contains("innerText"))
        #expect(script.contains("JSON.stringify"))
        #expect(script.contains("slice(0, 8)"))
    }
}
