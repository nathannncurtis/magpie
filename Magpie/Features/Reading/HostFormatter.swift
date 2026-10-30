import Foundation

/// Formats the host the URL pill shows (03 · Chrome).
enum HostFormatter {

    /// The display form of a URL's host: bare, lowercased, a leading `www.` stripped and
    /// IDN labels in unicode. An empty string when there is no host.
    static func host(for url: URL?) -> String {
        guard let raw = url?.host, !raw.isEmpty else { return "" }
        let host = raw.lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return
            bare
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { label -> String in
                guard label.hasPrefix("xn--") else { return String(label) }
                return Punycode.decodeLabel(String(label.dropFirst(4))) ?? String(label)
            }
            .joined(separator: ".")
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
