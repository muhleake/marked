# Marked: Project and Performance Report

Measured October 30, 2026, on the Release build of Marked 1.0 installed in `/Applications`, unless a section says otherwise.

## Summary

Marked meets all four of its lightness targets by a wide margin and handles its design size, a 5,000-line document, comfortably. A typical launch takes about 0.4 seconds, the app idles at essentially 0% CPU, it makes no network connections, and the bundle is 1.8 MB.

Performance holds up to about 20,000 lines. Above that, one real weakness appears: editor tinting slows down faster than documents grow. A 50,000-line file takes about 5 seconds to open, and each keystroke costs about 14 ms. No target covers files that size, but it's the first thing to fix if very large files matter.

Of the 19 acceptance tests, 16 pass and 3 are only partly verified because they need a person at the keyboard.

| Target | Goal | Result | Status |
| --- | --- | --- | --- |
| Launch to window | Under ~1 s | 421 ms median | Met, with one slow outlier |
| Idle CPU with a document open | ~0% | 0.0% in most samples | Met |
| Network connections | None | 0 sockets, no traffic | Met |
| App bundle size | Under ~15 MB | 1.8 MB | Met |
| Typing in a 5,000-line file | No visible lag | 1.7 ms per edit | Met |

## Test setup

| Item | Value |
| --- | --- |
| Computer | Apple M4, 16 GB memory |
| System | macOS 27.0.1 |
| Toolchain | Xcode 27.1, Swift 6.4 toolchain in Swift 5 language mode |
| Launch, CPU, memory, network | Release build |
| Editor and rendering timings | Debug build, run in the test suite |

The Debug numbers should run slower than Release, so treat them as conservative. Release was not timed separately.

## Launch

Time from running `open` to the first on-screen window, 11 launches per file, with Marked quit in between.

| Document | Fastest | Median | Slowest |
| --- | --- | --- | --- |
| Small file (under 1 KB) | 365 ms | 421 ms | 2,081 ms |
| 5,000 lines (83 KB) | 448 ms | 473 ms | 502 ms |

Two slow launches need explaining:

- **The 2,081 ms outlier:** one of the 22 launches. The cause is unknown, and it did not recur.
- **The first launch after installing on October 25:** this took over 10 seconds. The October 30 reinstall did not repeat it, with the first launch at 397 ms, so the earlier explanation of a one-time macOS check is unconfirmed.

## Idle CPU

Sampled every 2 seconds for 30 seconds, starting 12 seconds after launch.

| Document | Samples at 0.0% | Highest sample |
| --- | --- | --- |
| Small file | 14 of 15 | 0.3% |
| 5,000 lines | 14 of 15 | 4.6% |

Marked's WebKit helper processes also showed 0.0% at the end of each run.

## Memory

Physical footprint after launch, with the document open and idle.

| Process | Small file | 5,000 lines |
| --- | --- | --- |
| Marked | 71 MB | 71 MB |
| WebKit content | 20 MB | 59 MB |
| WebKit GPU | 11 MB | 12 MB |
| WebKit networking | 5 MB | 5 MB |
| **Total** | **107 MB** | **147 MB** |

Each open window adds its own preview page, so memory will rise with more documents open. That was not measured.

## Network

A test document contained a remote image and links.

- `lsof` showed no open sockets for Marked or its three WebKit helpers.
- `nettop` listed no traffic from any of them.

This holds by design. The preview runs under a rule list that blocks every load except `file:`, `about:` and `data:`, and a content security policy stops rendered documents from running scripts.

## App size

| Part | Size |
| --- | --- |
| Executable (arm64 and x86_64) | 1.5 MB |
| App icon | 284 KB |
| Preview HTML and CSS | 12 KB |
| **Installed bundle** | **1.8 MB** |

## Editing and rendering at scale

Test documents repeat a mix of headings, paragraphs, lists, tasks, tables, code blocks and quotes. Times are in milliseconds. Keystroke figures are medians of 21 edits.

