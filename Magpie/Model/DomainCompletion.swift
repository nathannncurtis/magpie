import Foundation

/// Finishes a half-typed address: the rest of a host that starts with what the field holds.
///
/// The user's own hosts (the sites they keep tabs and bookmarks on) come first, then a short
/// bundled list of well-known sites. Pure: the lists are handed in, so the matching tests
/// without the bundle.
struct DomainCompletion: Sendable, Equatable {

    /// Hosts from the user's tabs and bookmarks, most relevant first.
    var userHosts: [String]
    /// Well-known hosts, most familiar first.
    var popularHosts: [String]

    init(userHosts: [String] = [], popularHosts: [String] = Self.bundledHosts) {
        self.userHosts = userHosts.map(Self.normalized)
        self.popularHosts = popularHosts.map(Self.normalized)
    }

    /// The text that finishes `typed` into a host, or nil when nothing fits. `typed` has to
    /// look like the start of a bare host: no spaces, path, port or scheme, and it has to be
    /// shorter than the host it completes. A leading `www.` is typed through, never required.
    func suffix(for typed: String) -> String? {
        guard !typed.isEmpty, typed.allSatisfy(Self.isHostCharacter) else { return nil }
        let lowered = typed.lowercased()
        let withWWW = lowered.hasPrefix("www.")
        for host in userHosts + popularHosts {
            let candidate = withWWW ? "www." + host : host
            guard candidate.count > lowered.count, candidate.hasPrefix(lowered) else { continue }
            return String(candidate.dropFirst(lowered.count))
        }
        return nil
    }

    /// Lowercased, with a leading `www.` dropped, so one site is one entry.
    private static func normalized(_ host: String) -> String {
        let lowered = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }

    private static func isHostCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
    }

    /// The bundled well-known hosts, read once.
    static let bundledHosts: [String] = {
        guard let url = Bundle.main.url(forResource: "PopularDomains", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }()
}
