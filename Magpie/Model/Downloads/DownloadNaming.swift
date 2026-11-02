import Foundation
import UniformTypeIdentifiers

/// How a download is named on disk, and which responses are downloads in the first place.
/// Pure, so the rules are tested without a network.
enum DownloadNaming {

    static let fallbackName = "download"
    /// The longest a name may run, extension included.
    static let maxLength = 120

    /// Whether a response's Content-Disposition asks for a save rather than a show.
    static func isAttachment(disposition: String?) -> Bool {
        guard let disposition else { return false }
        let kind = disposition.split(separator: ";").first ?? ""
        return kind.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
    }

    /// The name a download is saved under: the server's suggestion, else the address's last
    /// path part, else a plain fallback; given an extension from the type when it has none.
    static func name(suggested: String?, url: URL?, mimeType: String?) -> String {
        var name =
            sanitized(suggested)
            ?? sanitized(url?.lastPathComponent.removingPercentEncoding)
            ?? fallbackName
        if (name as NSString).pathExtension.isEmpty,
            let mimeType,
            let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension
        {
            name += "." + ext
        }
        return clamped(name)
    }

    /// A name safe to write: no path separators, control characters or leading dots. Nil
    /// when nothing is left.
    static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let replaced = String(
            raw.unicodeScalars.map { scalar -> Character in
                if scalar == "/" || scalar == ":" || scalar == "\\"
                    || CharacterSet.controlCharacters.contains(scalar)
                {
                    return "_"
                }
                return Character(scalar)
            })
        var trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `name` unless a file of that name is already there; then "name 2.ext", "name 3.ext"
    /// and on. Names compare without regard to case, as the volume does.
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    /// Cuts a long stem, keeping the extension.
    private static func clamped(_ name: String) -> String {
        guard name.count > maxLength else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let room = max(maxLength - ext.count - 1, 1)
        return ext.isEmpty ? String(name.prefix(maxLength)) : String(stem.prefix(room)) + "." + ext
    }

    /// The cookies a request to `url` carries, from a store's whole jar.
    static func cookies(_ jar: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let isSecure = url.scheme?.lowercased() == "https"
        let path = url.path.isEmpty ? "/" : url.path
        return jar.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "."))
            let domainMatches = host == domain || host.hasSuffix("." + domain)
            return domainMatches && path.hasPrefix(cookie.path) && (isSecure || !cookie.isSecure)
        }
    }
}
