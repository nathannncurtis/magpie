import SwiftUI
import UIKit

extension Color {
    /// An sRGB colour from a 0xRRGGBB value, at the given opacity.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// Every colour token, each with a light and a dark value that follow the system appearance.
enum Palette {

    // MARK: Brand

    /// Primary filled controls: toggles on, icon squares, primary buttons, the Search key.
    static let ink = dynamic(light: 0x101115, dark: 0xF6F5F1)
    /// Text and icons on `ink`. Ink and paper swap in dark.
    static let onInk = dynamic(light: 0xF6F5F1, dark: 0x101115)
    /// Brand paper.
    static let paper = dynamic(light: 0xF6F5F1, dark: 0x121316)
    /// The sheen, at 135 degrees, the same in light and dark. It goes on the collected thing only:
    /// the bead, citation dots, the installed check, the search-field ring.
    static let sheen = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(hex: 0x0D9488), location: 0),
            Gradient.Stop(color: Color(hex: 0x10B981), location: 0.55),
            Gradient.Stop(color: Color(hex: 0x6EE7B7), location: 1),
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Text accents: "Get", "Done" on paper screens, the swipe-to-restore background.
    static let teal = dynamic(light: 0x0D7F74, dark: 0x5EEAD4)

    // MARK: Neutrals

    /// Primary text.
    static let textPrimary = dynamic(light: 0x101115, dark: 0xF2F2EE)
    /// Secondary text.
    static let textSecondary = dynamic(light: 0x5B5D64, dark: 0xA3A5AC)
    /// Tertiary text.
    static let textTertiary = dynamic(light: 0x8A8C93, dark: 0x8E9097)
    /// Secondary body text on the mist.
    static let textOnMistSecondary = dynamic(light: 0x3F4B48, dark: 0xA9B9B5)
    /// Secondary meta text on the mist.
    static let textOnMistSecondaryMeta = dynamic(light: 0x4F5A57, dark: 0x93A3A0)
    /// Uppercase section labels on the mist.
    static let labelOnMist = dynamic(light: 0x2F5F58, dark: 0x7FB5AB)
    /// Separator lines on paper.
    static let separator = dynamic(light: 0x101115, lightOpacity: 0.07, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// Separator lines on the mist.
    static let separatorOnMist = dynamic(light: 0x102824, lightOpacity: 0.08, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// Solid content cards.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1D21)
    /// The Skim page background.
    static let skimBackground = dynamic(light: 0xF7F6F2, dark: 0x121316)
    /// The opened search or menu sheet.
    static let sheetSolid = dynamic(light: 0xF5F4F0, dark: 0x1A1B1F)
    /// Ghost buttons and inset tiles.
    static let fill = dynamic(light: 0x101115, lightOpacity: 0.06, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// The tile behind an emoji in a Skim section.
    static let emojiTile = dynamic(light: 0xEEECE6, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// The engine tag inside the search field.
    static let tag = dynamic(light: 0xF1F0EB, dark: 0xFFFFFF, darkOpacity: 0.08)
    /// A toggle in its off state.
    static let toggleOff = dynamic(light: 0xDADAD4, dark: 0xFFFFFF, darkOpacity: 0.16)
    /// A toggle's knob.
    static let toggleKnob = dynamic(light: 0xFFFFFF, dark: 0x101115)
    /// The default reading-bar tint when the site gives no colour.
    static let pageTintGlass = dynamic(
        light: 0xFFF6EE, lightOpacity: 0.55, dark: 0x2C241E, darkOpacity: 0.55)
    /// The background of a warning box.
    static let warningBackground = dynamic(
        light: 0xFBEFE6, dark: 0xE39272, darkOpacity: 0.14)
    /// Warning text.
    static let warningText = dynamic(light: 0x6B3A22, dark: 0xF0C3AE)
    /// Strong warning text.
    static let warningStrong = dynamic(light: 0x4A2412, dark: 0xFFD9C7)
    /// The scrim behind sheets. The light opacity sits anywhere in an 18-22% band; this is its middle.
    static let scrim = dynamic(light: 0x101816, lightOpacity: 0.20, dark: 0x000000, darkOpacity: 0.32)

    // MARK: Reading chrome

    /// The readable foreground over a light page tint: the spec's warm dark default.
    static let onLightPageTint = Color(hex: 0x3A2E26)
    /// The readable foreground over a dark page tint: the spec's dark default.
    static let onDarkPageTint = Color(hex: 0xF2F2EE)

    // MARK: Search

    /// The search field's inner fill.
    static let searchFieldFill = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.72, dark: 0x1D2023, darkOpacity: 1)

    // MARK: Settings

    /// The inner hairline on Settings' material groups.
    static let groupHairline = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.75, dark: 0xFFFFFF, darkOpacity: 0.08)

    // MARK: Onboarding

    /// An engine tile's glass fill.
    static let engineTile = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// An engine tile's fill once picked.
    static let engineTileSelected = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.88, dark: 0xFFFFFF, darkOpacity: 0.15)
    /// An engine tile's inner hairline.
    static let engineTileHairline = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.70, dark: 0xFFFFFF, darkOpacity: 0.14)
    /// The Other tile's glass fill.
    static let engineTileOther = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.30, dark: 0xFFFFFF, darkOpacity: 0)
    /// The Other tile's inset outline.
    static let engineTileOtherOutline = dynamic(
        light: 0x101115, lightOpacity: 0.14, dark: 0xFFFFFF, darkOpacity: 0.18)
    /// The plus-glyph square on the Other tile.
    static let engineTileOtherGlyph = dynamic(
        light: 0x101115, lightOpacity: 0.07, dark: 0xFFFFFF, darkOpacity: 0.10)

    // MARK: Skim pill

    /// The resting Skim pill's fill.
    static let skimPillFill = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.45, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// The resting Skim pill's border.
    static let skimPillBorder = dynamic(
        light: 0x101115, lightOpacity: 0.16, dark: 0xFFFFFF, darkOpacity: 0.18)
    /// The resting Skim pill's inner top highlight; gone in dark.
    static let skimPillHighlight = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.90, dark: 0xFFFFFF, darkOpacity: 0)

    // MARK: Tab cards

    /// The white ring around a tab card's snapshot.
    static let tabCardRing = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.38, dark: 0xFFFFFF, darkOpacity: 0.06)
    /// The hairline outside a tab card's ring.
    static let tabCardHairline = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.75, dark: 0xFFFFFF, darkOpacity: 0.16)
    /// The soft shadow under a tab card (01 Shadows).
    static let tabCardShadow = dynamic(
        light: 0x102824, lightOpacity: 0.35, dark: 0x000000, darkOpacity: 0.60)
}

private extension Palette {
    /// A colour that switches with the system appearance.
    static func dynamic(
        light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1
    ) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, opacity: darkOpacity)
                    : UIColor(hex: light, opacity: lightOpacity)
            })
    }
}

private extension UIColor {
    /// An sRGB colour from a 0xRRGGBB value, at the given opacity.
    convenience init(hex: UInt32, opacity: Double) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: CGFloat(opacity))
    }
}
