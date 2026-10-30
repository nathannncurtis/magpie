import Foundation

/// Why a list line produced no rule. Counted per conversion so a real list can be audited
/// for what it lost.
enum FilterListSkipReason: String, CaseIterable, Codable, Sendable {
    /// `##+js(...)` and `#%#...` script snippets.
    case scriptInjection
    /// `#$#...` injected styles.
    case cssInjection
    /// `#@#` element-hiding exceptions. WebKit can't unhide a single selector, and a broad
    /// `ignore-previous-rules` would also unblock network rules, so these are dropped: elements
    /// they exempt may stay hidden on the exempted sites.
    case elementHidingException
    /// Selectors needing a script engine (`:has-text(`, `:-abp-`, `:xpath(`, …) or `:has(`.
    case proceduralSelector
    /// Selectors that aren't plain CSS WebKit would compile. One bad selector in a compiled
    /// list fails the whole list, so anything questionable is rejected.
    case invalidSelector
    /// `$webrtc`, `$beacon`, and `$websocket`/`$ping` where the running WebKit predates
    /// those resource types.
    case unsupportedResourceType
    /// `$removeparam`.
    case removeparam
    /// `$redirect`, `$redirect-rule`.
    case redirect
    /// `$csp`.
    case csp
    /// `$rewrite`, `$method`, `$header`, `$sitekey`, `$badfilter`, unknown options, and
    /// cosmetic-scoping options on block rules.
    case unsupportedOption
    /// `@@…$generichide` / `$elemhide` with nothing network-relevant to undo.
    case cosmeticWhitelist
    /// `domain=a.com|~b.com` in one option; if-domain and unless-domain can't be combined.
    case mixedDomains
    /// Empty patterns, spaces in patterns, unparsable domains.
    case invalidPattern
    /// `/regex/` rules using syntax outside the subset WebKit's rule compiler accepts.
    case unsupportedRegex
}

/// Counts for one conversion: what came in, what went out, what was dropped and why.
struct FilterListStats: Equatable, Sendable {
    var lines = 0
    var comments = 0
    var blanks = 0
    var rules = 0
    var emitted = 0
    var skipped: [FilterListSkipReason: Int] = [:]

    mutating func skip(_ reason: FilterListSkipReason) {
        skipped[reason, default: 0] += 1
    }
}

/// A network-block or element-hiding rule. These compile ahead of the exception rules.
struct ContentBlockerRule: Codable, Equatable, Hashable, Sendable {
    var trigger: Trigger
    var action: Action

    struct Trigger: Codable, Equatable, Hashable, Sendable {
        /// A regular expression over the loaded resource's URL, restricted to the syntax
        /// WebKit's rule compiler accepts: `.`, `*`, `+`, `?`, `[]`, `()`, `^`, `$`.
        var urlFilter: String
        var resourceType: [String]?
        var loadType: [String]?
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var urlFilterIsCaseSensitive: Bool?

        init(
            urlFilter: String,
            resourceType: [String]? = nil,
            loadType: [String]? = nil,
            ifDomain: [String]? = nil,
            unlessDomain: [String]? = nil,
            urlFilterIsCaseSensitive: Bool? = nil
        ) {
            self.urlFilter = urlFilter
            self.resourceType = resourceType
            self.loadType = loadType
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
            self.urlFilterIsCaseSensitive = urlFilterIsCaseSensitive
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
        }
    }

    struct Action: Codable, Equatable, Hashable, Sendable {
        var type: String
        var selector: String?

        init(type: String, selector: String? = nil) {
            self.type = type
            self.selector = selector
        }
    }

    enum CodingKeys: String, CodingKey {
        case trigger
        case action
    }

    init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

/// One list's conversion. The split matters: `ignore-previous-rules` only undoes rules ahead of
/// it in the same compiled list, so exceptions are placed after every block when a set is
/// assembled.
struct FilterListConversion: Sendable {
    var blockRules: [ContentBlockerRule]
    var exceptionRules: [ContentBlockerRule]
    var stats: FilterListStats
}

/// Which resource-type strings the running WebKit compiles. `stylesheet`, `subdocument` and
/// `xmlhttprequest` were renamed to `style-sheet`, `child-document` and `fetch`, with the old
/// names no longer accepted; `websocket` and `ping` only exist on the new side. The store
/// probes the compiler once and passes the result to the converter.
enum RuleListVocabulary: String, Equatable, Sendable {
    case current
    case legacy

