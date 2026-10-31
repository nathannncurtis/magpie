import Foundation

/// Formats the host the URL pill shows (03 · Chrome).
enum HostFormatter {

    /// The display form of a URL's host: bare, lowercased, a leading `www.` stripped and
    /// IDN labels in unicode. A label mixing scripts, the stuff of lookalike hosts, stays
    /// in punycode. An empty string when there is no host.
    static func host(for url: URL?) -> String {
        guard let raw = url?.host, !raw.isEmpty else { return "" }
        let host = raw.lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return
            bare
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { label -> String in
                guard label.hasPrefix("xn--") else { return String(label) }
                guard let decoded = Punycode.decodeLabel(String(label.dropFirst(4))),
                    IDNScript.isSingleScript(decoded)
                else { return String(label) }
                return decoded
            }
            .joined(separator: ".")
    }
}

/// A coarse script check for IDN labels: a label shows in unicode only when its letters
/// come from one script, allowing ASCII alongside Han, kana and Hangul as those
/// languages mix them. A letter from a script not listed keeps the label in punycode.
enum IDNScript {

    private enum Script { case latin, greek, cyrillic, armenian, hebrew, arabic, thai, cjk }

    static func isSingleScript(_ label: String) -> Bool {
        var scripts: Set<Script> = []
        var hasASCIILetter = false
        for scalar in label.unicodeScalars {
            let v = scalar.value
            if v < 0x80 {
                if scalar.properties.isAlphabetic { hasASCIILetter = true }
                continue
            }
            guard let script = script(of: v) else { return false }
            scripts.insert(script)
        }
        if scripts.count > 1 { return false }
        guard let only = scripts.first, hasASCIILetter else { return true }
        return only == .latin || only == .cjk
    }

    private static func script(of v: UInt32) -> Script? {
        switch v {
        case 0x00C0...0x024F, 0x1E00...0x1EFF: .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF: .greek
        case 0x0400...0x052F: .cyrillic
        case 0x0530...0x058F: .armenian
        case 0x0590...0x05FF: .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F: .arabic
        case 0x0E00...0x0E7F: .thai
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF: .cjk
        default: nil
        }
    }
}

/// RFC 3492 punycode decoding, for showing IDN hosts in unicode.
enum Punycode {

    private static let base = 36
    private static let tMin = 1
    private static let tMax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN = 128

    /// Decodes one label's encoded part (what follows the `xn--` prefix); nil when the
    /// label does not decode.
    static func decodeLabel(_ label: String) -> String? {
        guard !label.isEmpty else { return nil }
        let scalars = Array(label.unicodeScalars)
        var output: [Unicode.Scalar] = []
        var encoded = scalars
        if let delimiter = scalars.lastIndex(where: { $0 == "-" }) {
            output = Array(scalars[..<delimiter])
            encoded = Array(scalars[(delimiter + 1)...])
        }

        var n = initialN
        var index = 0
        var bias = initialBias
        var position = 0
        while position < encoded.count {
            let oldIndex = index
            var weight = 1
            var k = base
            while true {
                guard position < encoded.count else { return nil }
                guard let digit = digitValue(encoded[position]) else { return nil }
                position += 1
                index += digit * weight
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                guard weight <= 1_000_000_000 else { return nil }
                weight *= base - t
                k += base
            }
            bias = adapt(index - oldIndex, count: output.count + 1, firstTime: oldIndex == 0)
            let length = output.count + 1
            n += index / length
            index %= length
            guard let scalar = Unicode.Scalar(n) else { return nil }
            output.insert(scalar, at: index)
            index += 1
        }
        return String(String.UnicodeScalarView(output))
    }

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x61...0x7A: Int(scalar.value - 0x61)  // a-z
        case 0x41...0x5A: Int(scalar.value - 0x41)  // A-Z
        case 0x30...0x39: Int(scalar.value - 0x30 + 26)  // 0-9
        default: nil
        }
    }

    private static func adapt(_ delta: Int, count: Int, firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > (base - tMin) * tMax / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}
