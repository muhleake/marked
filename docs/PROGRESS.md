# Marked — Build Progress

Source of truth: `docs/SPEC.md`. Each phase is ticked only when build + tests + its own verification pass.

- [x] Phase S — Environment check and setup — Xcode 27.1 (27A9275), Swift 6.4, macOS 27.0.1, xcodegen 2.46.0 via brew; headless build + ad-hoc signing + XCTest smoke test passed.
- [x] Phase 0 — Scaffold and CLAUDE.md — project.yml (XcodeGen), swift-cmark gfm linked, Makefile, stub app launches to one 900×600 window; build + 1 test pass.
- [x] Phase 1 — Behavior reference — menus, document lifecycle, plain text, encodings, find, spelling, print and scope documented in docs/BEHAVIOR.md.
- [x] Phase 2 — Document model, window, editor — NSDocument (.md/.markdown/.mdown/.txt), UTF-8/UTF-16/1252 read + UTF-8 write with CRLF kept, split window w/ tabs, SF Mono editor (substitutions off, find bar, spellcheck), menus in code. 32 tests pass: open/edit/save/reopen, revert, duplicate, Open Recent menu, undo, CRLF, 1252.
- [x] Phase 3 — Live preview — cmark-gfm (table/strikethrough/tasklist/autolink/tagfilter + footnotes, sourcepos) off-main, WKWebView shell updated in place via isolated-world JS, CSP blocks page script, content rules block all non-file loads, links open externally, relative images resolve, ⌥⌘P cycles layouts, Treat as Markdown, scroll sync. 5,000-line doc: cmark 4.6 ms median warm (17 ms cold), 0.26 ms main-thread per edit, ~210 ms edit→visible incl. 150 ms debounce. 55 tests pass.
- [ ] Phase 4 — Toolbar and Markdown commands
- [ ] Phase 5 — Editor polish
- [ ] Phase 6 — Finish and install

## Acceptance tests

(Recorded after Phase 6.)

## Notes / open questions

- Phase 2: `.mdown` isn't covered by the system's `net.daringfireball.markdown` declaration, so Marked exports `io.github.muhleake.marked.mdown` (conforms to Markdown) and its document controller also maps the extension.
- Phase 2: XCTest runs tests inside a run-loop callout where NSApplication's end-of-event undo grouping never fires; the typing helper posts real key events and groups them explicitly. Tests run with `-ApplePersistenceIgnoreState YES` so they don't leave restorable state behind.
- Phase 2: if every window restored at launch fails (file deleted), Marked opens an untitled document instead of showing nothing.

- Phase 1: ⌥⌘T is AppKit's usual Show/Hide Toolbar shortcut, but the spec assigns it to Table and gives Show/Hide Toolbar no shortcut. Following the spec: Table = ⌥⌘T, Show/Hide Toolbar unbound. Not a spec contradiction, just noted.
