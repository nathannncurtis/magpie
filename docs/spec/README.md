# Magpie design spec

The build reads this spec. Build exactly what is written here. If something is missing or two parts of the spec conflict, stop and ask; don't invent design.

Status: draft 1, 2026-10-30. Sources:

| What | Where |
|---|---|
| Design board: screens light + dark, edge states, Skim photo tiers, motion, brand, app icon | `docs/design/board.html` |
| Mark source | `../design/assets/mark-6d.svg` |
| App icon layers | `../design/assets/icon/` |

## Files

1. `01-foundations.md`: color, mist, type, spacing, radii, shadows, icons, the mark
2. `02-glass.md`: where Liquid Glass goes and the SwiftUI API for each case
3. `03-components.md`: every reusable piece, with sizes and states
4. `04-screens.md`: each screen, its layout and behavior, light and dark
5. `05-motion.md`: springs, the seven moments, Reduce Motion
6. `06-copy.md`: voice and every string on the boards
7. `07-assets.md`: icons, fonts, favicons, app icon
8. `08-open.md`: decisions still needed before the build reaches them

## Ground rules

- **Platform:** iPhone only, iOS 26 minimum. SwiftUI first; UIKit only where SwiftUI can't do the job (WKWebView hosting, keyboard-attached sheet if needed).
- **Glass:** Apple's real Liquid Glass only, through `glassEffect`, `GlassEffectContainer`, and system bars and sheets. Never build custom blur stacks that imitate glass. The web boards approximate Apple's glass; the app uses the real thing.
- **Sheen rule:** the sheen gradient goes only on the collected thing: the bead, citation dots, the installed check, the search-field ring. Never on chrome or backgrounds.
- **Vocabulary:** no Zen vocabulary anywhere, in code comments, strings or asset names. The mark is "the mark" or "the cradle".
- **Privacy:** no telemetry, no analytics SDK, no crash SDK, no network calls Magpie makes for itself (except filter-list and mod-directory updates).
- **Dark mode:** follows the system. Web pages are never inverted or force-darkened.
- **Units:** all sizes are in points at the 390 pt-wide board phone. Use these values as they are; let Dynamic Type scale text, not layout chrome.
- **Touch:** every control's hit area is at least 44 pt. Small controls reach it with invisible padding rather than a bigger face; rows and tiles grow only when scaled text needs the room.
