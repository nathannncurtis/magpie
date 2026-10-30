import Foundation

/// One point on a Skim page: an emoji, a bold term, the claim, and the 1-based
/// numbers of the sources that back it.
struct SkimSection: Equatable, Codable, Identifiable, Sendable {

    var emoji: String
    var term: String
    var claim: String
    var citations: [Int]

    var id: String { term + "\u{0}" + claim }
}

/// One source a Skim page was built from. Its number is its index + 1.
struct SkimSourceRef: Equatable, Codable, Identifiable, Sendable {

    var url: URL
    var title: String
    var host: String
    var faviconURL: URL?
    var imageURL: URL?

    var id: String { url.absoluteString }
}

/// A finished Skim page. Only complete pages exist; a run that cannot build one
/// fails instead.
struct SkimPage: Equatable, Codable, Sendable {

    static let initialSourceCount = 3
    static let maxSources = 10

    var query: String
    var title: String
    var sections: [SkimSection]
    var sources: [SkimSourceRef]

    /// The photos the header shows: the sources' own images, in source order,
    /// capped at three. Never an image-search result.
    var photoURLs: [URL] {
        Array(sources.compactMap(\.imageURL).prefix(3))
    }

    /// The header tier: a photo mosaic with three or more photos, a single hero
    /// with one or two, mist with none.
    var photoTier: PhotoTier {
        switch photoURLs.count {
        case 3...: .mosaic
        case 1...2: .hero
        default: .none
        }
    }

    enum PhotoTier: Equatable, Sendable {
        case mosaic
        case hero
        case none
    }

    /// Whether "Dig deeper" still has unread results to go to; the control hides
    /// once the page is built from ten sources.
    var canDigDeeper: Bool { sources.count < Self.maxSources }
}

// MARK: - Share

extension SkimPage {

    /// A self-contained page to hand to the share sheet: one file, inline CSS,
    /// the photos embedded when their bytes were fetched (`photoData`), linked
    /// when not, and the sources listed with their links.
    func exportHTML(photoData: [URL: Data] = [:]) -> String {
        var out = #"""
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\#(escaping(title))</title>
            <style>
            body { margin: 0; font: 16px/1.55 -apple-system, sans-serif; background: #F7F6F2; color: #2B2D33; }
            @media (prefers-color-scheme: dark) { body { background: #121316; color: #C4C6CB; } }
            header { padding: 28px 22px 4px; }
            h1 { margin: 0 0 10px; font-size: 30px; line-height: 1.08; }
            .from { font-size: 13.5px; opacity: .62; }
            .photo { display: block; width: 100%; height: auto; margin-top: 16px; border-radius: 14px; }
            ul { list-style: none; margin: 20px 0 0; padding: 0 22px 26px; }
            li { margin: 14px 0; }
            b { font-weight: 650; }
            .n { display: inline-block; min-width: 15px; padding: 0 3px; margin: 0 2px 0 4px; border-radius: 8px;
                 background: linear-gradient(150deg, #14B8A6, #34D399 55%, #A7F3D0); color: #fff;
                 font-size: 10.5px; font-weight: 650; text-align: center; }
            .sources { padding: 0 22px 34px; }
            .sources h2 { font-size: 15px; }
            ol { list-style: none; margin: 0; padding: 0; }
            ol a { display: block; margin: 10px 0; padding: 12px 14px; border-radius: 12px;
                   background: #FFFFFF; color: #1B1C21; text-decoration: none; }
            @media (prefers-color-scheme: dark) { ol a { background: #1C1D21; color: #E6E6E2; } }
            .host { font-size: 12px; opacity: .6; }
            </style>
            </head>
            <body>
            <header>
            <h1>\#(escaping(title))</h1>
            <p class="from">\#(escaping(Self.fromLine(count: sources.count)))</p>
            </header>
            """#

        for photo in photoURLs {
            if let data = photoData[photo], let uri = Self.dataURI(data) {
                out += "\n<img class=\"photo\" src=\"" + uri + "\" alt=\"\">"
            } else {
                out += "\n<img class=\"photo\" src=\"" + escaping(photo.absoluteString) + "\" alt=\"\">"
            }
        }

        out += "\n<ul>"
        for section in sections {
            out += "\n<li><b>" + escaping(section.term) + "</b> — "
            out += escaping(section.claim)
            for citation in section.citations {
                out += "<span class=\"n\">\(citation)</span>"
            }
            out += "</li>"
        }
        out += "\n</ul>"

        out += "\n<section class=\"sources\">\n<h2>" + escaping(String(localized: "Sources")) + "</h2>\n<ol>"
        for (index, source) in sources.enumerated() {
            out += "\n<li><a href=\"" + escaping(source.url.absoluteString) + "\">"
            out += "<span class=\"host\">" + escaping("\(index + 1) · \(source.host)") + "</span><br>"
            out += escaping(source.title) + "</a></li>"
        }
        out += "\n</ol>\n</section>\n</body>\n</html>"
        return out
    }

    static func fromLine(count: Int) -> String {
        String(localized: "From \(count) pages · read on this phone")
    }

    private static func dataURI(_ data: Data) -> String? {
        guard let mime = data.first.flatMap(Self.mimeType(forByte:)) else { return nil }
        return "data:" + mime + ";base64," + data.base64EncodedString()
    }

    private static func mimeType(forByte byte: UInt8) -> String? {
        switch byte {
        case 0x89: "image/png"
        case 0xFF: "image/jpeg"
        case 0x47: "image/gif"
        default: nil
        }
    }

    private func escaping(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
