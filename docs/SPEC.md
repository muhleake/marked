# Marked — Spec & Claude Code Prompts

Oct 25, 2026

**To build:** do the "One-time steps only you can do" list (in Build phases), drop this file into an empty `Marked/` folder, open Claude Code there, and say: *Read every file in this folder and follow the "For Claude Code — start here" section.* That's it.

## For Claude Code — start here

You are building Marked end to end from this file. Work autonomously; only stop for the cases listed under "When to stop".

1. Read this entire file before doing anything. It is the source of truth.
2. If this file isn't already at `docs/SPEC.md`, move it there (create `docs/`). Every phase refers to that path.
3. Look for `docs/PROGRESS.md`. If it exists, resume from the first unfinished phase. If not, create it with a checklist of Phases S, 0, 1, 2, 3, 4, 5, 6.
4. Run the phases in "Build phases" in order. Treat each phase's code block as your task for that phase. Plan it, implement it, then build and run tests.
5. A phase is done only when the build succeeds, tests pass, and its own verification steps pass. Then tick it in `PROGRESS.md` with a one-line note, and make a git commit named `Phase N: <title>`.
6. After Phase 6, work through "Acceptance tests", record pass/fail for each in `PROGRESS.md`, fix failures, and give a final report.

**When to stop and ask** (otherwise keep going):

- A command needs `sudo`, an Apple ID, or a GUI-only action. Give the exact command or click path, then wait.
- A one-time setup step is missing (Xcode not installed, license not accepted, Homebrew missing).
- You would add a third-party dependency not named in this spec.
- A phase still fails after three honest fix attempts.

If a session ends mid-phase, the next session reads this file and `PROGRESS.md` and continues; don't redo finished phases.

## Overview

Marked is a native, single-purpose macOS Markdown editor: raw text on the left, live rendered preview on the right, a small formatting toolbar on top. It opens, edits and creates `.md` and `.txt` files and nothing else.

**Goals**

- Feel like a native Mac document editor: one window per document, standard File/Edit/Format menus, autosave, Revert To, Open Recent, tabs, Find & Replace, spell check, print.
- Split view: editor left, rendered GitHub-flavored Markdown right, updating as you type.
- Toolbar with one-click Markdown shortcuts (bold, italic, headings, lists, links, code, quote, table, rule).
- Plain `.txt` files open in the same app, editor only (preview hidden by default).
- Launches in under \~1 second, idles near 0% CPU, app bundle under \~15 MB.

**Non-goals**

- No rich text (RTF/DOCX), no cloud sync, no plugins, no export pipeline beyond Print/Save as PDF and Copy HTML.
- No account, telemetry, auto-updater, App Store or notarization.
- No file browser sidebar, no tags, no vault/library concept — it's a document editor, not a notes app.

Name note: there's an existing commercial Mac app called Marked 2 (a Markdown previewer), which is unrelated. Keep the bundle ID unique (e.g. `io.github.muhleake.marked`) so macOS doesn't confuse the two if both are ever installed.

## Tech stack and architecture

Build it as a Swift/AppKit **document-based app** (`NSDocument`). That one choice gives you most of the standard Mac document behavior for free: Open Recent, autosave, Versions/Revert To, window tabs, "Edited" title, Duplicate/Rename/Move To.

