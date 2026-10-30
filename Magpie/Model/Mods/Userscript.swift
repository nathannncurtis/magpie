import Foundation

/// A `@match` rule, with Chrome match-pattern semantics: `<scheme>://<host><path>`.
///
/// The scheme is `*` (http and https) or one of http, https, file and ftp. The host is
/// `*` (any host), `*.domain` (the domain and any subdomain) or an exact host; ports are
/// not part of a pattern. The path is a glob that must start with a slash. A `*` in the
/// path matches any run of characters, including slashes.
struct MatchPattern: Codable, Equatable, Hashable, Sendable {

    /// The scheme part as written, `*` for "http or https".
    let scheme: String
    /// The host part as written: `*`, `*.domain` or an exact host.
    let host: String
    /// The path part, always starting with a slash.
    let path: String

    /// The schemes a `*` pattern covers.
    static let anyScheme = "*"
    /// The schemes a pattern may name literally.
    private static let literalSchemes: Set<String> = ["http", "https", "file", "ftp"]
    /// The host that matches every host.
    private static let anyHost = "*"
    /// The prefix that widens a host to its subdomains.
    private static let subdomainPrefix = "*."

    init?(raw: String) {
        guard let divider = raw.range(of: "://") else { return nil }
        let scheme = String(raw[..<divider.lowerBound])
        guard scheme == Self.anyScheme || Self.literalSchemes.contains(scheme) else { return nil }

        let remainder = raw[divider.upperBound...]
        guard let pathStart = remainder.firstIndex(of: "/") else { return nil }
        let host = String(remainder[..<pathStart])
        let path = String(remainder[pathStart...])
        guard Self.isValid(host: host), !path.isEmpty else { return nil }

        self.scheme = scheme
        self.host = host
        self.path = path
    }

    private static func isValid(host: String) -> Bool {
        guard !host.isEmpty, !host.contains(":") else { return false }
        if host == anyHost { return true }
        if host.hasPrefix(subdomainPrefix) {
            let domain = host.dropFirst(subdomainPrefix.count)
            return !domain.isEmpty && !domain.contains("*")
        }
        return !host.contains("*")
    }

    /// The pattern's host with the wildcard parts taken off: `wikipedia.org`, or nil when
    /// the pattern names no host of its own.
    var domain: String? {
        if host == Self.anyHost { return nil }
        if host.hasPrefix(Self.subdomainPrefix) {
            return String(host.dropFirst(Self.subdomainPrefix.count))
        }
        return host
    }

    /// The pattern as an anchored regular expression source, the same string the injected
    /// guard's JavaScript uses.
    var regexSource: String {
        let schemePart: String
        if scheme == Self.anyScheme {
            schemePart = "https?"
        } else {
            schemePart = Self.escape(scheme)
        }

        let hostPart: String
        if host == Self.anyHost {
            hostPart = "[^/]*"
        } else if host.hasPrefix(Self.subdomainPrefix) {
            let domain = String(host.dropFirst(Self.subdomainPrefix.count))
            hostPart = "(?:[^/]+\\.)*" + Self.escape(domain)
        } else {
            hostPart = Self.escape(host)
        }

        let pathPart = Self.escape(path)
            .replacingOccurrences(of: "\\*", with: ".*")
        return "^\(schemePart)://\(hostPart)\(pathPart)$"
    }

    private static func escape(_ raw: String) -> String {
        NSRegularExpression.escapedPattern(for: raw)
    }
}

/// An `@include` or `@exclude` rule: a glob over the whole URL, or a regular expression
/// written between slashes.
struct URLRule: Codable, Equatable, Hashable, Sendable {

    /// How the rule was written.
    enum Kind: Codable, Equatable, Hashable, Sendable {
        /// A glob over the whole URL: `*` matches anything, `?` one character.
        case glob(pattern: String)
        /// A regular expression, as written between its slashes. It is tested unanchored,
        /// the way script managers test theirs.
        case regex(source: String)
    }

    let kind: Kind

    init?(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
            let source = String(trimmed.dropFirst().dropLast())
            guard !source.isEmpty else { return nil }
            kind = .regex(source: source)
            return
        }
        kind = .glob(pattern: trimmed)
    }

    /// The rule as a regular expression source, shared by Swift's own checks and the
    /// injected guard's JavaScript.
    var regexSource: String {
        switch kind {
        case .regex(let source):
            return source
        case .glob(let pattern):
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            return "^\(escaped)$"
        }
    }
}

