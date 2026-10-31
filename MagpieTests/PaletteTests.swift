import SwiftUI
import Testing
import UIKit

@testable import Magpie

/// One colour token with its expected values, straight from the foundations table.
fileprivate struct TokenSpec: Sendable {
    let name: String
    let color: Color
    let light: UInt32
    let lightOpacity: Double
    let dark: UInt32
    let darkOpacity: Double

    init(
        _ name: String, _ color: Color,
        light: UInt32, _ lightOpacity: Double = 1,
        dark: UInt32, _ darkOpacity: Double = 1
    ) {
        self.name = name
        self.color = color
        self.light = light
        self.lightOpacity = lightOpacity
        self.dark = dark
        self.darkOpacity = darkOpacity
    }
}

private let tokens: [TokenSpec] = [
    TokenSpec("ink", Palette.ink, light: 0x101115, dark: 0xF6F5F1),
    TokenSpec("onInk", Palette.onInk, light: 0xF6F5F1, dark: 0x101115),
    TokenSpec("onSheen", Palette.onSheen, light: 0x101115, dark: 0x101115),
    TokenSpec("paper", Palette.paper, light: 0xF6F5F1, dark: 0x121316),
    TokenSpec("teal", Palette.teal, light: 0x0D7A70, dark: 0x5EEAD4),
    TokenSpec("textPrimary", Palette.textPrimary, light: 0x101115, dark: 0xF2F2EE),
    TokenSpec("textSecondary", Palette.textSecondary, light: 0x5B5D64, dark: 0xA3A5AC),
    TokenSpec("textTertiary", Palette.textTertiary, light: 0x6D6F76, dark: 0x8E9097),
    TokenSpec("textOnMistSecondary", Palette.textOnMistSecondary, light: 0x3F4B48, dark: 0xA9B9B5),
    TokenSpec("textOnMistSecondaryMeta", Palette.textOnMistSecondaryMeta, light: 0x4F5A57, dark: 0x93A3A0),
    TokenSpec("labelOnMist", Palette.labelOnMist, light: 0x2F5F58, dark: 0x7FB5AB),
    TokenSpec("separator", Palette.separator, light: 0x101115, 0.07, dark: 0xFFFFFF, 0.07),
    TokenSpec("separatorOnMist", Palette.separatorOnMist, light: 0x102824, 0.08, dark: 0xFFFFFF, 0.07),
    TokenSpec("card", Palette.card, light: 0xFFFFFF, dark: 0x1C1D21),
    TokenSpec("skimBackground", Palette.skimBackground, light: 0xF7F6F2, dark: 0x121316),
    TokenSpec("sheetSolid", Palette.sheetSolid, light: 0xF5F4F0, dark: 0x1A1B1F),
    TokenSpec("fill", Palette.fill, light: 0x101115, 0.06, dark: 0xFFFFFF, 0.07),
    TokenSpec("emojiTile", Palette.emojiTile, light: 0xEEECE6, dark: 0xFFFFFF, 0.07),
    TokenSpec("tag", Palette.tag, light: 0xF1F0EB, dark: 0xFFFFFF, 0.08),
    TokenSpec("toggleOff", Palette.toggleOff, light: 0xDADAD4, dark: 0xFFFFFF, 0.16),
    TokenSpec("pageTintGlass", Palette.pageTintGlass, light: 0xFFF6EE, 0.55, dark: 0x2C241E, 0.55),
    TokenSpec("warningBackground", Palette.warningBackground, light: 0xFBEFE6, dark: 0xE39272, 0.14),
    TokenSpec("warningText", Palette.warningText, light: 0x6B3A22, dark: 0xF0C3AE),
    TokenSpec("warningStrong", Palette.warningStrong, light: 0x4A2412, dark: 0xFFD9C7),
    TokenSpec("scrim", Palette.scrim, light: 0x101816, 0.20, dark: 0x000000, 0.32),
]

/// The token's components under one appearance.
private func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    return (red, green, blue, alpha)
}

/// The expected components of a hex colour at an opacity.
private func rgba(_ hex: UInt32, _ opacity: Double) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    (
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        CGFloat(opacity)
    )
}

private func expectClose(
    _ actual: (CGFloat, CGFloat, CGFloat, CGFloat),
    _ expected: (CGFloat, CGFloat, CGFloat, CGFloat)
) {
    // One part in 255: the whole value an 8-bit channel can move.
    let tolerance = CGFloat(1.0 / 255.0)
    #expect(abs(actual.0 - expected.0) <= tolerance)
    #expect(abs(actual.1 - expected.1) <= tolerance)
    #expect(abs(actual.2 - expected.2) <= tolerance)
    #expect(abs(actual.3 - expected.3) <= tolerance)
}

@Suite("Palette")
struct PaletteTests {

    @Test("every token resolves to the spec colour in light and in dark", arguments: tokens)
    fileprivate func tokenResolves(spec: TokenSpec) {
        expectClose(rgba(spec.color, .light), rgba(spec.light, spec.lightOpacity))
        expectClose(rgba(spec.color, .dark), rgba(spec.dark, spec.darkOpacity))
    }
}
