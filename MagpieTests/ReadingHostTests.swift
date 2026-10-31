import SwiftUI
import Testing
import UIKit

@testable import Magpie

@Suite("HostFormatter")
struct ReadingHostTests {

    @Test(
        "the host shows bare",
        arguments: [
            ("https://example.org/", "example.org"),
            ("https://example.org/a/page?q=1", "example.org"),
            ("https://www.quietweb.org/", "quietweb.org"),
            ("https://www.quietweb.org/notes/", "quietweb.org"),
            ("https://WWW.QuietWeb.ORG/", "quietweb.org"),
            ("https://127.0.0.1:8080/", "127.0.0.1"),
            ("http://example.org:81/", "example.org"),
            ("https://[::1]:8443/", "::1"),
            ("https://xn--bcher-kva.de/", "bücher.de"),
            ("https://xn--bcher-kva.xn--espaol-zwa.org/", "bücher.español.org"),
        ])
    func hosts(url: String, host: String) {
        #expect(HostFormatter.host(for: URL(string: url)) == host)
    }

    @Test(
        "no host shows an empty string",
        arguments: [
            nil,
            URL(string: "about:blank"),
            URL(string: "data:text/plain,hello"),
        ])
    func noHost(url: URL?) {
        #expect(HostFormatter.host(for: url) == "")
    }

    @Test("a label that does not decode stays as it is")
    func undecodableLabel() {
        #expect(HostFormatter.host(for: URL(string: "https://xn--.de/")) == "xn--.de")
    }

    @Test("a label mixing scripts stays in punycode")
    func mixedScript() {
        // Cyrillic а with Latin pple.
        #expect(HostFormatter.host(for: URL(string: "https://xn--pple-43d.com/")) == "xn--pple-43d.com")
        #expect(!IDNScript.isSingleScript("p\u{0430}ypal"))
        #expect(!IDNScript.isSingleScript("\u{03B1}\u{0430}"))
    }

    @Test("a single-script label shows in unicode")
    func singleScript() {
        #expect(HostFormatter.host(for: URL(string: "https://xn--d1acpjx3f.xn--p1ai/")) == "яндекс.рф")
        #expect(IDNScript.isSingleScript("bücher"))
        #expect(IDNScript.isSingleScript("東京abc"))
    }
}

@Suite("Punycode")
struct PunycodeTests {

    @Test(
        "one label decodes",
        arguments: [
            ("bcher-kva", "bücher"),
            ("espaol-zwa", "español"),
        ])
    func labels(encoded: String, decoded: String) {
        #expect(Punycode.decodeLabel(encoded) == decoded)
    }

    @Test(
        "an empty or malformed label does not decode",
        arguments: [
            "",
            "!!!",
            "bcher-kva999999999999999999",
        ])
    func rejects(label: String) {
        #expect(Punycode.decodeLabel(label) == nil)
    }
}

@Suite("PageBackgroundColor")
struct PageBackgroundColorTests {

    @Test(
        "an r,g,b string parses",
        arguments: [
            ("255, 255, 255", UInt32(0xFFFFFF)),
            ("13, 148, 136", UInt32(0x0D9488)),
            (" 13 , 148 , 136 ", UInt32(0x0D9488)),
        ])
    func parses(text: String, hex: UInt32) {
        let color = PageBackgroundColor.parse(text)
        #expect(color != nil)
        let resolved = UIColor(color ?? .clear).resolvedColor(with: UITraitCollection())
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: nil))
        let tolerance = CGFloat(1.0 / 255.0)
        #expect(abs(red - CGFloat((hex >> 16) & 0xFF) / 255) <= tolerance)
        #expect(abs(green - CGFloat((hex >> 8) & 0xFF) / 255) <= tolerance)
        #expect(abs(blue - CGFloat(hex & 0xFF) / 255) <= tolerance)
    }

    @Test(
        "anything else does not parse",
        arguments: [
            "",
            "1,2",
            "1,2,3,4",
            "300, 0, 0",
            "-1, 0, 0",
            "red",
            "rgb(1, 2, 3)",
        ])
    func rejects(text: String) {
        #expect(PageBackgroundColor.parse(text) == nil)
    }
}