/// A compiled rule source. The engine agrees with JavaScript's on the constructs the
/// parsers emit, and matches case-insensitively, as the guard's literals do.
private struct RuleRegex {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func matches(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: source, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// A userscript's metadata block: where it runs and what it asks for.
struct UserscriptMetadata: Codable, Equatable, Sendable {

    /// When the script asks to run.
    enum RunAt: String, Codable, Equatable, Sendable, CaseIterable {
        case documentStart = "document-start"
        case documentEnd = "document-end"
        case documentIdle = "document-idle"

        /// Script managers' default.
        static let defaultRunAt = documentIdle

        init(raw: String) {
            self = RunAt(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? .defaultRunAt
        }
    }

    /// The grants the GM shim honours. Everything else is installed as unsupported.
    static let supportedGrants: Set<String> = [
        "none", "GM_addStyle", "GM_getValue", "GM_setValue", "GM_info",
    ]

    var name: String?
    var namespace: String?
    var version: String?
    var author: String?
    var summary: String?
    var matches: [MatchPattern] = []
    var includes: [URLRule] = []
    var excludes: [URLRule] = []
    var runAt: RunAt = .defaultRunAt
    var grants: [String] = []
    var icon: String?
    var noFrames = false

    /// Whether the script says anywhere it runs. A script with no `@match` and no
    /// `@include` runs nowhere, and cannot be installed.
    var hasRunRules: Bool {
        !matches.isEmpty || !includes.isEmpty
    }

    /// The grants the shim cannot honour, in the order the script named them.
    var unsupportedGrants: [String] {
        var seen: Set<String> = []
        return grants.filter { grant in
            guard !UserscriptMetadata.supportedGrants.contains(grant), !seen.contains(grant) else {
                return false
            }
            seen.insert(grant)
            return true
        }
    }

    /// The hosts the `@match` rules name, deduplicated in writing order. Empty when the
    /// script matches by `@include` alone, or everywhere.
    var matchDomains: [String] {
        var seen: Set<String> = []
        var domains: [String] = []
        for pattern in matches {
            guard let domain = pattern.domain, !seen.contains(domain) else { continue }
            seen.insert(domain)
            domains.append(domain)
        }
        return domains
    }

    /// Whether the script runs on a page at this address.
    func runs(on url: URL) -> Bool {
        guard hasRunRules else { return false }
        let address = url.absoluteString
        let allowed =
            (matches.map { RuleRegex($0.regexSource).matches(address) }
                + includes.map { RuleRegex($0.regexSource).matches(address) })
        guard allowed.contains(true) else { return false }
        return !excludes.contains { RuleRegex($0.regexSource).matches(address) }
    }

    /// The rule sources that let a page through, then those that bar it, in writing
    /// order. Both lists feed the injected guard.
    var runRegexSources: [String] {
        matches.map(\.regexSource) + includes.map(\.regexSource)
    }

    var excludeRegexSources: [String] {
        excludes.map(\.regexSource)
    }
}

/// One userscript: its metadata block and the code that follows it.
struct Userscript: Equatable, Sendable {

    var metadata = UserscriptMetadata()
    var body = ""

    /// Parses a userscript. Text without a `==UserScript==` block, or with an empty one,
    /// is not a userscript and parses as nil.
    static func parse(_ source: String) -> Userscript? {
        guard let block = metadataBlock(in: source) else { return nil }
        var metadata = UserscriptMetadata()
        var foundKey = false

        for line in block.lines {
            guard let entry = keyAndValue(of: line) else { continue }
            foundKey = true
            let value = entry.value
            switch entry.key {
            case "name": metadata.name = value
            case "namespace": metadata.namespace = value
            case "version": metadata.version = value
            case "author": metadata.author = value
            case "description": metadata.summary = value
            case "match": metadata.matches.appendIfPresent(MatchPattern(raw: value))
            case "include": metadata.includes.appendIfPresent(URLRule(raw: value))
            case "exclude": metadata.excludes.appendIfPresent(URLRule(raw: value))
            case "run-at": metadata.runAt = UserscriptMetadata.RunAt(raw: value)
            case "grant": metadata.grants.append(value)
            case "icon": metadata.icon = value
            case "noframes": metadata.noFrames = value.isEmpty || value != "false"
            default: break
            }
        }
        guard foundKey else { return nil }

        var script = Userscript()
        script.metadata = metadata
        script.body = block.trailing
        return script
    }

    /// The block's inner lines, and everything after it as the script's body.
    private static func metadataBlock(in source: String) -> (lines: [String], trailing: String)? {
        let open = "// ==UserScript=="
        let close = "// ==/UserScript=="
        var lines: [String] = []
        var trailing: [Substring] = []
        var inBlock = false
        var foundBlock = false
        var foundClose = false

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if trimmed == open {
                    inBlock = true
                    foundBlock = true
                }
                continue
            }
            if trimmed == close {
                foundClose = true
                continue
            }
            if foundClose {
                trailing.append(line)
            } else {
                lines.append(String(line))
            }
        }
        guard foundBlock, foundClose else { return nil }
        return (lines, trailing.joined(separator: "\n"))
    }

    /// The key and value of a metadata line; flag keys such as `@noframes` carry "".
    private static func keyAndValue(of line: String) -> (key: String, value: String)? {
        guard let body = commentBody(of: line), let at = body.firstIndex(of: "@") else {
            return nil
        }
        guard body[..<at].allSatisfy(\.isWhitespace) else { return nil }
        let rest = body[body.index(after: at)...]
        let key = rest.prefix { !$0.isWhitespace }
        guard !key.isEmpty else { return nil }
        let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return (String(key), value)
    }

    /// A comment line's body, without its slashes.
    private static func commentBody(of line: String) -> Substring? {
        var view = Substring(line)
        var slashes = 0
        while view.hasPrefix("/") {
            view = view.dropFirst()
            slashes += 1
        }
        guard slashes >= 2 else { return nil }
        return view
    }
}

/// A rule source, made safe to embed between a JavaScript regex literal's slashes. `/` is
/// the only character the sources can carry that needs it: ICU needs it bare and a
/// JavaScript literal needs it escaped, so the escaping happens only when the source is
/// written into one.
enum RuleRegexJS {

    static func literalSafe(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var escaped = false
        for character in source {
            if escaped {
                out.append("\\")
                out.append(character)
                escaped = false
            } else if character == "\\" {
                out.append("\\")
                escaped = true
            } else if character == "/" {
                out.append("\\/")
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }
}

private extension Array {
    /// Appends the value when the rule parses.
    mutating func appendIfPresent(_ value: Element?) {
        if let value { append(value) }
    }
}