    /// Resource types a negated EasyList type expands to. `document` and `popup` are
    /// opt-in only, so pages and links can't be blocked by accident.
    var safeResourceTypes: [ResourceKind] {
        let base: [ResourceKind] = [.font, .image, .media, .other, .script, .stylesheet, .subdocument]
        switch self {
        case .current: return base + [.xmlhttprequest, .websocket, .ping]
        case .legacy: return base + [.xmlhttprequest]
        }
    }
}

/// An EasyList resource option resolved against the vocabulary's WebKit type names.
enum ResourceKind: Hashable, Sendable {
    case document
    case popup
    case script
    case image
    case font
    case media
    case stylesheet
    case subdocument
    case xmlhttprequest
    case websocket
    case ping
    case other

    func name(in vocabulary: RuleListVocabulary) -> String {
        switch (self, vocabulary) {
        case (.stylesheet, .current): return "style-sheet"
        case (.stylesheet, .legacy): return "stylesheet"
        case (.subdocument, .current): return "child-document"
        case (.subdocument, .legacy): return "subdocument"
        case (.xmlhttprequest, .current): return "fetch"
        case (.xmlhttprequest, .legacy): return "xmlhttprequest"
        default: return webKitName
        }
    }

    private var webKitName: String {
        switch self {
        case .document: return "document"
        case .popup: return "popup"
        case .script: return "script"
        case .image: return "image"
        case .font: return "font"
        case .media: return "media"
        case .websocket: return "websocket"
        case .ping: return "ping"
        case .other: return "other"
        case .stylesheet, .subdocument, .xmlhttprequest:
            preconditionFailure("Renamed kinds go through name(in:)")
        }
    }
}

/// Converts EasyList-family filter syntax into WebKit content-blocker JSON. Pure.
enum FilterListConverter {

    /// WebKit caps one compiled rule list at this many rules.
    static let webKitRuleListLimit = 150_000

    /// Element-hiding selectors batched into one `css-display-none` rule.
    static let selectorsPerElementHidingRule = 500

    // MARK: Conversion

    static func convert(
        _ text: String,
        vocabulary: RuleListVocabulary = .current
    ) -> FilterListConversion {
        var blocks: [ContentBlockerRule] = []
        var exceptions: [ContentBlockerRule] = []
        var stats = FilterListStats()
        var selectors = SelectorBatcher()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            stats.lines += 1
            if line.isEmpty {
                stats.blanks += 1
                continue
            }
            if line.hasPrefix("!") || line.hasPrefix("[") {
                stats.comments += 1
                continue
            }
            stats.rules += 1

            if let cosmetic = CosmeticRule.parse(line) {
                convertCosmetic(cosmetic, stats: &stats, selectors: &selectors)
                continue
            }

            var isException = false
            var body = line
            if body.hasPrefix("@@") {
                isException = true
                body.removeFirst(2)
            }
            let (pattern, options) = splitOptions(body, vocabulary: vocabulary)
            convertNetwork(
                pattern: pattern,
                options: options,
                isException: isException,
                vocabulary: vocabulary,
                stats: &stats,
                blocks: &blocks,
                exceptions: &exceptions
            )
        }

        blocks.append(contentsOf: selectors.rules())
        stats.emitted = blocks.count + exceptions.count
        return FilterListConversion(blockRules: blocks, exceptionRules: exceptions, stats: stats)
    }

    // MARK: Set assembly

