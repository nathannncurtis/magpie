# 07 · Assets

| Asset | Source | Notes |
|---|---|---|
| Mark (stroke, bead, tile) | `docs/design/assets/mark-6d.svg` | PDF vectors; stroke as a template image |
| App icon | `docs/design/assets/icon/` layers: background (paper, ink), stroke, bead | Locked 2026-10-30. Light: paper tile, ink stroke, sheen bead. Dark: near-black tile (#16181C → #060708), paper stroke, a brighter bead (#14B8A6 → #34D399 → #A7F3D0). Clear and tinted: stroke white 100%, bead white 60%. Assemble in Icon Composer: three layers, translucency off, specular on, a slight shadow on the bead. |
| Fraunces | Google Fonts, variable, OFL | Bundle `Fraunces[SOFT,WONK,opsz,wght].ttf`; register in Info.plist |
| SF Symbols | System | See 01 Icons |
| Cookie icon | Custom | 20 pt grid, 2 pt stroke, rounded caps; matches SF Symbols medium |
| Drawn mod icons | Board 06 | Simple white glyph on a 160° gradient tile; each directory mod supplies its own icon in the index |
| Engine favicons | Bundled PNG at 3x (30 pt → 90 px) | Google, DuckDuckGo, Brave, Kagi, Ecosia, Startpage, Bing; generic for Other |
| Site favicons | Fetched from the site itself (`<link rel=icon>` / apple-touch-icon), cached on device | Never fetch them through a third-party favicon service, which would leak browsing |
| Filter lists | Downloaded on first run, auto-updated | EasyList / EasyPrivacy-class for ads & trackers; a cookie-banner list (e.g. EasyList Cookie) on its own toggle. Nothing bundled |