| Measurement | 1,000 lines | 5,000 lines | 20,000 lines | 50,000 lines |
| --- | --- | --- | --- | --- |
| File size | 17 KB | 83 KB | 331 KB | 827 KB |
| Open to window | 154 | 214 | 1,028 | 5,220 |
| Open to rendered preview | 283 | 266 | 1,146 | 5,468 |
| Markdown render (background) | 0.9 | 4.8 | 16.8 | 41.2 |
| Word and line counts (background) | 0.6 | 2.7 | 10.4 | 26.3 |
| Tint one keystroke | 0.33 | 1.55 | 5.63 | 13.33 |
| Full edit on the main thread | 0.47 | 1.74 | 6.07 | 13.80 |
| Tint whole document | 8.8 | 51 | 451 | 2,463 |
| Add a code fence | 1.9 | 27 | 364 | 2,274 |

The 1,000-line open-to-preview time is higher than the 5,000-line time because it was the first window of the run and included starting WebKit.

At 60 Hz, one frame lasts 16.7 ms. A full edit stays within that even at 50,000 lines, although at that size it uses most of the frame before the window has drawn anything. At 5,000 lines a keystroke uses about a tenth of the frame.

A preview update appears about 217 ms after typing stops at 5,000 lines, including the intentional 150 ms pause that waits for typing to settle. Exporting a 1,500-line document to PDF produced 45 pages.

## Findings

### Tinting is the bottleneck in large files

Two costs grow with document size:

- **Full tinting scales worse than the document.** Ten times the lines (5,000 to 50,000) takes about 48 times as long. Opening a file and editing a code fence both pay this cost, on the main thread. Typing three backticks in a 50,000-line file freezes the window for over 2 seconds.
- **Keystroke tinting isn't constant.** It re-tints only the edited paragraph, yet the cost still grows with the size of the document.

The likely causes, from reading `MarkdownHighlighter.swift` but not confirmed by profiling, are converting the full text storage string for each regex call and rescanning the whole document for code fences on every edit.

This doesn't affect files around the 5,000-line design size, where the worst case is a 51 ms tint. Marked is usable up to about 20,000 lines, and fence edits become a noticeable pause of about 0.4 seconds at that size.

### Everything else holds up

Markdown rendering and word counts run off the main thread and scale linearly. Even at 50,000 lines they take under 50 ms, so they aren't a concern.

## Quality

| Item | Value |
| --- | --- |
| App code | 23 Swift files, about 3,100 lines |
| Test code | 12 Swift files, about 1,700 lines |
| Tests | 202, all passing |
| Third-party dependencies | 1 (swift-cmark) |

Tests run inside the real app and cover Markdown commands, rendering, file encodings, documents, the preview, the toolbar, printing, external file changes and state restoration. Typing tests use real key events.

### Acceptance tests

| Area | Passed | Partly verified |
| --- | --- | --- |
| Files | 3 | 3 |
| Editing | 4 | 0 |
| Preview | 5 | 0 |
| Lightness | 4 | 0 |
| **Total** | **16** | **3** |

The three partly verified tests need someone at the keyboard, because automated control of the app's interface wasn't available:

1. **Double-clicking files:** `.md` opens Marked, but `.txt` opens it only after you change the default app in Finder.
2. **Quit and relaunch with unsaved edits:** the underlying pieces are tested, but the full sequence with real typing wasn't run.
3. **Browse All Versions:** Revert is tested, but the Versions screen itself wasn't driven.

Details are in [PROGRESS.md](PROGRESS.md).

## Known limitations

- **Tested on one setup:** the app targets macOS 14 but has only been run on macOS 27.0.1 on Apple silicon. The Intel half of the executable has never been run.
- **Inline HTML tools:** underline, highlight and text color write HTML tags, which other Markdown apps may strip or display as text.
- **Keyboard layouts:** ⇧⌘8, ⇧⌘7, ⇧⌘. and ⇧⌘- assume a US layout.
- **No sandbox:** Marked is unsandboxed so previews can load relative images from anywhere. A document can therefore display any local image it references, though it can't run scripts or send anything over the network.
- **Tests touch real app data:** the suite runs as the real app, so test files can appear in Marked's Open Recent list. Settings changed during tests are restored afterward.

## How to reproduce

- `make test` prints the 5,000-line render, tint and preview timings, the PDF page count, and the shortcut count. Look for lines starting `RENDER-`, `HIGHLIGHT-`, `PREVIEW-`, `PDF-` and `SHORTCUTS`.
- The launch, CPU, memory, network and scaling measurements came from temporary scripts that aren't in the repo. The methods are described in each section above.
