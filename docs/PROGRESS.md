# Marked — Build Progress

Source of truth: `docs/SPEC.md`. Each phase is ticked only when build + tests + its own verification pass.

- [x] Phase S — Environment check and setup — Xcode 27.1 (27A9275), Swift 6.4, macOS 27.0.1, xcodegen 2.46.0 via brew; headless build + ad-hoc signing + XCTest smoke test passed.
- [x] Phase 0 — Scaffold and CLAUDE.md — project.yml (XcodeGen), swift-cmark gfm linked, Makefile, stub app launches to one 900×600 window; build + 1 test pass.
- [x] Phase 1 — Behavior reference — menus, document lifecycle, plain text, encodings, find, spelling, print and scope documented in docs/BEHAVIOR.md.
- [ ] Phase 2 — Document model, window, editor
- [ ] Phase 3 — Live preview
- [ ] Phase 4 — Toolbar and Markdown commands
- [ ] Phase 5 — Editor polish
- [ ] Phase 6 — Finish and install

## Acceptance tests

(Recorded after Phase 6.)

## Notes / open questions

- Phase 1: ⌥⌘T is AppKit's usual Show/Hide Toolbar shortcut, but the spec assigns it to Table and gives Show/Hide Toolbar no shortcut. Following the spec: Table = ⌥⌘T, Show/Hide Toolbar unbound. Not a spec contradiction, just noted.
