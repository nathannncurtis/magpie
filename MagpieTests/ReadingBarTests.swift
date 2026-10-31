import SwiftUI
import Testing
import UIKit

@testable import Magpie

private func components(_ color: Color, _ scheme: ColorScheme) -> (CGFloat, CGFloat, CGFloat) {
    let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: nil))
    return (red, green, blue)
}

private func expectClose(
    _ actual: (CGFloat, CGFloat, CGFloat), _ hex: UInt32
) {
    let tolerance = CGFloat(1.0 / 255.0)
    #expect(abs(actual.0 - CGFloat((hex >> 16) & 0xFF) / 255) <= tolerance)
    #expect(abs(actual.1 - CGFloat((hex >> 8) & 0xFF) / 255) <= tolerance)
    #expect(abs(actual.2 - CGFloat(hex & 0xFF) / 255) <= tolerance)
}

@Suite("ReadableForeground")
struct ReadableForegroundTests {

    @Test("the default glass tint takes the warm dark in light, the off-white in dark")
    func defaultTint() {
        let light = ReadableForeground.foreground(for: Palette.pageTintGlass, scheme: .light)
        expectClose(components(light, .light), 0x3A2E26)
        let dark = ReadableForeground.foreground(for: Palette.pageTintGlass, scheme: .dark)
        expectClose(components(dark, .dark), 0xF2F2EE)
    }

    @Test(
        "a white page tint reads the warm dark, a black one the off-white",
        arguments: [
            ColorScheme.light, .dark,
        ])
    func extremes(scheme: ColorScheme) {
        #expect(
            ReadableForeground.foreground(for: .white, scheme: scheme)
                == Palette.onLightPageTint)
        #expect(
            ReadableForeground.foreground(for: .black, scheme: scheme) == Palette.onDarkPageTint)
    }

    @Test("a dark page tint reads the off-white")
    func darkTint() {
        let teal = Color(hex: 0x0D9488)
        #expect(!ReadableForeground.isLight(teal, scheme: .light))
        #expect(ReadableForeground.foreground(for: teal, scheme: .light) == Palette.onDarkPageTint)
    }

    @Test("the tint's opacity does not change the foreground")
    func opacityIgnored() {
        let faint = Color(hex: 0xFFFFFF, opacity: 0.1)
        #expect(ReadableForeground.foreground(for: faint, scheme: .light) == Palette.onLightPageTint)
    }

    @Test("a white page's tint reads the warm dark in dark too: the glass shows the white page")
    func whitePageInDark() {
        let tint = Color.white.opacity(0.55)
        #expect(ReadableForeground.foreground(for: tint, scheme: .dark) == Palette.onLightPageTint)
    }
}

@Suite("TabCount")
struct TabCountTests {

    @Test(
        "the label counts up to 99",
        arguments: [
            (0, "0"),
            (1, "1"),
            (2, "2"),
            (42, "42"),
            (99, "99"),
        ])
    func counts(count: Int, label: String) {
        #expect(TabCount.label(for: count) == label)
    }

    @Test("above 99 the label is the infinity sign", arguments: [100, 583, 10_000])
    func overflows(count: Int) {
        #expect(TabCount.label(for: count) == "∞")
    }
}
