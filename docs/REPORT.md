# Marked: Project and Performance Report

Measured October 30, 2026, on the Release build of Marked installed in `/Applications`, with nobody using the Mac, unless a section says otherwise.

## Summary

Marked meets all of its lightness targets by a wide margin. A launch takes about 0.4 seconds, the app idled at 0.0% CPU in every sample, it makes no network connections, and the bundle is 2.0 MB.

This run also shows the large-file problem from the first report is fixed. Opening a 50,000-line file went from 5.2 seconds to 0.6 seconds, and each keystroke's tinting went from 13.3 ms to 0.2 ms. Costs now grow in step with file size.

Of the 19 acceptance tests, 16 pass and 3 are only partly verified because they need a person at the keyboard.

| Target | Goal | Result | Status |
| --- | --- | --- | --- |
| Launch to window | Under ~1 s | 412 ms median, 550 ms slowest | Met |
| Idle CPU with a document open | ~0% | 0.0% in all 30 samples | Met |
| Network connections | None | 0 sockets, no traffic | Met |
| App bundle size | Under ~15 MB | 2.0 MB | Met |
| Typing in a 5,000-line file | No visible lag | 0.12 ms per edit | Met |

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

Time from running `open` to the first on-screen window, 21 launches per file, with Marked quit in between.

| Document | Fastest | Median | Slowest |
| --- | --- | --- | --- |
| Small file (under 1 KB) | 387 ms | 412 ms | 550 ms |
| 5,000 lines (83 KB) | 441 ms | 455 ms | 502 ms |

The first report had one 2,081 ms launch, taken while the Mac was in active use. It didn't recur in these 42 launches with the Mac left alone, which fits that explanation.

## Idle CPU

Sampled every 2 seconds for 30 seconds, starting 12 seconds after launch.

| Document | Samples at 0.0% | Highest sample |
| --- | --- | --- |
| Small file | 15 of 15 | 0.0% |
| 5,000 lines | 15 of 15 | 0.0% |

Marked's WebKit helper processes also showed 0.0% at the end of each run.

## Memory

Physical footprint after launch, with the document open and idle.

| Process | Small file | 5,000 lines |
| --- | --- | --- |
| Marked | 53 MB | 56 MB |
| WebKit content | 19 MB | 59 MB |
| WebKit GPU | 11 MB | 12 MB |
| WebKit networking | 5 MB | 5 MB |
| **Total** | **88 MB** | **132 MB** |

Each open window adds its own preview page, so memory will rise with more documents open. That was not measured.

### Memory pass (November 2, 2026)

Medians of three runs of the Release build, measured 15 seconds after opening, the same way as above. The test file is a copy of this project's 124-line README.

| Document | 1.1.1 | Now |
| --- | --- | --- |
| Small Markdown file, split view | 86 MB | 86 MB |
| README as `.md`, split view | 116 MB | 116 MB |
| README as `.txt`, editor only | 103 MB | 67 MB |

Two changes:

- **The preview starts only when it's shown.** `.txt` files and Editor Only windows used to start a hidden WebKit page, GPU and networking process anyway. Now they don't, which saves about 30 MB, and the Marked process is smaller too.
- **Closed windows are freed.** Opening and closing the same file in the test app showed the leak. Each closed Markdown window kept its WebKit page process running and left about 14 MB in Marked. Each closed text window left about 25 MB, held by the window server. After the fix, five open-and-close cycles add about 1 MB in total, and no page processes are left over.

  macOS 27 keeps every closed `NSWindow` object alive, because references from its own title bar controls hold it. A bare AppKit window shows the same thing. The window server then keeps the last frame that window showed, so Marked now empties each window before it leaves the screen.

What stays, and why:

- **About 40 MB is the floor for a native window with a toolbar.** An empty AppKit window measured 29 MB, and 39 MB with a 17-button toolbar. Dropping the toolbar would save about 12 MB.
- **About 33 MB is the floor for the preview.** A blank `WKWebView` costs about 33 MB across the WebKit helper processes. The page process then grows with the length of the rendered document, about 20 MB more for the README, because WebKit keeps its drawn tiles. WebKit has no public setting for this.
- **Spell checking accounts for most of the launch peak.** With it off, the peak fell from about 120 MB to 54 MB, but steady memory fell only about 4 MB. It stays on.
- **No measurable effect:** turning off the content rules, sharing a data store, limiting how far ahead the editor lays out text, or asking `malloc` to release free memory.

## Network

A test document contained a remote image and links.

- `lsof` showed no open sockets for Marked or its three WebKit helpers.
- `nettop` listed no traffic from any of them.

This holds by design. The preview runs under a rule list that blocks every load except `file:`, `about:` and `data:`, and a content security policy stops rendered documents from running scripts.

## App size

| Part | Size |
| --- | --- |
| Executable (arm64 and x86_64) | 1.6 MB |
| App icon | 432 KB |
| Preview HTML and CSS | 12 KB |
| **Installed bundle** | **2.0 MB** |

## Editing and rendering at scale

