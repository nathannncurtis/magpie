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
    /// The sheen's middle stop, for the fills that must be one solid colour.
    static let sheenMid = Color(hex: 0x10B981)
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
    /// A switched-on toggle: `ink` in light, `teal` in dark, where the system knob's
    /// white would vanish on the near-white ink track.
    static let toggleOn = dynamic(light: 0x101115, dark: 0x5EEAD4)
    /// A toggle in its off state.
    static let toggleOff = dynamic(light: 0xDADAD4, dark: 0xFFFFFF, darkOpacity: 0.16)
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

    // MARK: Lists

    /// The ring around each favicon in a stack of sources on the mist, so the tiles read
    /// as one stack over the backdrop.
    static let faviconRingOnMist = dynamic(
        light: 0xE1F0EC, lightOpacity: 0.95, dark: 0x0C1211, darkOpacity: 1)

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

    // MARK: Mods

    /// The "Get" capsule's fill.
    static let getButtonFill = dynamic(
        light: 0xEEF0EE, dark: 0xFFFFFF, darkOpacity: 0.10)
    /// The install-from-URL field's fill.
    static let installURLFill = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.80, dark: 0xFFFFFF, darkOpacity: 0.08)
    /// A sheet's grabber.
    static let grabber = dynamic(
        light: 0x101115, lightOpacity: 0.18, dark: 0xFFFFFF, darkOpacity: 0.25)
    /// The featured card's sky, top of its 160-degree gradient.
    static let featuredPreviewTop = dynamic(light: 0xEAF1FE, dark: 0x18233B)
    /// The featured card's sky, bottom of its 160-degree gradient.
    static let featuredPreviewBottom = dynamic(light: 0xD7E5FD, dark: 0x0F1626)

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

    // MARK: Skim page

    /// Skim section text.
    static let skimBody = dynamic(light: 0x2B2D33, dark: 0xC4C6CB)
    /// The query in the Skim query bar.
    static let skimQueryText = dynamic(light: 0x3A3C44, dark: 0xD6D7DB)
    /// A source card's title.
    static let skimSourceTitle = dynamic(light: 0x1B1C21, dark: 0xE6E6E2)
    /// A source card's site line.
    static let skimSourceSite = dynamic(light: 0x5B5D64, dark: 0x8E9097)
    /// The working line on the mist, and the from-line on the no-photo tier.
    static let skimStatus = dynamic(light: 0x2F4F4A, dark: 0xA9C9C3)
    /// The divider inside the Skim control bar.
    static let skimControlDivider = dynamic(
        light: 0x101115, lightOpacity: 0.14, dark: 0xFFFFFF, darkOpacity: 0.16)
    /// The ring around a Skim source card.
    static let skimSourceRing = dynamic(
        light: 0x101115, lightOpacity: 0.05, dark: 0xFFFFFF, darkOpacity: 0.06)
    /// The shadow under a Skim source card.
    static let skimSourceShadow = dynamic(
        light: 0x101115, lightOpacity: 0.30, dark: 0x000000, darkOpacity: 0.35)

    // MARK: Menu

    /// A menu tile's fill.
    static let menuTile = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.5, dark: 0xFFFFFF, darkOpacity: 0.06)
    /// A menu group's fill.
    static let menuGroup = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xFFFFFF, darkOpacity: 0.06)
    /// The inner hairline on a menu tile and a menu group.
    static let menuHairline = dynamic(
        light: 0xFFFFFF, lightOpacity: 0.6, dark: 0xFFFFFF, darkOpacity: 0.08)
    /// A menu tile's icon and label.
    static let menuTileLabel = dynamic(light: 0x2B2D33, dark: 0xF2F2EE)

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
