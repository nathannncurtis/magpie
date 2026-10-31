import Foundation

/// What one source page yielded: its identity, its photo, and its readable text.
struct ReadPage: Equatable, Sendable {
    var url: URL
    var title: String
    var siteName: String
    var faviconURL: URL?
    var imageURL: URL?
    var text: String

    var host: String { HostFormatter.host(for: url) }
}

/// The page facts the extraction script reports back.
struct PagePayload: Equatable, Decodable, Sendable {

    struct Block: Equatable, Decodable, Sendable {
        var tag: String
        var id: String?
        var cls: String?
        var text: String
        var links: Int
        var headings: Int
        var lists: Int
    }

    var title: String
    var pageTitle: String?
    var site: String?
    var favicon: String?
    var image: String?
    var blocks: [Block]
}

/// Picks the readable article out of a page's blocks: the largest text-dense
/// block wins; chrome around it loses. Pure, so it is tested on fixtures.
enum ArticleSelection {

    static let minTextLength = 300
    static let maxTextLength = 8_000
    static let maxLinkDensity = 0.4

    /// Hints that a block is the page's chrome rather than its content.
    private static let chromeHints = [
        "nav", "menu", "header", "footer", "sidebar", "aside", "comment",
        "promo", "related", "share", "social", "subscribe", "newsletter",
    ]

    static func pick(payload: PagePayload, url: URL) -> ReadPage? {
        guard let best = payload.blocks.map(scored).compactMap(\.self).max(by: { $0.1 < $1.1 }) else {
            return nil
        }
        let block = best.0
        let host = HostFormatter.host(for: url)
        return ReadPage(
            url: url,
            title: nonEmpty(payload.pageTitle) ?? nonEmpty(payload.title) ?? host,
            siteName: nonEmpty(payload.site) ?? host,
            faviconURL: payload.favicon.flatMap(URL.init(string:)),
            imageURL: payload.image.flatMap(URL.init(string:)),
            text: capped(block.text))
    }

    /// The block's score, or nil when the block is not a readable candidate.
    static func scored(_ block: PagePayload.Block) -> (PagePayload.Block, Double)? {
        let length = Double(block.text.count)
        guard length >= Double(minTextLength) else { return nil }
        let density = length > 0 ? Double(block.links) / length : 1
        guard density <= maxLinkDensity else { return nil }
        var score = length * (1 - density)
        score += Double(block.headings) * 120
        score += Double(block.lists) * 80
        if isChrome(block) { score *= 0.25 }
        return (block, score)
    }

    private static func isChrome(_ block: PagePayload.Block) -> Bool {
        let words = ((block.id ?? "") + " " + (block.cls ?? "")).lowercased()
        return chromeHints.contains { words.contains($0) }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps the text tight: runs of whitespace collapse, and anything past the
    /// cap ends at its last sentence end.
    static func capped(_ text: String) -> String {
        var out = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard out.count > maxTextLength else { return out }
        let cut = out.index(out.startIndex, offsetBy: maxTextLength)
        let head = out[..<cut]
        let window = head.index(cut, offsetBy: -400, limitedBy: head.startIndex) ?? head.startIndex
        let enders: Set<Character> = [".", "!", "?"]
        if let end = head[window...].lastIndex(where: { enders.contains($0) }) {
            out = String(head[...end])
        } else {
            out = String(head)
        }
        return out
    }
}

/// What a Skim run uses to read a source page.
protocol PageReading: Sendable {
    /// One page's readable article, or nil when the page cannot be read.
    func read(_ url: URL) async -> ReadPage?
}

/// Reads a source page offscreen: load it, pull its candidate blocks out with a
/// script, and let the selection score them.
struct PageReader: PageReading {

    var timeout: TimeInterval = 12

    func read(_ url: URL) async -> ReadPage? {
        guard
            let json = await OffscreenPage.load(
                url: url, timeout: timeout, script: Self.extractionScript),
            let data = json.data(using: .utf8),
            let payload = try? JSONDecoder().decode(PagePayload.self, from: data)
        else { return nil }
        return ArticleSelection.pick(payload: payload, url: url)
    }

    /// Collects the page's facts and its text-densest candidate blocks. Parent
    /// blocks are taken before their children, so nested duplicates never score.
    static let extractionScript = #"""
        (() => {
            const meta = (sel) => {
                const el = document.querySelector(sel);
                return el ? (el.content || "").trim() : "";
            };
            let image = meta("meta[property='og:image']") || meta("meta[name='twitter:image']");
            if (!image) {
                let best = 0;
                for (const el of document.images) {
                    const w = el.naturalWidth || el.width, h = el.naturalHeight || el.height;
                    if (w >= 200 && h >= 150 && w * h > best) {
                        best = w * h;
                        image = el.currentSrc || el.src;
                    }
                }
            }
            const icon = document.querySelector("link[rel~='icon']")
                || document.querySelector("link[rel='apple-touch-icon']");
            const blocks = [];
            const taken = new Set();
            for (const el of document.querySelectorAll("article, main, [role='main'], div, section, td")) {
                if (taken.has(el)) continue;
                const text = (el.innerText || "").trim();
                if (text.length < 200) continue;
                let linked = 0;
                for (const a of el.querySelectorAll("a")) linked += (a.innerText || "").trim().length;
                blocks.push({
                    tag: el.tagName,
                    id: el.id || "",
                    cls: typeof el.className === "string" ? el.className : "",
                    text: text.slice(0, 12000),
                    links: linked,
                    headings: el.querySelectorAll("h1,h2,h3").length,
                    lists: el.querySelectorAll("ul,ol").length
                });
                for (const child of el.querySelectorAll("*")) taken.add(child);
            }
            blocks.sort((a, b) => b.text.length - a.text.length);
            return JSON.stringify({
                title: document.title || "",
                pageTitle: meta("meta[property='og:title']"),
                site: meta("meta[property='og:site_name']"),
                favicon: icon ? icon.href : "",
                image: image || "",
                blocks: blocks.slice(0, 8)
            });
        })()
        """#
}