    /// Splits one set's rules into numbered chunks under WebKit's per-list cap. Every chunk
    /// carries the set's full exception tail, so an exception undoes the blocks ahead of it
    /// whichever chunk WebKit applies it in; exceptions are few compared with blocks. If the
    /// cap is below the exception count the chunks overflow — the tail is kept complete rather
    /// than truncated, because a truncated exception list would block content the lists
    /// explicitly whitelisted.
    static func ruleChunks(
        from conversions: [FilterListConversion],
        cap: Int = webKitRuleListLimit
    ) -> [[ContentBlockerRule]] {
        var blocks: [ContentBlockerRule] = []
        var exceptions: [ContentBlockerRule] = []
        var seen = Set<ContentBlockerRule>()
        for conversion in conversions {
            for rule in conversion.blockRules where seen.insert(rule).inserted {
                blocks.append(rule)
            }
            for rule in conversion.exceptionRules where seen.insert(rule).inserted {
                exceptions.append(rule)
            }
        }
        guard !(blocks.isEmpty && exceptions.isEmpty) else { return [] }

        if blocks.isEmpty {
            return [exceptions]
        }
        let blocksPerChunk = max(1, cap - exceptions.count)
        var chunks: [[ContentBlockerRule]] = []
        var index = 0
        while index < blocks.count {
            let end = min(index + blocksPerChunk, blocks.count)
            chunks.append(Array(blocks[index..<end]) + exceptions)
            index = end
        }
        return chunks
    }

