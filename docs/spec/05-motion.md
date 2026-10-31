# 05 · Motion

The live reference is the Motion section of the design board, `docs/design/`.

## Rules
1. **Springs, not timed curves.** Use SwiftUI `.spring(response:dampingFraction:)`.
2. **Fast.** Chrome transitions finish in about 0.5 s.
3. **Glass grows out of what you touched.** Nothing appears from nowhere.
4. **Chrome follows the finger.** Scroll-driven changes are interactive, not triggered by timers.
5. **Only confirmations bounce:** the install check and the bead dropping into the mark.
6. **Reduce Motion:** every moment becomes a crossfade of about 200 ms, and the ambient mist drift stops.

## Springs

| Name | Value | Use |
|---|---|---|
| `chrome` | `.spring(response: 0.3, dampingFraction: 0.88)` | All bar/sheet morphs, cards, bars arriving |
| `settle` | `.spring(response: 0.28, dampingFraction: 0.9)` | Scroll-collapse settle, re-flow |
| `snap` | `.spring(response: 0.34, dampingFraction: 0.72)` | The only bounce: installed check, bead drop |
| `smooth` | `.easeInOut(duration: 0.35)` | Mist clearing, crossfades |

Stagger lists 25–30 ms per item. Content inside a sheet starts 50 ms after the sheet does.

## The seven moments

### 01 · Open search
- **Trigger:** tap the URL pill.
- **Morph:** one shape in the `GlassEffectContainer`. The bar widens to the edges, rises, and becomes the search sheet; the keyboard rises with it as one piece. Spring: `chrome`, about 0.5 s.
- **Fill:** the glass turns fully solid (`sheetSolid`) while it grows. Nothing shows through the open sheet.
- **Content:** the URL row fades out over 100 ms. The field fades in 50 ms after the morph starts; the rows stagger 30 ms each as the list arrives, and every later change animates the rows it adds or drops.
- **Dismiss:** swipe down or tap the scrim; VoiceOver's two-finger scrub does the same. The whole sheet follows the swipe down, glass and all, and shrinks back into the bar on the same spring.

### 02 · Bar into menu
- **Trigger:** tap •••.
- **Morph:** same as 01, but the bar row stays pinned at the base and never moves. The menu grows up from it and hugs its content. Spring: `chrome`; fill turns solid.
- **Content:** groups stagger in from the bottom up, 25 ms apart, rising 12 pt as they fade in.
- **••• state:** shows the pressed fill while the menu is open.
- **Dismiss:** tap •••, swipe down, or tap the page; VoiceOver's two-finger scrub does the same. The whole sheet follows the swipe down, glass and all, and shrinks back into the bar on the same spring.

### 03 · Tab stack
- **Trigger:** tap the tab count.
- **Page → card:** the page scales to 0.62 and its corner radius grows to 26 (screen) as it lands. Spring: `chrome`.
- **Neighbours:** slide in from the sides 40 ms behind. Labels and the bottom row fade in.
- **Close:** fling up past 30% of the height or faster than 500 pt/s. The card follows the finger, then flies off. The next card re-flows over with `settle`.
- **Open:** the tapped card grows back to full screen with `chrome`.

### 04 · Skim finishes
- **Trigger:** the last source is read.
- **Sequence:**
  1. The mark scales to 0.7 and fades, and the mist clears to paper (`smooth`, 350 ms).
  2. Photos fade in, settling from 1.04 scale, 70 ms apart.
  3. The title, then each section, rise 8 pt as they fade in, 70 ms apart.
  4. The query bar drops in and the control bar rises (`chrome`).
- **Total:** about 1.4 s.
- **Reduce Motion:** one crossfade straight to the page.

### 05 · Chrome on scroll
- **Trigger:** scroll direction, not scroll position.
- **Collapse:** after 24 pt of downward scroll, the bar goes from 60 tall to a 38-tall pill showing only the host. The side buttons fade out; each keeps its full hit width while it can still be tapped, then its slot folds away.
- **Expand:** any upward scroll, or reaching the end of the page, brings the full bar back.
- **Tracking:** progress follows the scroll offset interactively, then settles with `settle` (about 0.4 s).
- **Slim pill:** tapping it expands the bar and opens search.
- **Reduce Motion:** the bar stays full size.

### 06 · Mod installed
- **Trigger:** tap Install.
- **Button:**
  1. A 0.96 press scale.
  2. The label is replaced by a 24 pt `MarkSpinner` while the mod is fetched and checked, for at least 600 ms.
  3. A tick replaces the spinner (`snap`), with a success haptic (`.sensoryFeedback(.success)`).
- **Sheet out:** the sheet drops away (`chrome`, about 0.5 s) and the blur behind it clears along with it. The preview card and warning stay up through the spinner and the tick.
- **Lands:** a confirmation row rises 8 pt as it fades in, carrying the `InstalledCheck` pop (`snap`). The "Installed · N" segment ticks over.
- **Directory installs (Get) never switch segments:** the row's Get becomes the popping `InstalledCheck` in place.

### 07 · Launch
- **Trigger:** a cold launch with no open tabs. Later launches restore the last tab, with no animation.
- **Sequence:**
  1. The mist fades up from paper (250 ms).
  2. The mark draws over 700 ms, and the bead drops in at the end (`snap`).
  3. The whole stage — paper, mist and mark — fades as the search sheet rises from the bottom (`chrome`), the mark rising 40 pt within it. Under Reduce Motion it is one 200 ms crossfade.
- **Total:** about 1.9 s. Tapping skips it.
- **Reduce Motion:** the mark appears whole and the sheet fades in.

## Ambient
- **Skim working mist drift:** see 01 Mist. Stops under Reduce Motion.
- **Search field caret:** system.
- **No other ambient motion anywhere.**
