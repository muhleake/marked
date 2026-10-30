# Marked — Build Progress

Source of truth: `docs/SPEC.md`. Each phase is ticked only when build + tests + its own verification pass.

- [x] Phase S — Environment check and setup — Xcode 27.1 (27A9275), Swift 6.4, macOS 27.0.1, xcodegen 2.46.0 via brew; headless build + ad-hoc signing + XCTest smoke test passed.
- [x] Phase 0 — Scaffold and CLAUDE.md — project.yml (XcodeGen), swift-cmark gfm linked, Makefile, stub app launches to one 900×600 window; build + 1 test pass.
- [x] Phase 1 — Behavior reference — menus, document lifecycle, plain text, encodings, find, spelling, print and scope documented in docs/BEHAVIOR.md.
- [x] Phase 2 — Document model, window, editor — NSDocument (.md/.markdown/.mdown/.txt), UTF-8/UTF-16/1252 read + UTF-8 write with CRLF kept, split window w/ tabs, SF Mono editor (substitutions off, find bar, spellcheck), menus in code. 32 tests pass: open/edit/save/reopen, revert, duplicate, Open Recent menu, undo, CRLF, 1252.
- [x] Phase 3 — Live preview — cmark-gfm (table/strikethrough/tasklist/autolink/tagfilter + footnotes, sourcepos) off-main, WKWebView shell updated in place via isolated-world JS, CSP blocks page script, content rules block all non-file loads, links open externally, relative images resolve, ⌥⌘P cycles layouts, Treat as Markdown, scroll sync. 5,000-line doc: cmark 4.6 ms median warm (17 ms cold), 0.26 ms main-thread per edit, ~210 ms edit→visible incl. 150 ms debounce. 55 tests pass.
- [x] Phase 4 — Toolbar and Markdown commands — pure MarkdownCommands (inline wrap/unwrap incl. ***, _, cursor-in-span; line prefixes w/ heading replace, list renumber, task/quote; fences; link/image; table; rule) applied as one undo step; customizable NSToolbar (SF Symbols, heading dropdown, layout segmented control); Format menu with spec shortcuts. 79 command tests + 7 UI tests; 54 menu shortcuts, no duplicates.
- [x] Phase 5 — Editor polish — MarkdownHighlighter (system colors, color/weight only; per-paragraph re-tint, full re-tint only when fences change; 5,000 lines: 48 ms full, 1.5 ms per keystroke), list continuation (-,*,+,1.,1),- [ ]; empty item ends list; skips code fences), Tab/Shift-Tab indent/outdent, status bar (words · characters · lines, counted off-main), Format ▸ Bigger ⌘+ (also ⌘=) / Smaller ⌘− / Default Size ⌘0 persisted. 173 tests pass.
- [x] Phase 6 — Finish and install — Print/Export as PDF render the preview offscreen (paginated, light, backgrounds kept; .txt prints raw), Page Setup via NSDocument printInfo, Edit ▸ Copy as HTML, Settings (font size, default layout, preview theme), external-change reload prompt (file presenter + check on activate), per-window layout/Treat-as-Markdown restoration. `make install` → /Applications/Marked.app (1.5 MB, ad-hoc). 187 tests pass.