    /// Canonical JSON for one chunk; the stable form its identifier hash is taken over.
    static func encodedJSON(_ rules: [ContentBlockerRule]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("Rule JSON is not UTF-8")
        }
        return json
    }

    /// A one-rule list using only the renamed types; whether the running WebKit compiles it
    /// decides the vocabulary for every conversion.
    static let vocabularyProbeJSON =
        #"[{"trigger":{"url-filter":"vocabulary","resource-type":["style-sheet","child-document","fetch","websocket","ping"]},"action":{"type":"block"}}]"#

    // MARK: Element hiding

    private enum CosmeticKind {
        case hide
        case exception
        case style
        case snippet
    }

    private struct CosmeticRule {
        let domains: String
        let selector: String
        let kind: CosmeticKind

        /// Finds the `##` / `#@#` / `#?#` / `#$#` / `#%#` separator families, whichever comes
        /// first, and splits the line there.
        static func parse(_ line: String) -> CosmeticRule? {
            let chars = Array(line)
            guard chars.count > 1 else { return nil }
            var i = 0
            while i < chars.count - 1 {
                guard chars[i] == "#" else {
                    i += 1
                    continue
                }
                let next = chars[i + 1]
                if next == "#" {
                    return CosmeticRule(
                        domains: String(chars[0..<i]),
                        selector: String(chars[(i + 2)...]).trimmingCharacters(in: .whitespaces),
                        kind: .hide
                    )
                }
                if next == "?" || next == "$" || next == "%" {
                    if i + 2 < chars.count, chars[i + 2] == "#" {
                        let kind: CosmeticKind = next == "?" ? .hide : (next == "$" ? .style : .snippet)
                        return CosmeticRule(
                            domains: String(chars[0..<i]),
                            selector: String(chars[(i + 3)...]).trimmingCharacters(in: .whitespaces),
                            kind: kind
                        )
                    }
                }
                if next == "@" {
                    for following in ["#", "?#", "$#", "%#"] {
                        if line.dropFirst(i + 2).hasPrefix(following) {
                            let selectorStart = i + 2 + following.count
                            return CosmeticRule(
                                domains: String(chars[0..<i]),
                                selector: String(chars[selectorStart...]).trimmingCharacters(in: .whitespaces),
                                kind: .exception
                            )
                        }
                    }
                }
                i += 1
            }
            return nil
        }
    }

    private static func convertCosmetic(
        _ rule: CosmeticRule,
        stats: inout FilterListStats,
        selectors: inout SelectorBatcher
    ) {
        switch rule.kind {
        case .snippet:
            stats.skip(.scriptInjection)
            return
        case .style:
            stats.skip(.cssInjection)
            return
        case .exception:
            // Best effort: dropped, see FilterListSkipReason.elementHidingException.
            stats.skip(.elementHidingException)
            return
        case .hide:
            break
        }

        if rule.selector.hasPrefix("+js(") {
            stats.skip(.scriptInjection)
            return
        }
        guard !rule.selector.isEmpty, isPlainCSS(rule.selector) else {
            stats.skip(proceduralMarker(in: rule.selector) ? .proceduralSelector : .invalidSelector)
            return
        }
        guard let domains = parseDomains(rule.domains) else {
            stats.skip(.invalidPattern)
            return
        }
        selectors.add(
            rule.selector,
            ifDomains: domains.included.map { "*\($0)" },
            unlessDomains: domains.excluded.map { "*\($0)" }
        )
    }

    private static let cssFunctionPseudos: Set<String> = [
        ":not", ":is", ":where", ":nth-child", ":nth-last-child", ":nth-of-type", ":nth-last-of-type",
    ]

    private static let proceduralMarkers = [
        ":has-text(", ":-abp-", ":xpath(", ":matches-attr(", ":matches-path(", ":matches-property(",
        ":matches-media(", ":min-text-length(", ":upward(", ":watch-attr(", ":style(", ":remove-attr(",
        ":remove-class(", ":remove(", ":spath", ":has(", ":contains(", ":matches(", ":others(",
        ":nth-ancestor(", ":subject", ":if(", ":if-not(",
    ]

    private static func proceduralMarker(in selector: String) -> Bool {
        proceduralMarkers.contains { selector.contains($0) }
    }

    /// A conservative check that a selector is plain CSS WebKit compiles: balanced brackets,
    /// parentheses and quotes, no style or script syntax, and function calls only from the
    /// small set of standard functional pseudo-classes.
    private static func isPlainCSS(_ selector: String) -> Bool {
        if proceduralMarker(in: selector) { return false }
        var bracketDepth = 0
        var parenDepth = 0
        var quote: Character? = nil
        var name = ""

        for char in selector {
            if let open = quote {
                if char == open { quote = nil }
                continue
            }
            switch char {
            case "\"", "'":
                if bracketDepth == 0 { return false }
                quote = char
                name = ""
            case "[":
                if bracketDepth > 0 { return false }
                bracketDepth += 1
                name = ""
            case "]":
                if bracketDepth == 0 { return false }
                bracketDepth -= 1
                name = ""
            case "(":
                if parenDepth > 0 { return false }
                guard cssFunctionPseudos.contains(name) else { return false }
                parenDepth += 1
                name = ""
            case ")":
                if parenDepth == 0 { return false }
                parenDepth -= 1
                name = ""
            case "<", "{", "}", ";", "\\":
                return false
            case "^", "$", "|", "=", "!", "%", "@", "/", "&", "?":
                // Attribute operators and unquoted attribute values, inside brackets only.
                if bracketDepth == 0 { return false }
                name = ""
            case " ", ">", "+", ",", ".", "#", "*", "~":
                name = ""
            case ":":
                // A pseudo begins its own token; a second colon extends it (`::before`).
                if name.isEmpty || name.hasPrefix(":") {
                    name += ":"
                } else {
                    name = ":"
                }
            case "-", "_":
                name += String(char)
            default:
                if char.isLetter || char.isNumber {
                    name += String(char)
                } else {
                    return false
                }
            }
        }
        return bracketDepth == 0 && parenDepth == 0 && quote == nil
    }

    // MARK: Network rules

    private struct RuleOptions {
        var resourceTypes = Set<ResourceKind>()
        var negatedTypes = Set<ResourceKind>()
        var explicitPopup = false
        var document = false
        var thirdParty: Bool?
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var matchCase = false
        var cosmetic = false
        var dropReason: FilterListSkipReason?
    }

    private static func convertNetwork(
        pattern: String,
        options: RuleOptions?,
        isException: Bool,
        vocabulary: RuleListVocabulary,
        stats: inout FilterListStats,
        blocks: inout [ContentBlockerRule],
        exceptions: inout [ContentBlockerRule]
    ) {
        let options = options ?? RuleOptions()
        if let reason = options.dropReason {
            stats.skip(reason)
            return
        }
        if options.cosmetic && !isException {
            // Cosmetic scoping options only mean something on whitelists.
            stats.skip(.unsupportedOption)
            return
        }
        if isException && options.cosmetic && !options.document && options.resourceTypes.isEmpty
            && options.thirdParty == nil
        {
            stats.skip(.cosmeticWhitelist)
            return
        }

        if isException && options.document, let host = plainHost(pattern) {
            // Whole-page whitelist: undo every earlier rule on pages at this host.
            exceptions.append(
                ContentBlockerRule(
                    trigger: ContentBlockerRule.Trigger(urlFilter: ".*", ifDomain: ["*\(host)"]),
                    action: ContentBlockerRule.Action(type: "ignore-previous-rules")
                )
            )
            return
        }

        let translation: PatternTranslation
        if pattern.isEmpty {
            // Options-only lines (`$popup,domain=…`) mean "any URL, restricted by the
            // options"; only emit them when the options really do restrict the rule.
            let restricted =
                !options.ifDomains.isEmpty || !options.unlessDomains.isEmpty
                || !options.resourceTypes.isEmpty || options.explicitPopup
                || (options.document && !isException)
            translation = (restricted && !isException) ? .filter(".*") : .invalid
        } else {
            translation = translate(pattern)
        }

        switch translation {
        case .filter(let urlFilter):
            var trigger = ContentBlockerRule.Trigger(urlFilter: urlFilter)
            if options.matchCase {
                trigger.urlFilterIsCaseSensitive = true
            }
            var types = options.resourceTypes
            if options.explicitPopup { types.insert(.popup) }
            if options.document && !isException { types.insert(.document) }
            if types.isEmpty, !options.negatedTypes.isEmpty {
                // A negated type means "every type except this one".
                types = Set(vocabulary.safeResourceTypes).subtracting(options.negatedTypes)
            }
            if !types.isEmpty {
                trigger.resourceType = types.map { $0.name(in: vocabulary) }.sorted()
            }
            if let thirdParty = options.thirdParty {
                trigger.loadType = [thirdParty ? "third-party" : "first-party"]
            }
            if !options.ifDomains.isEmpty {
                trigger.ifDomain = options.ifDomains.map { "*\($0)" }
            }
            if !options.unlessDomains.isEmpty {
                trigger.unlessDomain = options.unlessDomains.map { "*\($0)" }
            }
            let rule = ContentBlockerRule(
                trigger: trigger,
                action: ContentBlockerRule.Action(
                    type: isException ? "ignore-previous-rules" : "block"
                )
            )
            if isException {
                exceptions.append(rule)
            } else {
                blocks.append(rule)
            }
        case .unsupported:
            stats.skip(.unsupportedRegex)
        case .invalid:
            stats.skip(.invalidPattern)
        }
    }

    enum PatternTranslation {
        case filter(String)
        case unsupported
        case invalid
    }

    /// Translates one EasyList network pattern into a url-filter. `||` anchors to the start of
    /// the host, `|` to an end of the URL, `^` to a separator (anything but a letter, digit or
    /// `.`/`-`/`_`/`%`), `*` is a wildcard; everything else is literal.
    static func translate(_ pattern: String) -> PatternTranslation {
        var rest = Substring(pattern)
        var domainAnchored = false
        var startAnchored = false
        var endAnchored = false
        if rest.hasPrefix("||") {
            domainAnchored = true
            rest = rest.dropFirst(2)
        } else if rest.hasPrefix("|") {
            startAnchored = true
            rest = rest.dropFirst()
        }
        if rest.hasSuffix("|") {
            endAnchored = true
            rest = rest.dropLast()
        }
        if rest.isEmpty { return .invalid }
        if rest.contains(" ") || rest.contains("\t") { return .invalid }

        if rest.hasPrefix("/"), rest.hasSuffix("/"), rest.count > 2 {
            let body = rest.dropFirst().dropLast()
            return validatedRegex(body).map { .filter($0) } ?? .unsupported
        }

        var out = ""
        if domainAnchored {
            // scheme :// ( userinfo or subdomains ending in a dot ) pattern
            out += "^[a-z][a-z0-9+.-]*://([^/]+\\.)?"
        } else if startAnchored {
            out += "^"
        }
        for char in rest {
            switch char {
            case "*":
                out += ".*"
            case "^":
                out += "[^a-zA-Z0-9._%-]"
            default:
                out += escapeLiteral(char)
            }
        }
        if endAnchored {
            out += "$"
        }
        return .filter(out)
    }

    /// Passes a `/regex/` rule through only when it stays inside the syntax WebKit's rule
    /// compiler accepts: no alternation, no counted repetition, no escape classes, no group
    /// flags, balanced groups and classes.
    static func validatedRegex(_ body: Substring) -> String? {
        if body.isEmpty { return nil }
        var parenDepth = 0
        var classDepth = 0
        var escaped = false
        var previous: Character? = nil
        for char in body {
            if escaped {
                // Only punctuation escapes; \d, \w, \b shorthand is outside the accepted subset.
                if char.isLetter || char.isNumber { return nil }
                escaped = false
                previous = char
                continue
            }
            switch char {
            case "\\":
                escaped = true
            case "|", "{", "}":
                return nil
            case "(":
                if classDepth > 0 { return nil }
                if previous == nil || previous == "(" || previous == "?" { return nil }
                parenDepth += 1
            case ")":
                if parenDepth == 0 { return nil }
                parenDepth -= 1
            case "[":
                if classDepth > 0 { return nil }
                classDepth += 1
            case "]":
                if classDepth == 0 { return nil }
                classDepth -= 1
            case "*", "+", "?":
                if previous == nil || previous == "(" { return nil }
            default:
                break
            }
            previous = char
        }
        guard parenDepth == 0, classDepth == 0, !escaped else { return nil }
        return String(body)
    }

    private static func escapeLiteral(_ char: Character) -> String {
        if ".+?()[]{}|$^\\".contains(char) {
            return "\\\(char)"
        }
        return String(char)
    }

    /// The host of a `||host^` pattern, or nil when the pattern carries a path or wildcards
    /// that make a host-scoped whitelist wrong.
    private static func plainHost(_ pattern: String) -> String? {
        var rest = Substring(pattern)
        guard rest.hasPrefix("||") else { return nil }
        rest = rest.dropFirst(2)
        if rest.hasSuffix("^") { rest = rest.dropLast() }
        if rest.hasSuffix("|") { rest = rest.dropLast() }
        guard !rest.isEmpty else { return nil }
        let hostChars = { (c: Character) in c.isLetter || c.isNumber || c == "." || c == "-" }
        guard rest.allSatisfy(hostChars), !rest.hasPrefix("."), !rest.hasSuffix("."),
            !rest.contains("..")
        else { return nil }
        return String(rest).lowercased()
    }

    // MARK: Options

    private static let typeOptions: [String: ResourceKind] = [
        "script": .script,
        "image": .image,
        "img": .image,
        "stylesheet": .stylesheet,
        "css": .stylesheet,
        "font": .font,
        "media": .media,
        "xmlhttprequest": .xmlhttprequest,
        "xhr": .xmlhttprequest,
        "subdocument": .subdocument,
        "object": .media,
        "object-subrequest": .media,
        "other": .other,
    ]

    private static let flagOptions: Set<String> = [
        "third-party", "first-party", "match-case", "popup", "document", "generichide", "genericblock",
        "elemhide", "important", "collapse", "badfilter", "donottrack", "websocket", "ping", "beacon",
        "webrtc", "script", "image", "img", "stylesheet", "css", "font", "media", "xmlhttprequest",
        "xhr", "subdocument", "object", "object-subrequest", "other",
    ]

    private static let valueOptions: Set<String> = [
        "domain", "redirect", "redirect-rule", "csp", "removeparam", "rewrite", "method", "header",
        "sitekey",
    ]

    /// Splits `$options` off a rule. A `$` is only an option separator when everything after it
    /// parses as options, so patterns with a literal `$` survive.
    private static func splitOptions(
        _ body: String,
        vocabulary: RuleListVocabulary
    ) -> (String, RuleOptions?) {
        let candidates = body.indices.filter { body[$0] == "$" }
        for index in candidates.reversed() {
            let optionText = String(body[body.index(after: index)...])
            if let options = parseOptions(optionText, vocabulary: vocabulary) {
                return (String(body[..<index]), options)
            }
        }
        return (body, nil)
    }

    private static func parseOptions(
        _ text: String,
        vocabulary: RuleListVocabulary
    ) -> RuleOptions? {
        var options = RuleOptions()
        for token in text.split(separator: ",", omittingEmptySubsequences: false) {
            let raw = token.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { continue }
            if let equals = raw.firstIndex(of: "=") {
                let key = String(raw[..<equals])
                guard valueOptions.contains(key) else { return nil }
                let value = String(raw[raw.index(after: equals)...])
                applyValueOption(key, value, &options)
                continue
            }
            var name = raw
            var negated = false
            if name.hasPrefix("~") {
                negated = true
                name.removeFirst()
            }
            guard flagOptions.contains(name) else { return nil }
            applyFlagOption(name, negated: negated, vocabulary: vocabulary, &options)
        }
        return options
    }

    private static func applyValueOption(_ key: String, _ value: String, _ options: inout RuleOptions) {
        switch key {
        case "domain":
            guard let domains = parseDomains(value),
                !(domains.included.isEmpty && domains.excluded.isEmpty)
            else {
                options.dropReason = options.dropReason ?? .invalidPattern
                return
            }
            if !domains.included.isEmpty && !domains.excluded.isEmpty {
                options.dropReason = options.dropReason ?? .mixedDomains
            } else {
                options.ifDomains = domains.included
                options.unlessDomains = domains.excluded
            }
        case "redirect", "redirect-rule":
            options.dropReason = options.dropReason ?? .redirect
        case "csp":
            options.dropReason = options.dropReason ?? .csp
        case "removeparam":
            options.dropReason = options.dropReason ?? .removeparam
        default:
            options.dropReason = options.dropReason ?? .unsupportedOption
        }
    }

    private static func applyFlagOption(
        _ name: String,
        negated: Bool,
        vocabulary: RuleListVocabulary,
        _ options: inout RuleOptions
    ) {
        if let webKitType = typeOptions[name] {
            if negated {
                options.negatedTypes.insert(webKitType)
            } else {
                options.resourceTypes.insert(webKitType)
            }
            return
        }
        switch name {
        case "third-party":
            options.thirdParty = !negated
        case "first-party":
            options.thirdParty = negated
        case "match-case":
            options.matchCase = true
        case "popup":
            options.explicitPopup = true
        case "document":
            options.document = true
        case "generichide", "genericblock", "elemhide":
            options.cosmetic = true
        case "websocket", "ping":
            // Real types on current WebKit; older builds have no match for them.
            if vocabulary == .legacy {
                options.dropReason = options.dropReason ?? .unsupportedResourceType
            } else {
                options.resourceTypes.insert(name == "websocket" ? .websocket : .ping)
            }
        case "beacon", "webrtc":
            options.dropReason = options.dropReason ?? .unsupportedResourceType
        case "badfilter", "donottrack":
            options.dropReason = options.dropReason ?? .unsupportedOption
        default:
            // `important` overrides exceptions, which WebKit has no priority for; the rule is
            // kept as a plain block. `collapse` is a cosmetic hint.
            break
        }
    }

    // MARK: Domains

    /// Domain lists: `domain=` option values are pipe-separated, cosmetic-rule domains
    /// comma-separated; domains contain neither character, so both split here.
    private static func parseDomains(_ text: String) -> (included: [String], excluded: [String])? {
        var included: [String] = []
        var excluded: [String] = []
        for token in text.split(whereSeparator: { $0 == "," || $0 == "|" }) {
            var domain = token.trimmingCharacters(in: .whitespaces)
            var negated = false
            if domain.hasPrefix("~") {
                negated = true
                domain.removeFirst()
            }
            domain = domain.lowercased()
            if domain.hasPrefix("*.") { domain.removeFirst(2) }
            while domain.hasPrefix(".") { domain.removeFirst() }
            if let slash = domain.firstIndex(of: "/") { domain = String(domain[..<slash]) }
            if domain.isEmpty {
                if negated { return nil }
                continue
            }
            let hostChars = { (c: Character) in c.isLetter || c.isNumber || c == "." || c == "-" }
            if !domain.allSatisfy({ $0.isASCII }), let encoded = punycodeEncoded(domain) {
                domain = encoded
            }
            guard domain.allSatisfy(hostChars), domain.allSatisfy({ $0.isASCII }) else { return nil }
            if negated {
                excluded.append(domain)
            } else {
                included.append(domain)
            }
        }
        return (included, excluded)
    }

    /// Encodes an IDN domain to its ASCII `xn--` form, label by label; WebKit only accepts
    /// lowercase ASCII domains. ASCII input and already-encoded labels pass through.
    private static func punycodeEncoded(_ domain: String) -> String? {
        var labels: [String] = []
        for label in domain.split(separator: ".", omittingEmptySubsequences: false) {
            guard let encoded = punycodeLabel(label) else { return nil }
            labels.append(encoded)
        }
        return labels.joined(separator: ".")
    }

    /// Punycode (RFC 3492) for one label.
    private static func punycodeLabel(_ label: Substring) -> String? {
        let scalars = Array(label.unicodeScalars)
        if scalars.allSatisfy(\.isASCII) { return String(label) }

        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        var output = scalars.filter(\.isASCII).map { String($0) }
        let basicCount = output.count
        if basicCount > 0 { output.append("-") }
        var handled = basicCount
        var n = 0x80
        var delta = 0
        var bias = 72

        func digit(_ value: Int) -> Character? {
            switch value {
            case 0..<26: return UnicodeScalar(97 + value).map(Character.init)
            case 26..<36: return UnicodeScalar(48 + value - 26).map(Character.init)
            default: return nil
            }
        }

        func adapt(_ delta: Int, points: Int, first: Bool) -> Int {
            var delta = first ? delta / damp : delta / 2
            delta += delta / points
            var k = 0
            while delta > ((base - tMin) * tMax) / 2 {
                delta /= base - tMin
                k += base
            }
            return k + tMin + ((base - tMin + 1) * delta) / (delta + skew)
        }

        while handled < scalars.count {
            let m = scalars.map { Int($0.value) }.filter { $0 >= n }.min() ?? n
            delta += Int(m - n) * (handled + 1)
            n = Int(m)
            for scalar in scalars {
                let value = Int(scalar.value)
                if value < n { delta += 1 }
                guard value == n else { continue }
                let totalDelta = delta
                var q = delta
                var k = base
                while true {
                    let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                    if q < t { break }
                    guard let d = digit(t + (q - t) % (base - t)) else { return nil }
                    output.append(String(d))
                    q = (q - t) / (base - t)
                    k += base
                }
                guard let d = digit(q) else { return nil }
                output.append(String(d))
                delta = 0
                handled += 1
                bias = adapt(totalDelta, points: handled, first: handled == basicCount + 1)
            }
            delta += 1
            n += 1
        }
        return "xn--" + output.joined()
    }

    // MARK: Selector batching

    /// Groups element-hiding selectors by their domain restriction so one rule covers many
    /// selectors, keeping the rule count down.
    private struct SelectorBatcher {
        private struct Group {
            var ifDomains: [String]
            var unlessDomains: [String]
            var selectors: [String] = []
            var seen = Set<String>()
        }

        private var groups: [String: Group] = [:]
        private var order: [String] = []

        mutating func add(_ selector: String, ifDomains: [String], unlessDomains: [String]) {
            let key = ifDomains.joined(separator: "|") + "#" + unlessDomains.joined(separator: "|")
            var group = groups[key] ?? Group(ifDomains: ifDomains, unlessDomains: unlessDomains)
            if groups[key] == nil {
                order.append(key)
            }
            if group.seen.insert(selector).inserted {
                group.selectors.append(selector)
            }
            groups[key] = group
        }

        func rules() -> [ContentBlockerRule] {
            var rules: [ContentBlockerRule] = []
            for key in order {
                guard let group = groups[key] else { continue }
                for chunk in group.selectors.chunked(into: FilterListConverter.selectorsPerElementHidingRule) {
                    rules.append(
                        ContentBlockerRule(
                            trigger: ContentBlockerRule.Trigger(
                                urlFilter: ".*",
                                ifDomain: group.ifDomains.isEmpty ? nil : group.ifDomains,
                                unlessDomain: group.unlessDomains.isEmpty ? nil : group.unlessDomains
                            ),
                            action: ContentBlockerRule.Action(
                                type: "css-display-none",
                                selector: chunk.joined(separator: ",")
                            )
                        )
                    )
                }
            }
            return rules
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
