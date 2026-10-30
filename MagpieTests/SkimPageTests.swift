import Foundation
import Testing

@testable import Magpie

/// The finished page itself: its photo tiers, its share page, and its store.
@Suite("SkimPage")
struct SkimPageTests {

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    private func source(_ index: Int, photo: Bool) -> SkimSourceRef {
        SkimSourceRef(
            url: url("https://host\(index).example/page"),
            title: "Source \(index)",
            host: "host\(index).example",
            faviconURL: nil,
            imageURL: photo ? url("https://host\(index).example/photo\(index).jpg") : nil)
    }

    private func page(photoCount: Int, sources: Int = 3) -> SkimPage {
        SkimPage(
            query: "seasoning carbon steel",
            title: "Seasoning carbon steel",
            sections: [
                SkimSection(
                    emoji: "🔥", term: "Method",
                    claim: "Wipe on a thin coat of oil, then heat it.", citations: [1, 3])
            ],
            sources: (0..<sources).map { source($0, photo: $0 < photoCount) })
    }

    // MARK: Photos

    @Test("the header tiers by photo count, capped at three")
    func photoTiers() {
        #expect(page(photoCount: 3).photoTier == .mosaic)
        #expect(page(photoCount: 5).photoTier == .mosaic)
        #expect(page(photoCount: 5).photoURLs.count == 3)
        #expect(page(photoCount: 1).photoTier == .hero)
        #expect(page(photoCount: 0).photoTier == .none)
    }

    @Test("digging deeper stops at ten sources")
    func digDeeperCeiling() {
        #expect(page(photoCount: 0).canDigDeeper)
        #expect(!page(photoCount: 0, sources: 10).canDigDeeper)
    }

    // MARK: The share page

    @Test("the share page carries the title, the from-line, and the sources")
    func sharePageCarriesThePage() {
        let html = page(photoCount: 0).exportHTML()

        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("<h1>Seasoning carbon steel</h1>"))
        #expect(html.contains(SkimPage.fromLine(count: 3)))
        #expect(html.contains("read on this phone"))
        #expect(html.contains("<a href=\"https://host0.example/page\">"))
        #expect(html.contains("<span class=\"host\">1 · host0.example</span>"))
    }

    @Test("each point carries its citation chips")
    func sharePageChipsItsPoints() {
        let html = page(photoCount: 0).exportHTML()

        #expect(html.contains("<li><b>Method</b> — Wipe on a thin coat of oil, then heat it."))
        #expect(html.contains("<span class=\"n\">1</span><span class=\"n\">3</span></li>"))
    }

    @Test("markup in the page's text is escaped")
    func sharePageEscapes() {
        let loud = SkimPage(
            query: "seasoning", title: #"Pan & "cast" <iron>"#,
            sections: [], sources: [])
        let html = loud.exportHTML()

        #expect(html.contains("<h1>Pan &amp; &quot;cast&quot; &lt;iron&gt;</h1>"))
        #expect(!html.contains(#"<h1>Pan & "cast" <iron></h1>"#))
    }

    @Test("photos are linked until their bytes are in hand")
    func sharePagePhotos() {
        let linked = page(photoCount: 2).exportHTML()
        #expect(linked.components(separatedBy: "<img class=\"photo\"").count == 3)
        #expect(linked.contains("src=\"https://host0.example/photo0.jpg\""))

        let page = page(photoCount: 2)
        let bytes: [URL: Data] = [
            page.photoURLs[0]: Data([0x89, 0x50, 0x4E, 0x47]),
            page.photoURLs[1]: Data([0x00]),  // not a picture
        ]
        let embedded = page.exportHTML(photoData: bytes)
        #expect(embedded.contains("src=\"data:image/png;base64,"))
        #expect(embedded.contains("src=\"https://host1.example/photo1.jpg\""))
    }

    // MARK: The store

    @Test("a saved page comes back whole")
    func storeRoundTrip() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skim-store-tests", isDirectory: true)
        let store = SkimPageStore(directory: directory)
        let id = UUID()
        let page = page(photoCount: 2)

        #expect(store.save(page, id: id))
        #expect(store.load(id: id) == page)
        #expect(store.load(id: UUID()) == nil)
    }

    @Test("a bookmark address points at its page, and only that")
    func bookmarkAddresses() {
        let id = UUID()

        #expect(SkimPageStore.address(forID: id) == url("magpie://skim/\(id.uuidString)"))
        #expect(SkimPageStore.pageID(forBookmarkURL: SkimPageStore.address(forID: id)!) == id)
        #expect(SkimPageStore.pageID(forBookmarkURL: url("https://host0.example/page")) == nil)
        #expect(SkimPageStore.pageID(forBookmarkURL: url("magpie://other/\(id.uuidString)")) == nil)
        #expect(SkimPageStore.pageID(forBookmarkURL: url("magpie://skim/not-a-uuid")) == nil)
    }
}