- Phase 4 shortcut notes: no conflicts remain among the 54 menu key equivalents (checked with AppKit's runtime items present). ⌥⌘T = Table, so View ▸ Show Toolbar has no shortcut. Shifted shortcuts (⇧⌘8/7/./-) are declared by their shifted character (*, &, >, _), which is what AppKit matches; that assumes a US keyboard layout. Formatting is disabled in plain .txt windows (until Treat as Markdown) and in Preview Only.

## Additions after Phase 6

- 2026-10-27 — Underline (⌘U, `<u>`), Highlight (⇧⌘H, `<mark>`), Text Color menu (8 presets + Remove Color, `<span style="color: …">`) in the toolbar and Format menu, by request. Markdown has no syntax for these, so they're inline HTML that the preview, print/PDF and Copy as HTML render; the editor dims the tags and shows colored text in its color. New enum cases were appended so saved toolbar layouts keep their identifiers. Dark-mode highlight made stronger. App icon bundled as `Marked/Resources/AppIcon.icns`. 201 tests pass.

- 2026-10-30 — Repo prepared for GitHub: README and screenshot, `docs/REPORT.md` with fresh measurements, swift-cmark pinned to a revision, one type per file for `TextCounts`, `TextColor`, `ContentRules` and `PreviewLayout`, tests split into one class per file and phase-named test files renamed. No behavior changes. 202 tests pass.

## Acceptance tests

Run 2026-10-25 against `/Applications/Marked.app` (Release, ad-hoc) and the in-process test suite (187 tests). "Auto" = verified by an automated test or measurement; "Manual" = needs a person at the keyboard (no Accessibility/Automation permission was available to drive the GUI).

**Files**

- [~] Double-click `.md`/`.txt` opens Marked — `.md`/`.mdown` already default to Marked (`open file.md` launches it); `.txt` still opens in the system's default app until the default app is changed with Get Info ▸ Open with ▸ Change All. Marked is offered for both. **Manual step pending.**
- [x] ⌘N → type → ⌘S saves `Untitled.md` as UTF-8 — Auto (new doc type = Markdown, extension md, bytes are UTF-8).
- [x] CRLF file saves back as CRLF; Windows-1252 opens clean — Auto (byte-for-byte CRLF round trip; 1252 smart quotes/€ decode).
- [~] Quit with unsaved edits, relaunch: windows and edits restored — Auto for the parts: autosave in place on, windows restorable, layout/Treat-as-Markdown round-trip through restorable state, launch fallback when a restored file is gone. Full quit/relaunch with typing not driven. **Manual check.**
- [~] File ▸ Revert To ▸ Browse All Versions — Auto: Revert restores saved text in the editor; AppKit adds the Revert To submenu because autosavesInPlace is on. Versions browser UI not driven (Versions can't store revisions for files in the temp folder the tests use). **Manual check.**
- [x] Editing the file in another app triggers a reload prompt — Auto (a separate `/bin/sh` process rewrites the file; the file presenter fires and the prompt is shown once; Reload / Keep This Version / identical-content cases).

**Editing**

- [x] Every toolbar button and shortcut applies, toggles off, undoes in one ⌘Z — Auto (all 19 actions via real Format menu items; one undo restores pre-action text separately from earlier typing; redo; toggle-off; every shortcut matched through `NSMenu.performKeyEquivalent`; 54 shortcuts, no duplicates).
- [x] Return continues bullets, numbers (incrementing), tasks; Return on empty item ends the list — Auto.
- [x] ⌘F find bar, Find & Replace, spell-check underlines — Auto (find bar and replace bar open; spell check on, underlines visible in snapshots).
- [x] Typing "quotes" doesn't produce curly quotes — Auto (real key events into the editor).

**Preview**

- [x] Headings, tables, task lists, strikethrough, code blocks, relative images, autolinks render — Auto (DOM checks; relative PNG loads with naturalWidth 1).
- [x] Clicking a link opens the browser; the preview never navigates — Auto (real `click()` in the page → external opener, page URL unchanged).
- [x] Preview follows system dark mode — Auto (light/dark snapshots; Settings can force Light/Dark).
- [x] ⌥⌘P cycles Split / Editor / Preview; `.txt` starts editor-only; Treat as Markdown shows preview — Auto.
- [x] 5,000-line file: no visible lag; preview keeps scroll position — Auto/measured: 0.26 ms main-thread per edit + 1.5 ms re-tint; cmark 4.6 ms (warm); preview updated in place (no reload).

**Lightness**

- [x] Cold launch to window under ~1 s — measured 434–483 ms (5 launches of the installed app, `open` → first window). The very first launch right after install took >10 s (macOS's one-time check of a newly copied, ad-hoc-signed app); later launches are fast.
- [x] ~0% CPU idle with a document open — 0.0% for Marked and its WebKit helpers over 10 s (`ps`, `top`).
- [x] No network connections — `lsof -i` shows no sockets for Marked or its WebKit processes; `nettop` lists no Marked/WebKit traffic, with a document containing a remote image and links. All non-file loads are blocked by a content rule list.
- [x] App bundle under ~15 MB — 1.5 MB.

## Notes / open questions

- Phase 2: `.mdown` isn't covered by the system's `net.daringfireball.markdown` declaration, so Marked exports `io.github.muhleake.marked.mdown` (conforms to Markdown) and its document controller also maps the extension.
- Phase 2: XCTest runs tests inside a run-loop callout where NSApplication's end-of-event undo grouping never fires; the typing helper posts real key events and groups them explicitly. Tests run with `-ApplePersistenceIgnoreState YES` so they don't leave restorable state behind.
- Phase 2: if every window restored at launch fails (file deleted), Marked opens an untitled document instead of showing nothing.

- Phase 1: ⌥⌘T is AppKit's usual Show/Hide Toolbar shortcut, but the spec assigns it to Table and gives Show/Hide Toolbar no shortcut. Following the spec: Table = ⌥⌘T, Show/Hide Toolbar unbound. Not a spec contradiction, just noted.
