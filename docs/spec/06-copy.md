# 06 · Copy

## Voice
- **Terse and plain.** Write in short sentences; semicolons are fine.
- **No exclamation marks.** None anywhere.
- **No hype.** No "AI-powered", no "supercharge", no "magic".
- **AI framing:** never call Magpie anti-AI, and never call it an AI browser.
- **Vocabulary:** no Zen vocabulary.
- **Errors:** say what happened and what to do, in one line.

Put all strings in `Localizable.xcstrings`; English only at 1.0.

## Strings on the boards

| Where | String |
|---|---|
| Welcome | "magpie" · "The browser you shape." · "Get started" · "Free and open source. No account. Nothing collected." |
| Engine picker | "Where should searches go?" · "Pick one; you can switch any time from the menu." · tile notes (04 · 07b) · "Other" / "Any, by search URL" · "Continue with {engine}" |
| Search | Skim pill: "Skim" |
| Menu | Tiles: "Skim" · "Bookmark" · "Share" · "Mods"; rows: "Block ads & trackers" · "Block cookie banners" · "Archive inactive tabs" / "After 1 day" · "Search engine" · "Skim for me" |
| Tabs | "Archived · {n}" · "{n} open" |
| Skim working | "Reading {n} pages" · "Cancel" |
| Skim page | "From {n} pages · read on this phone" · "Sources" · "Dig deeper · up to 10" |
| Archive | "Archive" · "Yesterday" · "Earlier this week" · "Search archived tabs" · "Done" |
| Bookmarks | "Bookmarks" · "Edit" · "Folders" · "Recently added" · "New folder" · "Skim page · {folder}" · "Search bookmarks" |
| Settings | "Settings" · "Make Magpie your default browser" / "Links from other apps open here. Set in iOS Settings." / "Open" · section labels: "Search", "Privacy", "Tabs & more" · rows (04 · 11) · "Updated {time} ago" · "iOS Passwords" · "About Magpie" · "{version} · MPL-2.0" |
| Mods | "Mods" · "Directory" · "Installed · {n}" · "Popular this week" · "Get" · "Install from URL" |
| Install sheet | "Install from URL" · "Runs on" · "Can" · "Not in the directory." · "Nobody has reviewed this mod. Only install it if you trust where it came from." · "Cancel" · "Install" · confirmation: "Installed just now" |
| Mod author line | "{script\|filter list} · {author}" |

## Edge states
| Where | String |
|---|---|
| Mods · Installed | "Not reviewed" · "{type} · {author} · from a link" · "Swipe a mod left to remove it. Off keeps it, but it stops running." |
| Mods · Directory install failed | "{name} didn't install. Tap Get to try again." (drafted, `// COPY: review`) |
| Empty Archive | "Nothing archived yet" / "Tabs you leave alone for a day land here, and stay for 30 days." |
| Empty Bookmarks | "No bookmarks yet" / "Tap Bookmark in the menu to keep a page here." (drafted, `// COPY: review`) |
| Empty Installed | "Nothing installed" / "Mods from the directory or a link show up here." (drafted, `// COPY: review`) |
| Offline | "Can't reach {host}" / "You're offline. It'll load when you're back." · "Try again" |
| Skim failed | "Only {n} of {m} pages could be read. That's not enough to Skim." · "Show search results" · "Try again" |
| Install failed (web page) | "That's a web page, not a mod." / "Magpie needs a link to a userscript (ending in .user.js) or a filter list." |

## Still to write
These strings are not on the boards and need wording in the same voice:
- other page-load errors (server error, bad certificate, blocked by a filter list)
- other install failures (download failed, a script with no @match)
- the Other-engine URL prompt
- the About screen

The build drafts them in the voice above and marks each one `// COPY: review` for review.
