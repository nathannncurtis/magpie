import SwiftUI
import UIKit

/// The Fraunces display face, registered from the bundled variable font.
///
/// The display settings are fixed across the type table: weight 600, SOFT 100, WONK 0.
/// `.custom` cannot set variation axes, so the font is built through CoreText with the
/// variation attributes applied; the optical size axis is left to track the point size.
enum FrauncesFace {
    /// The registered family name.
    static let familyName = "Fraunces"

    /// The wght axis value.
    static let weight = 600.0
    /// The SOFT axis value: full softness.
    static let softness = 100.0
    /// The WONK axis value: never wonky.
    static let wonk = 0.0

    /// Variation axis tags, as stored in the variation dictionary.
    private enum AxisTag {
        static let opticalSize: FourCharCode = 0x6F70_737A  // opsz
        static let weight: FourCharCode = 0x7767_6874  // wght
        static let softness: FourCharCode = 0x534F_4654  // SOFT
        static let wonk: FourCharCode = 0x574F_4E4B  // WONK
    }

    /// The styled font at an exact size, with the display variation axes applied.
    static func ctFont(_ size: CGFloat) -> CTFont {
        let base = CTFontDescriptorCreateWithNameAndSize(familyName as CFString, size)
        let variations: [AnyHashable: Any] = [
            NSNumber(value: AxisTag.weight): NSNumber(value: weight),
            NSNumber(value: AxisTag.softness): NSNumber(value: softness),
            NSNumber(value: AxisTag.wonk): NSNumber(value: wonk),
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontVariationAttribute: variations] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// The styled font at `size`, scaled with Dynamic Type the way `style` scales.
    ///
    /// `Font(CTFont)` does not scale on its own, so the size is scaled through the text
    /// style's metrics before the font is built.
    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        let scaled = UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledValue(for: size)
        return Font(ctFont(scaled))
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

/// The type table. SF Pro through system text styles; Fraunces for display text.
enum Typography {

    // MARK: Fraunces

    /// The lowercase wordmark.
    static var wordmark: Font { FrauncesFace.font(46, relativeTo: .largeTitle) }
    /// Screen headers: Archive, Bookmarks, Settings, the onboarding question.
    static var screenTitle: Font { FrauncesFace.font(30, relativeTo: .largeTitle) }
    /// Screen headers set at the lower end of the 28-30 band, such as Mods.
    static var screenTitleSmall: Font { FrauncesFace.font(28, relativeTo: .largeTitle) }
    /// The Skim page title.
    static var skimTitle: Font { FrauncesFace.font(32, relativeTo: .largeTitle) }
    /// The Skim page title on the no-photo tier, at 40 pt.
    static var skimTitleNoPhotos: Font { FrauncesFace.font(40, relativeTo: .largeTitle) }
    /// The title over Skim working.
    static var skimWorkingTitle: Font { FrauncesFace.font(28, relativeTo: .title) }
    /// Section titles, such as "Popular this week".
    static var sectionTitle: Font { FrauncesFace.font(17, relativeTo: .headline) }

    // MARK: SF Pro

    /// Search field text.
    static let field = Font.body
    /// Suggestions, menu rows, list titles.
    static let row = Font.subheadline
    /// The title line of a row.
    static let rowTitle = Font.subheadline.weight(.semibold)
    /// Skim section text. Apply `bodyLineSpacing`.
    static let body = Font.subheadline
    /// Descriptions, sites, times.
    static let meta = Font.footnote
    /// Subtitles in rows, fine print.
    static let small = Font.caption
    /// Uppercase step and section labels. Apply `labelTracking` and uppercasing.
    static let label = Font.caption2.weight(.semibold)
    /// The engine tag and author lines.
    static let tag = Font.caption2.weight(.medium).monospacedDigit()
    /// Bar CTAs.
    static let buttonBar = Font.body.weight(.semibold)
    /// Pill buttons.
    static let buttonPill = Font.subheadline.weight(.semibold)

    // MARK: Tracking and line spacing

    static let wordmarkTracking: CGFloat = -0.5
    static let skimTitleTracking: CGFloat = -0.5
    /// Line-height multiple of the Skim title.
    static let skimTitleLineHeight: CGFloat = 1.04
    /// Extra spacing between lines of Skim section text.
    static let bodyLineSpacing: CGFloat = 3
    static let labelTracking: CGFloat = 0.8
}
