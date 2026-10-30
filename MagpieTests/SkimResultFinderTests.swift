import Foundation
import Testing

@testable import Magpie

/// The results-page link filter, on handwritten HTML in the results endpoint's
/// shape: organic links kept in order, ads and the engine's own pages dropped.
@Suite("ResultFinder")
struct SkimResultFinderTests {

    private let base = ResultFinder.searchURL
    private let engineHosts = ResultFinder.engineHosts

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    private func links(_ html: String) -> [URL] {
        OrganicLinkFilter.links(
            from: AnchorScan.anchors(inHTML: html), base: base, engineHosts: engineHosts)
    }

    // MARK: Anchor scan

    @Test("anchors carry their href and class, quoted or not")
    func anchorsReadAttributes() {
        let html = #"""
            <a class="result__a" href="https://a.example/one">One</a>
            <a href='https://b.example/two' class='result'>Two</a>
            <a href=https://c.example/three>Three</a>
            <a>Four</a>
            """#
        let anchors = AnchorScan.anchors(inHTML: html)

        #expect(
            anchors == [
                RawAnchor(href: "https://a.example/one", className: "result__a"),
                RawAnchor(href: "https://b.example/two", className: "result"),
                RawAnchor(href: "https://c.example/three", className: ""),
                RawAnchor(href: "", className: ""),
            ])
    }

    // MARK: Filtering

    @Test("a results page keeps its organic links in order")
    func organicLinksSurvive() {
        let html = #"""
            <div class="result">
              <h2><a class="result__a" href="https://kitchen.example/seasoning">Seasoning</a></h2>
              <a href="https://pans.example/care">Care</a>
              <a href="https://stoves.example/heat">Heat</a>
            </div>
            """#
        let found = links(html)

        #expect(
            found == [
                url("https://kitchen.example/seasoning"),
                url("https://pans.example/care"),
                url("https://stoves.example/heat"),
            ])
    }

    @Test("ads and sponsored placements are dropped")
    func adsDrop() {
        let html = #"""
            <a class="result--ad" href="https://shop.example/ad">Ad</a>
            <a class="result result--paid" href="https://shop.example/paid">Paid</a>
            <a class="badge-sponsored" href="https://shop.example/sponsored">Sponsored</a>
            <a class="result__a" href="https://kitchen.example/real">Real</a>
            """#

        #expect(links(html) == [url("https://kitchen.example/real")])
    }

    @Test("the engine's own pages and verticals are dropped")
    func enginePagesDrop() {
        let html = #"""
            <a href="https://duckduckgo.com/?q=seasoning">The engine itself</a>
            <a href="https://images.duckduckgo.com/seasoning.jpg">Its images</a>
            <a href="https://html.duckduckgo.com/html/?q=seasoning">Its HTML page</a>
            <a href="https://kitchen.example/real">Real</a>
            """#

        #expect(links(html) == [url("https://kitchen.example/real")])
    }

    @Test("redirect links are unwrapped to their target")
    func redirectsUnwrap() {
        let html = #"""
            <a href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fkitchen.example%2Fseasoning&amp;k1=-1">One</a>
            <a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fpans.example%2Fcare&amp;rut=abc">Two</a>
            <a href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fstoves.example%2Fheat%3Fkind%3Dgas">Three</a>
            <a href="https://duckduckgo.com/l/?yt=other">A redirect to nowhere</a>
            """#
        let found = links(html)

        #expect(
            found == [
                url("https://kitchen.example/seasoning"),
                url("https://pans.example/care"),
                url("https://stoves.example/heat?kind=gas"),
            ])
    }

    @Test("PDFs and non-web links are dropped")
    func unusableLinksDrop() {
        let html = #"""
            <a href="https://docs.example/manual.pdf">A PDF</a>
            <a href="https://docs.example/guide.PDF">A PDF, shouted</a>
            <a href="mailto:hello@example.com">Mail</a>
            <a href="javascript:void(0)">A script</a>
            <a href="https://kitchen.example/real">Real</a>
            """#

        #expect(links(html) == [url("https://kitchen.example/real")])
    }

    @Test("a link seen twice counts once")
    func duplicatesCollapse() {
        let html = #"""
            <a href="https://kitchen.example/seasoning">Once</a>
            <a href="https://kitchen.example/seasoning">Again</a>
            <a href="https://kitchen.example/seasoning#top">Again, at a fragment</a>
            <a href="https://pans.example/care">Another</a>
            """#

        #expect(
            links(html) == [
                url("https://kitchen.example/seasoning"),
                url("https://pans.example/care"),
            ])
    }

    @Test("one page, the shape of it all")
    func wholePage() {
        let html = #"""
            <html><body>
            <div class="nav"><a href="https://duckduckgo.com/about">About</a></div>
            <div class="results">
              <div class="result result--ad"><a class="result__a" href="https://ads.example/1">Ad one</a></div>
              <div class="result">
                <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fkitchen.example%2Fseasoning&amp;rut=1">
                  How to season a pan
                </a>
              </div>
              <div class="result">
                <a class="result__a" href="https://pans.example/mineral-b">Mineral B, cared for</a>
              </div>
              <div class="result">
                <a class="result__a" href="https://stoves.example/heat-guide.pdf">Heat, as a PDF</a>
              </div>
              <div class="result">
                <a class="result__a" href="https://kitchen.example/seasoning">Seasoning, again</a>
              </div>
            </div>
            </body></html>
            """#

        #expect(
            links(html) == [
                url("https://kitchen.example/seasoning"),
                url("https://pans.example/mineral-b"),
            ])
    }

    // MARK: Pieces

    @Test("an ad class is spotted among the others")
    func adClasses() {
        #expect(OrganicLinkFilter.isAdClassed("result--ad result__a"))
        #expect(OrganicLinkFilter.isAdClassed("result--paid-link"))
        #expect(OrganicLinkFilter.isAdClassed("AD"))
        #expect(OrganicLinkFilter.isAdClassed("x-sponsored-x"))
        #expect(!OrganicLinkFilter.isAdClassed("result__a"))
        #expect(!OrganicLinkFilter.isAdClassed(""))
    }

    @Test("the engine's host and its subdomains are the engine")
    func engineHostMatching() {
        #expect(OrganicLinkFilter.hostIsEngine("duckduckgo.com", engineHosts: engineHosts))
        #expect(OrganicLinkFilter.hostIsEngine("images.duckduckgo.com", engineHosts: engineHosts))
        #expect(!OrganicLinkFilter.hostIsEngine("notduckduckgo.com", engineHosts: engineHosts))
        #expect(!OrganicLinkFilter.hostIsEngine("example.com", engineHosts: engineHosts))
    }

    @Test("Skim reads the HTML endpoint whatever the engine is set to")
    func searchEndpoint() {
        #expect(ResultFinder.searchURL.host == "html.duckduckgo.com")
        #expect(ResultFinder.htmlScript.contains("document.body"))
    }
}
