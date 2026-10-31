import Foundation

/// What a line of search-field input resolves to.
enum QueryResolution: Equatable, Sendable {
    /// A web address to open.
    case url(URL)
    /// A query to run on the chosen engine.
    case search(String)
}

/// Turns raw search-field input into either a URL or a query.
///
/// Pure and total: every input resolves to something, except input that is only whitespace.
enum QueryResolver {

    /// Resolves `input` against `engine`. Nil when there is nothing to submit.
    static func resolve(_ input: String, engine: SearchEngine = .default) -> QueryResolution? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = bareHostURL(trimmed) { return .url(url) }
        if let scheme = leadingScheme(trimmed) {
            switch scheme {
            case "http", "https", "ftp":
                guard let url = URL(string: trimmed), !(url.host ?? "").isEmpty else {
                    return .search(searchText(trimmed))
                }
                return .url(url)
            case "about":
                // Only about:blank is a page; anything else is words to search for.
                if trimmed.lowercased() == "about:blank", let blank = URL(string: "about:blank") {
                    return .url(blank)
                }
                return .search(searchText(trimmed))
            default:
                // javascript:, data:, file: and unknown schemes are never opened.
                return .search(searchText(trimmed))
            }
        }
        return .search(searchText(trimmed))
    }

    /// Pasted multi-line text searches as one line: each run of whitespace holding a line
    /// break or tab becomes a single space. Plain spaces are left as typed.
    private static func searchText(_ text: String) -> String {
        guard text.contains(where: { $0.isNewline || $0 == "\t" }) else { return text }
        var result = ""
        var run = ""
        for character in text {
            if character.isWhitespace {
                run.append(character)
                continue
            }
            if !run.isEmpty {
                result += run.contains(where: { $0.isNewline || $0 == "\t" }) ? " " : run
                run = ""
            }
            result.append(character)
        }
        return result
    }

    /// The URL for input that names a host without a scheme: `quietweb.org`, `localhost:8080`,
    /// `192.168.1.4`, `[::1]:8080`, or any of those with a path, query or fragment attached.
    /// Non-ASCII hosts are converted to punycode by URLComponents.
    private static func bareHostURL(_ input: String) -> URL? {
        guard !input.contains(where: { $0.isWhitespace }) else { return nil }

        // Split the host part from whatever path, query or fragment follows it.
        let terminator = input.firstIndex(where: { "/?#".contains($0) }) ?? input.endIndex
        let authority = String(input[..<terminator])
        let rest = String(input[terminator...])
        guard !authority.isEmpty, !authority.hasPrefix(".") else { return nil }

        // Peel a trailing :port off the authority.
        var host = authority
        var port: Int?
        if authority.hasPrefix("[") {
            // A bracketed IPv6 literal, with an optional :port after the closing bracket.
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = String(authority[...close])
            let after = authority[authority.index(after: close)...]
            if !after.isEmpty {
                guard after.first == ":",
                    let value = Int(after.dropFirst()), value <= 65535
                else { return nil }
                port = value
            }
        } else if let colon = authority.lastIndex(of: ":") {
            let candidate = authority[authority.index(after: colon)...]
            let digitsOnly = !candidate.isEmpty && candidate.count <= 5 && candidate.allSatisfy(\.isNumber)
            if digitsOnly, let value = Int(candidate), value <= 65535 {
                host = String(authority[..<colon])
                port = value
            } else {
                // Colons that are not a port belong to a scheme or an unbracketed IPv6 literal;
                // neither is a bare host.
                return nil
            }
        }

        guard isValidHost(host) else { return nil }

        // The authority is already validated; URLComponents encodes the rest, punycode
        // included, and rejects a path that cannot live in a URL at all.
        let lowercaseAuthority = port.map { "\(host.lowercased()):\($0)" } ?? host.lowercased()
        guard let components = URLComponents(string: "https://" + lowercaseAuthority + rest) else {
            return nil
        }
        guard let url = components.url, url.host != nil, url.scheme == "https" else { return nil }
        return url
    }

    /// The lowercased scheme at the head of `input`, when the text before its first colon is
    /// shaped like one.
    private static func leadingScheme(_ input: String) -> String? {
        guard let colon = input.firstIndex(of: ":") else { return nil }
        let head = input[..<colon]
        guard let first = head.first, first.isLetter else { return nil }
        guard head.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return nil }
        return String(head).lowercased()
    }

    /// Whether `host` reads as a machine name: localhost, an IPv4 or bracketed IPv6 literal,
    /// or dot-separated labels ending in an alphabetic tail at least two characters long.
    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        if host.lowercased() == "localhost" { return true }
        if isIPv4(host) { return true }
        if host.hasPrefix("["), host.hasSuffix("]"), host.dropFirst().dropLast().contains(":") {
            return true
        }

        var labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // One trailing empty label is a fully qualified name: "example.com.".
        if labels.count > 1, labels.last?.isEmpty == true { labels.removeLast() }
        guard labels.count > 1 else { return false }
        guard let tail = labels.last, tail.count >= 2, tail.allSatisfy(\.isLetter) else { return false }
        return labels.allSatisfy(isValidLabel)
    }

    /// A DNS label: up to 63 letters or digits with inner hyphens. IDN labels count.
    private static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Four dot-separated numbers, each 0-255, without leading zeros.
    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber) else { return false }
            guard let value = Int(part), value <= 255 else { return false }
            return part.count == 1 || !part.hasPrefix("0")
        }
    }
}