| Layer | Choice | Why |
| --- | --- | --- |
| Language / UI | Swift 5.10+, AppKit (not SwiftUI for the editor) | `NSTextView` provides undo, spell check, find bar, services and smart quotes toggles built in |
| App model | `NSDocumentController` + `MarkdownDocument: NSDocument` | Standard Mac file handling for free |
| Window | `NSSplitViewController`: editor pane + preview pane, divider draggable, preview collapsible | Left/right split |
| Editor | `NSTextView` in `NSScrollView`, monospace font, lightweight regex syntax tinting via `NSTextStorageDelegate` | Readable raw Markdown without a heavy editor framework |
| Parser | `swift-cmark` (Apple's cmark-gfm fork) via Swift Package Manager, GFM extensions on: tables, strikethrough, task lists, autolinks | Fast C parser, spec-compliant, outputs HTML directly |
| Preview | `WKWebView` loading a local HTML shell + one bundled CSS file; body replaced via JS on edit | Accurate rendering, light/dark CSS, no network |
| Settings | `UserDefaults` + small Settings window | Font size, preview on/off default, theme |
| Minimum macOS | 14 (Sonoma) | Modern APIs, no back-compat burden |

**Data flow:** keystroke → `NSTextStorage` changes → debounce \~150 ms → cmark renders HTML on a background queue → main thread calls `updateBody(html)` in the WKWebView (no full reload, so scroll position holds) → optional scroll sync by matching the editor's top visible line to `data-sourcepos` attributes cmark emits.

**Deliberately avoided:** Electron/Tauri (too heavy), SwiftUI text views (weak undo/find/spellcheck control), JavaScript Markdown libraries in the web view (cmark is faster and keeps JS out), any third-party editor framework.

## Functional spec

### Files and documents

- Types: `.md`, `.markdown`, `.mdown`, `.txt` (UTType `net.daringfireball.markdown` and `public.plain-text`). Register Marked as an editor for both so Finder "Open With" works.
- New (⌘N) creates an untitled Markdown doc; Save defaults to `.md`. Save As lets you pick `.md` or `.txt`.
- Encoding: read UTF-8 first, fall back to UTF-16 / Windows-1252 detection; always write UTF-8, preserve the file's original line endings (LF vs CRLF).
- Autosave in place, Versions browsing, Revert To, Duplicate, Rename, Move To — all via `NSDocument`.
- Detect external changes (file edited elsewhere) and prompt to reload.
- Restore open windows on relaunch (state restoration).

### Editor (left pane)

- Monospace font (default SF Mono 13 pt), adjustable with Format ▸ Bigger/Smaller (⌃⌘=, ⌃⌘-), line wrapping on, comfortable line height.
- Syntax tinting only — color and weight, never hide characters: headings, emphasis, inline code, fenced code blocks, links, list markers, blockquotes.
- Smart quotes/dashes/substitutions **off** by default (they corrupt Markdown); spell check on.
- List continuation: Return on a ` -  `, ` *  `, ` 1.  ` or ` - [ ]  ` line continues the list (numbered lists increment); Return on an empty item ends the list.
- Tab / Shift-Tab indent and outdent selected lines.
- Word, character and line count in a slim status bar at the bottom.

### Preview (right pane)

- GitHub-flavored rendering: headings, emphasis, lists, task lists (checkboxes display only), tables, code blocks, blockquotes, images (relative paths resolved against the file's folder), links, horizontal rules.
- Links open in the default browser; never navigate inside the preview.
- Follows system light/dark mode. One CSS file, GitHub-like look.
- Toggle with ⌥⌘P; three layouts: Split / Editor only / Preview only.
- Two-way scroll sync between editor and preview (approximate is fine).
- Zoom: View ▸ Zoom In/Out/Actual Size (⌘+, ⌘−, ⌘0) scales both panes; View ▸ Preview Zoom (⌥⌘=, ⌥⌘-, ⌥⌘0) scales only the preview, and its Scale to Window option sizes the preview to its pane. Pinch to zoom works in the preview.

### Toolbar

Standard `NSToolbar`, icons from SF Symbols, customizable via right-click (free with NSToolbar). Each button wraps the selection or inserts at the cursor, and toggles off if already applied.

| Button | Inserts | Shortcut |
| --- | --- | --- |
| Bold | `**text**` | ⌘B |
| Italic | `*text*` | ⌘I |
| Strikethrough | `~~text~~` | ⇧⌘X |
| Heading menu (H1–H6) | ` #  ` … ` ######  ` at line start | ⌘1 – ⌘6 |
| Bulleted list | ` -  ` per line | ⇧⌘8 |
| Numbered list | ` 1.  ` per line | ⇧⌘7 |
| Task list | ` - [ ]  ` per line | ⇧⌘T |
| Quote | ` >  ` per line | ⇧⌘. |
| Inline code | `` `text` `` | ⌥⌘C (⌘E stays "Use Selection for Find") |
| Code block | ```` ``` ```` fences around selection | ⇧⌘C |
| Link | `[text](url)`, cursor lands in url | ⌘K |
| Image | `![alt](path)` | ⇧⌘I |
| Table | 3×3 GFM table skeleton | ⌥⌘T |
| Horizontal rule | `---` on its own line | ⇧⌘- |
| Preview toggle | Split / Editor / Preview segmented control | ⌥⌘P |

### Plain-text (.txt) behavior

- Opens in the same window style with the preview pane collapsed and Markdown tinting off.
- Toolbar Markdown buttons disabled for `.txt`; a View menu item "Treat as Markdown" turns preview and tinting on for that window without renaming the file.

### Menus

Use the standard Mac menu structure: **File** (New, Open, Open Recent, Close, Save, Duplicate, Rename, Move To, Revert To, Export as PDF, Page Setup, Print), **Edit** (Undo/Redo, Cut/Copy/Paste, Paste and Match Style, Select All, Find submenu, Spelling and Grammar, Substitutions, Transformations, Speech), **Format** (Markdown actions above, Font bigger/smaller), **View** (Layout, Show/Hide Toolbar, Customize Toolbar, Enter Full Screen, Treat as Markdown), **Window**, **Help**. Edit → Copy as HTML copies the rendered HTML of the selection or whole doc.

## Document feature scope

`docs/BEHAVIOR.md` records how each of these behaves in the app.

| Feature | Marked | Notes |
| --- | --- | --- |
| One window per document, window tabs | Included | NSDocument default |
| Autosave, Versions, Revert To | Included | NSDocument default |
| Duplicate / Rename / Move To | Included | NSDocument default |
| Open Recent, state restoration | Included |  |
| Find, Find & Replace, Find Next/Previous, Use Selection for Find | Included | `NSTextView.usesFindBar = true` |
| Spelling & grammar, substitutions, transformations, speech | Included | Substitutions default off |
| Print, Export as PDF | Included | Prints the rendered preview, not raw text |
| Encoding detection on open | Included | UTF-8 write |
| Plain-text mode | Included | `.txt` = preview hidden; "Treat as Markdown" toggle |
| Rich text: fonts panel, colors, rulers, styles, lists, tables, images in RTF | Out of scope | Markdown handles formatting |
| RTF / RTFD / DOCX / ODT / HTML read-write | Out of scope | `.md` + `.txt` only |
| Wrap to Page / Wrap to Window | Out of scope | Always wrap to window |
| iCloud open panel on launch | Out of scope | Open panel only on ⌘O |

## Project layout, build and install

Use an Xcode project generated from a `project.yml` with **XcodeGen**, so Claude Code edits plain text files instead of `.pbxproj`, and builds run headless with `xcodebuild`.

```
Marked/
  project.yml                 # XcodeGen spec
  CLAUDE.md                   # rules for Claude Code (Phase 0)
  docs/
    SPEC.md                   # this doc, exported
    BEHAVIOR.md               # how the app behaves
  Marked/
    App/AppDelegate.swift
    App/MainMenu.swift        # menus built in code, no nib
    Document/MarkdownDocument.swift
    Document/FileEncoding.swift
    Window/DocumentWindowController.swift
    Window/SplitViewController.swift
    Editor/EditorViewController.swift
    Editor/MarkdownHighlighter.swift
    Editor/MarkdownCommands.swift   # toolbar/menu text transforms
    Editor/ListContinuation.swift
    Preview/PreviewViewController.swift
    Preview/MarkdownRenderer.swift  # swift-cmark wrapper
    Preview/Resources/preview.html
    Preview/Resources/preview.css
    Toolbar/ToolbarController.swift
    Settings/SettingsWindow.swift
    Info.plist
    Marked.entitlements
  MarkedTests/
    MarkdownCommandsTests.swift
    RendererTests.swift
    EncodingTests.swift
```

**Signing and install:**

- Ad-hoc signing only (`CODE_SIGN_IDENTITY="-"`, no development team), so no Apple ID login is ever needed in Xcode and Claude Code builds fully from the terminal. No notarization needed for an app you build yourself.
- App Sandbox **off** (see decision below). No entitlements file needed beyond an empty one.
- Install: `xcodebuild -scheme Marked -configuration Release -derivedDataPath build.noindex` then copy `build.noindex/Build/Products/Release/Marked.app` to `/Applications`. A `make install` target wraps this.
- Set as default: Finder → Get Info on any `.md` → Open with: Marked → Change All.

**Decision — sandbox off:** a sandboxed app can only load relative images in the preview from folders you've explicitly granted. The sandbox adds friction here with no real benefit, so Marked ships unsandboxed. To keep it on instead, change this line before starting and Claude Code will add folder bookmarks.

## Build phases

Claude Code runs these phases in order on its own, following "For Claude Code — start here". Each code block is that phase's task. The short list below is the only part that needs you, because it involves your Apple ID or admin password.

### One-time steps only you can do

1. Install **Xcode** from the Mac App Store (needs your Apple ID, \~10+ GB). Open it once and let it install components.
2. In Terminal, run these two lines (they need your password, which Claude Code can't type):

   ```
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch
   ```
3. If you don't have Homebrew, install it from brew.sh (also asks for your password).
4. Export this doc as Markdown and drop it into an empty folder named `Marked/`. Any filename works; Claude Code moves it to `docs/SPEC.md`.
5. Open Claude Code in `Marked/` and say: *Read every file in this folder and follow the "For Claude Code — start here" section.* Approve permission prompts as they come, or allow them for the session.

### Phase S — Environment check and setup

```
We're about to build a macOS app (see docs/SPEC.md). Set up and verify the dev environment.
Don't use sudo; if something needs it, stop and give me the exact command to run.

1. Verify the toolchain and report versions: `xcode-select -p` must point inside Xcode.app
   (not CommandLineTools), `xcodebuild -version`, `swift --version`, macOS version.
   If any check fails, tell me exactly which one-time step to redo.
2. Install missing tools with Homebrew: xcodegen (required). Confirm `xcodegen --version`.
3. `git init` if this isn't a repo yet; add a Swift/Xcode .gitignore (build.noindex/, DerivedData,
   *.xcodeproj/xcuserdata, .DS_Store). Make an initial commit with docs/SPEC.md.
4. Smoke test: generate a throwaway XcodeGen macOS app in /tmp, build it with
   `xcodebuild ... CODE_SIGN_IDENTITY="-" build`, run its test target, then delete it.
   This proves headless building, ad-hoc signing and XCTest all work before real work starts.
Report a short pass/fail checklist.
```

### Phase 0 — Scaffold and CLAUDE.md

```
Read docs/SPEC.md fully. We're building Marked, a macOS Markdown/txt editor.

1. Create CLAUDE.md at the repo root containing:
   - One-paragraph summary of the app and the non-goals from the spec.
   - Stack rules: Swift 5.10+, AppKit, NSDocument-based, NSTextView editor, WKWebView preview,
     swift-cmark (gfm) via SPM, macOS 14 minimum, ad-hoc code signing (no team). No SwiftUI for the editor, no other third-party deps
     without asking me.
   - Build: `xcodegen generate && xcodebuild -scheme Marked -destination 'platform=macOS' build`.
     Test: same with `test`. Always build and run tests before saying a task is done.
   - Keep the app light: no network calls, no analytics, no background work when idle.
   - Never edit Marked.xcodeproj by hand; edit project.yml and regenerate.
2. Create project.yml (XcodeGen) for a macOS app target "Marked" (bundle id io.github.muhleake.marked)
   and a unit test target "MarkedTests", with the folder layout from the spec's "Project layout" section.
3. Add the swift-cmark package (https://github.com/apple/swift-cmark, gfm branch) and link
   cmark-gfm and cmark-gfm-extensions.
4. Add a Makefile with targets: gen, build, test, run, install (Release build copied to /Applications).
5. Stub AppDelegate so the app launches to an empty window. Build it and confirm it runs.
Don't implement features yet.
```

### Phase 1 — Behavior reference

```
Write docs/BEHAVIOR.md, the reference for how Marked behaves as a Mac document app:
- The complete menu tree with key equivalents.
- Document lifecycle: new, open, save, autosave, versions, revert, duplicate, rename, move,
  external-change handling, tabs, state restoration.
- Plain-text mode behavior and encoding handling.
- Find/replace, spelling, substitutions, print/PDF.
Use the "Document feature scope" table in docs/SPEC.md for what's included.
```

### Phase 2 — Document model, window, editor

```
Implement Phase 2 of docs/SPEC.md, using docs/BEHAVIOR.md for expected behavior.
- MarkdownDocument: NSDocument for .md/.markdown/.mdown/.txt. Declare UTIs and
  CFBundleDocumentTypes in Info.plist (via project.yml). autosavesInPlace = true.
- FileEncoding: read UTF-8, fall back to UTF-16 / Windows-1252; write UTF-8;
  preserve LF vs CRLF. Unit tests for each case.
- DocumentWindowController + SplitViewController with the editor on the left and an empty
  placeholder on the right (preview comes next phase). Window tabs enabled.
- EditorViewController: NSTextView, SF Mono 13pt, wraps to window, spell check on, smart quotes/
  dashes/text replacement off, find bar on, undo works across the document.
- .txt files open with the right pane collapsed.
- Menus built in code (MainMenu.swift) matching docs/BEHAVIOR.md.
  Format menu can be empty for now.
Verify: open, edit, save, reopen, Revert To, Duplicate, and Open Recent all work.
Build + tests must pass.
```

### Phase 3 — Live preview

```
Implement the preview pane from docs/SPEC.md.
- MarkdownRenderer wraps swift-cmark with GFM extensions: table, strikethrough, tasklist, autolink.
  Enable sourcepos. Render off the main thread. Unit tests for each GFM element.
- PreviewViewController: WKWebView loads bundled preview.html + preview.css once, then updates
  via a JS function updateBody(html) so scroll position is kept. Debounce edits ~150 ms.
- preview.css: clean GitHub-like styling, light and dark via prefers-color-scheme.
- Relative image paths resolve against the document's folder (baseURL / file access).
- Link clicks open in the default browser via WKNavigationDelegate; never navigate in place.
- No network: block any non-file, non-about URL loads.
- View menu layout: Split / Editor only / Preview only (⌥⌘P cycles). Remember per-window.
- .txt: preview hidden; View → "Treat as Markdown" turns it on for that window.
- Approximate scroll sync: editor's top visible line → nearest data-sourcepos element.
Keep typing latency imperceptible on a 5,000-line file; measure and tell me the render time.
```

### Phase 4 — Toolbar and Markdown commands

```
Implement the toolbar and Format menu from docs/SPEC.md (the Toolbar table is the source of truth
for buttons and shortcuts).
- MarkdownCommands: pure functions (text, selectedRange) -> (newText, newSelection) for each action,
  so they're unit-testable without UI. Inline styles wrap/unwrap the selection (toggle off if already
  applied); with no selection insert the markers and place the cursor between them. Line-prefix
  styles (headings, lists, quote, task) apply to every selected line and toggle. Headings replace an
  existing heading level instead of stacking. Link puts the cursor inside the (url).
- Apply edits through NSTextView's shouldChangeText/replaceCharacters so each is one undo step.
- NSToolbar with SF Symbols, heading dropdown, layout segmented control, user-customizable.
  Disable Markdown buttons for plain .txt windows unless "Treat as Markdown" is on.
- Same actions in the Format menu with the spec's key equivalents. Check for conflicts with
  standard shortcuts and tell me if any remain.
Write thorough MarkdownCommandsTests (toggle on/off, multi-line, empty selection, undo).
```

### Phase 5 — Editor polish

```
Editor quality-of-life from docs/SPEC.md:
- MarkdownHighlighter: NSTextStorageDelegate that tints headings, emphasis, inline code, fenced
  blocks, links, list markers, blockquotes. Color/weight only; never hide characters. Only re-highlight
  the edited paragraph range (plus fenced-block boundaries) so large files stay fast.
  Uses system colors so dark mode works. Off for .txt unless "Treat as Markdown".
- ListContinuation: Return continues -, *, 1., - [ ] lists (numbers increment); Return on an empty
  item removes the marker. Tab/Shift-Tab indent/outdent selected lines.
- Status bar under the editor: words · characters · lines, updating on edit.
- ⌘+ / ⌘− font size, persisted in UserDefaults.
Tests for list continuation edge cases.
```

### Phase 6 — Finish and install

```
Final pass on docs/SPEC.md:
- Print and Export as PDF print the rendered preview (WKWebView printOperation), with Page Setup.
- Edit → Copy as HTML (selection's rendered HTML, or the whole document if nothing is selected).
- Small Settings window: editor font size, default layout for .md, preview theme follow-system.
- External file change: prompt to reload (NSFilePresenter is fine).
- State restoration of open windows and their layout.
- Run through every row in the spec's "Acceptance tests" section and report pass/fail for each.
- Check idle CPU (~0%), launch time, and app bundle size; report the numbers.
- `make install`, then tell me the exact steps to set Marked as the default app for .md files.
```

**If a session ends or runs long:** open Claude Code in the same folder and repeat the kickoff line. It reads `docs/PROGRESS.md` and picks up at the first unfinished phase.

## Acceptance tests

Marked is done when every box below is ticked on a real build in `/Applications`.

**Files**

- [ ] Double-clicking a `.md` and a `.txt` in Finder opens Marked (after setting default).
- [ ] ⌘N → type → ⌘S saves `Untitled.md` as UTF-8.
- [ ] A CRLF file saves back as CRLF; a Windows-1252 file opens without garbled characters.
- [ ] Quit with unsaved edits, relaunch: windows and edits are restored.
- [ ] File → Revert To → Browse All Versions works.
- [ ] Editing the file in another app triggers a reload prompt.

**Editing**

- [ ] Every toolbar button and shortcut applies, toggles off, and undoes in one ⌘Z.
- [ ] Return continues bullets, numbers (incrementing) and tasks; Return on an empty item ends the list.
- [ ] ⌘F find bar, Find & Replace, and spell-check underlines work.
- [ ] Typing "quotes" doesn't produce curly quotes.

**Preview**

- [ ] Headings, tables, task lists, strikethrough, code blocks, relative images and autolinks render.
- [ ] Clicking a link opens the browser; the preview never navigates.
- [ ] Preview follows system dark mode.
- [ ] ⌥⌘P cycles Split / Editor / Preview; `.txt` starts editor-only; Treat as Markdown shows preview.
- [ ] Typing in a 5,000-line file has no visible lag; preview keeps its scroll position.

**Lightness**

- [ ] Cold launch to window in under \~1 second.
- [ ] \~0% CPU in Activity Monitor when idle with a document open.
- [ ] No network connections (check with Little Snitch or `nettop`).
- [ ] App bundle under \~15 MB.