Test documents repeat a mix of headings, paragraphs, lists, tasks, tables, code blocks and quotes. Times are in milliseconds. Keystroke figures are medians of 21 edits.

| Measurement | 1,000 lines | 5,000 lines | 20,000 lines | 50,000 lines |
| --- | --- | --- | --- | --- |
| File size | 17 KB | 83 KB | 331 KB | 827 KB |
| Open to window | 175 | 157 | 285 | 583 |
| Open to rendered preview | 213 | 207 | 396 | 822 |
| Markdown render (background) | 0.9 | 5.2 | 18.0 | 41.8 |
| Word and line counts (background) | 0.6 | 2.6 | 10.7 | 26.5 |
| Tint one keystroke | 0.04 | 0.05 | 0.10 | 0.21 |
| Full edit on the main thread | 0.12 | 0.12 | 0.19 | 0.30 |
| Tint whole document | 7.0 | 24 | 95 | 227 |
| Add a code fence | 0.7 | 3.0 | 13 | 34 |
| Preview scroll moves editor | 2.1 | 6.3 | 14.7 | 35.4 |

The 1,000-line open times are higher than the 5,000-line times because that was the first window of the run and included starting WebKit.

At 60 Hz, one frame lasts 16.7 ms. Typing stays far inside that at every size tested. A preview update appears about 214 ms after typing stops at 5,000 lines, including the intentional 150 ms pause that waits for typing to settle. Exporting a 1,500-line document to PDF produced 45 pages.

### Before and after the tinting fix

| Measurement at 50,000 lines | Before | After |
| --- | --- | --- |
| Open to window | 5,220 ms | 583 ms |
| Tint one keystroke | 13.3 ms | 0.21 ms |
| Tint whole document | 2,463 ms | 227 ms |
| Add a code fence | 2,274 ms | 34 ms |

Timing each part showed two causes. Every keystroke rescanned the whole document for code fences, and checking whether a line was inside a code block walked the full fence list, once per line. Marked now updates the fence list only around the edit and looks lines up with a binary search.

The first report guessed at a different cause, repeated string conversion. Fixing that alone made little difference, and the timing above replaced that guess.

## Findings

- **Typing and opening:** no longer a concern at any size tested.
- **Preview scrolling in very large files:** moving the editor from the preview takes about 35 ms at 50,000 lines, roughly two frames, so the editor may visibly trail the preview at that size. At 5,000 lines it takes about 6 ms. The cost is exact text layout up to the target line.
- **Everything else:** rendering and word counts run off the main thread, scale linearly, and stay under 50 ms at 50,000 lines.

## What came from MarkEdit

[MarkEdit](https://github.com/MarkEdit-app/MarkEdit) is an MIT-licensed Mac Markdown editor. Its editor runs CodeMirror in a web view, while Marked uses a native text view, so none of its editor code applies and none was copied.

| MarkEdit idea | What Marked did |
| --- | --- |
| Pinch to zoom, 10% zoom steps, menu items that disable at the limits | Adopted, using page zoom so text re-wraps to fit the pane |
| Doing work only on the text that changed or is visible | Applied to code-fence tracking, which produced the speedup above |
| README with icon and screenshots, plain top-level layout | Adopted |

Ideas from its source folders that Marked could add later, not evaluated in depth:

- A Quick Look extension, to preview Markdown files in Finder
- A table of contents for jumping between headings
- Front matter support at the top of files
- Word completion while typing

## Quality

| Item | Value |
| --- | --- |
| App code | 22 Swift files, about 3,200 lines |
| Test code | 12 Swift files, about 1,800 lines |
| Tests | 204, all passing |
| Third-party dependencies | 1 (swift-cmark) |

Tests run inside the real app and cover Markdown commands, rendering, file encodings, documents, the preview, two-way scrolling, zoom, the toolbar, printing, external file changes and state restoration. Typing tests use real key events. A randomized test checks the new fence tracking against a full scan across 400 edits.

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
- **Automated tests don't launch like a person:** the test app is never frontmost, so a freeze that only happened on a real launch with always-visible scroll bars got past them. Launch behavior needs checking with `open`.
- **Scroll sync is approximate:** it matches rendered blocks to source lines, so the panes can sit a line or so apart, especially inside long paragraphs.
- **Zoom is app-wide:** zoom settings apply to every window rather than each document.
- **Keyboard layouts:** ⇧⌘8, ⇧⌘7, ⇧⌘. and ⇧⌘- assume a US layout.
- **No sandbox:** Marked is unsandboxed so previews can load relative images from anywhere. A document can therefore display any local image it references, though it can't run scripts or send anything over the network.
- **Tests touch real app data:** the suite runs as the real app, so test files can appear in Marked's Open Recent list. Settings changed during tests are restored afterward.

## How to reproduce

- `make test` prints the 5,000-line render, tint and preview timings, the PDF page count, and the shortcut count. Look for lines starting `RENDER-`, `HIGHLIGHT-`, `PREVIEW-`, `PDF-` and `SHORTCUTS`.
- The launch, CPU, memory, network and scaling measurements came from temporary scripts that aren't in the repo. The methods are described in each section above.
