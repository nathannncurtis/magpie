import CryptoKit
import Foundation

/// One download as the mods fetch it: its bytes and the reply that carried them.
struct ModDownload: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

/// How the mods reach the network: an ephemeral session that keeps no cookies and no
/// storage, so fetching a script or a list leaves nothing behind.
enum ModFetcher {

    static let live: @Sendable (URL) async throws -> ModDownload = { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.cannotParseResponse)
        }
        return ModDownload(data: data, response: http)
    }

    /// The lowercase hex digest of some bytes.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the link the user pasted turned out to be.
enum InstallLinkResult: Equatable {

    /// A userscript that parsed, with its metadata. It only installs when it says where
    /// it runs; `noRunRules` covers the one that doesn't.
    case userscript(Userscript)
    /// Text in filter-list syntax.
    case filterList
    /// The link's own userscript parsed, but it carries no `@match` and no `@include`.
    case noRunRules
    /// A page, or anything else that is neither a script nor a list.
    case webPage
    /// Nothing came back.
    case unreachable

    var isInstallable: Bool {
        switch self {
        case .userscript, .filterList: return true
        case .noRunRules, .webPage, .unreachable: return false
        }
    }
}

/// Tells a userscript from a filter list from a web page.
enum InstallClassifier {

    /// The prefixes a filter-list rule can start with.
    private static let listLinePrefixes = [
        "||", "@@||", "@@|", "|", "##", "#@#", "#?#", "##^",
    ]

    static func classify(_ text: String) -> InstallLinkResult {
        if let script = Userscript.parse(text) {
            return script.metadata.hasRunRules ? .userscript(script) : .noRunRules
        }
        let head = text.prefix(4096).lowercased()
        if head.contains("<!doctype html") || head.contains("<html") {
            return .webPage
        }
        return looksLikeFilterList(text) ? .filterList : .webPage
    }

    /// Filter-list syntax, loosely: nothing but comments, section headers and rule lines,
    /// with a fair number of rules among them.
    private static func looksLikeFilterList(_ text: String) -> Bool {
        let lines =
            text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var rules = 0
        for line in lines {
            if line.hasPrefix("!") || line.hasPrefix("[") { continue }
            if isRuleLine(line) {
                rules += 1
                continue
            }
            return false
        }
        return rules >= 3
    }

    private static func isRuleLine(_ line: String) -> Bool {
        if listLinePrefixes.contains(where: { line.hasPrefix($0) }) { return true }
        if line.contains("$domain=") || line.contains("$~domain") { return true }
        // A plain host or path rule: "ads.example.com/banner.gif".
        return !line.contains(where: { $0.isWhitespace })
            && (line.contains("/") || line.contains("."))
    }
}

/// Fetches a pasted link and turns what comes back into a draft, ready to install.
enum ModLinkInstaller {

    /// The link's text, classified. A link that doesn't answer, or that isn't a mod,
    /// comes back as the matching result rather than nil.
    static func inspect(
        _ url: URL,
        fetch: @Sendable (URL) async throws -> ModDownload = ModFetcher.live
    ) async -> InstallLinkResult {
        guard url.scheme == "http" || url.scheme == "https" else { return .webPage }
        do {
            let download = try await fetch(url)
            guard download.response.statusCode == 200 else { return .unreachable }
            let text = String(decoding: download.data, as: UTF8.self)
            return InstallClassifier.classify(text)
        } catch {
            return .unreachable
        }
    }

    /// A pasted link as a draft. Nil when the link isn't installable: the caller already
    /// knows why from `inspect`.
    static func draft(from result: InstallLinkResult, url: URL) -> ModDraft? {
        let fallbackName = Self.name(from: url)
        switch result {
        case .userscript(let script):
            return ModDraft(
                id: linkID(for: url),
                name: script.metadata.name ?? fallbackName,
                kind: .userscript,
                author: script.metadata.author,
                version: script.metadata.version,
                summary: script.metadata.summary,
                icon: .linkInstall(),
                source: .link(url),
                script: script.metadata,
                scriptBody: script.body,
                listURL: nil)
        case .filterList:
            return ModDraft(
                id: linkID(for: url),
                name: fallbackName,
                kind: .filterList,
                author: nil,
                version: nil,
                summary: nil,
                icon: ModIconSpec(
                    glyph: "line.3.horizontal.decrease.circle.fill",
                    gradient: [
                        "#6F7B8A", "#3E4753",
                    ]),
                source: .link(url),
                script: nil,
                scriptBody: nil,
                listURL: url)
        case .noRunRules, .webPage, .unreachable:
            return nil
        }
    }

    /// Fetches the link and builds the draft in one step, for the store's update path.
    static func fetchDraft(from url: URL, fetch: @Sendable (URL) async throws -> ModDownload = ModFetcher.live)
        async -> ModDraft?
    {
        let result = await inspect(url, fetch: fetch)
        return draft(from: result, url: url)
    }

    /// A stable id for a link install: "link-" plus the first digits of the address's
    /// digest, so the same link always updates the same mod.
    static func linkID(for url: URL) -> String {
        "link-" + ModFetcher.sha256Hex(of: Data(url.absoluteString.utf8)).prefix(12)
    }

    /// What a link is called when nothing better is known: its file name, else its host.
    /// A bare address has no file name — its path is just "/".
    static func name(from url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/" {
            return String(last.prefix(40))
        }
        return url.host() ?? url.absoluteString
    }
}
