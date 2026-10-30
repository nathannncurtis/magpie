# 02 · Glass

Magpie uses Apple's Liquid Glass and nothing else that imitates it. Glass is for **controls that float over content**. Content itself is never glass.

## Where glass goes

| Surface | API | Notes |
|---|---|---|
| Reading bar (back, URL, tabs, •••) | `.glassEffect(.regular.tint(pageTint), in: .capsule)` inside a `GlassEffectContainer` | `pageTint` = the page's `themeColor` or `underPageBackgroundColor` at about 55% (fallback `pageTintGlass`). The bar's buttons are plain, not separately glassed. |
| Bar → search sheet, bar → menu | Same `GlassEffectContainer`, `glassEffectID("chrome", in: ns)` on bar and sheet | One shape that morphs (05). When open, the sheet is **fully solid** `sheetSolid`, with glass only during the morph. |
| Launch search sheet (cold start on the mist) | `.glassEffect(.regular, in: UnevenRoundedRectangle(top: 38))` | Field, suggestions and keyboard read as one piece. This sheet sits on the mist, not a page, so it stays glass. |
| Tab stack: Archived chip | `.glassEffect(.regular.interactive(), in: .capsule)` | |
| Tab stack: + button | `.buttonStyle(.glassProminent)`, tinted `ink` | Ink glass; it flips to paper in dark |
| Skim query bar (top) | `.glassEffect(.regular, in: .capsule)` | Floats over the photo mosaic |
| Skim control bar ("Dig deeper · up to 10" \| share) | `.glassEffect(.regular.interactive(), in: .capsule)` | One bar, split by a 1 pt divider |
| Mods segmented control | glass capsule, selected segment solid `card` | |
| Bottom search pill (Archive, Bookmarks) | `.glassEffect(.regular.interactive(), in: .capsule)` + scroll-edge effect | Use iOS 26 `.scrollEdgeEffectStyle(.soft, for: .bottom)` on the list instead of drawing a fade |
| "Install from URL" footer pill (Mods) | `.glassEffect(.regular.interactive(), in: .capsule)` | |
| Engine tiles (first launch) | `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))` | Selected tile: 2 pt `ink` ring, a check badge, and a more opaque fill |
| Welcome "Get started", engine "Continue" | `.buttonStyle(.glassProminent)` tinted `ink` | |

## Where glass never goes

- **Content cards:** mod cards, the featured card, source cards, tab cards, folder tiles and the Skim page body. These are solid `card`.
- **List rows:** they sit directly on the mist (Archive, Bookmarks).
- **Settings groups:** these use the system material `.regularMaterial`, not glass and not white. The groups stay as boxes, frosted rather than white.
- **Inside a sheet:** menu tiles and groups are inset fills (`card` at 50–55%, or a white 0.75 pt inner hairline in light mode), not nested glass.

## Sheets

- **Install from URL:** a system `.sheet` with `.presentationDetents([.large])`. iOS 26 sheets are glass at partial height and turn opaque when expanded, which matches the solid rule.
  - Behind it, the real Mods page stays visible, lightly blurred: about 2.5 pt blur plus `scrim`.
  - Use `.presentationBackgroundInteraction(.disabled)`, with no stock grey dimming beyond the scrim.
- **Menu and search:** not system sheets. Both morph out of the bar (see the table above), so build them as custom views in the same glass container.

## Rules

1. Glass grows out of what you touched. A sheet from the bar comes from the bar.
2. One glass layer at a time. Never put glass on glass.
3. Text on glass is `textPrimary` or `textSecondary`, never tinted.
4. In dark mode the glass goes smoky: the system does this, so don't override it.
5. Never fake glass with `.ultraThinMaterial` plus a stroke where `glassEffect` applies.
