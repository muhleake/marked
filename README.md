# Marked

Marked is a native macOS Markdown editor: raw text on the left, a live GitHub-flavored preview on the right, and a formatting toolbar on top. It opens, edits and creates `.md`, `.markdown`, `.mdown` and `.txt` files, and nothing else.

![Marked with the editor on the left and the rendered preview on the right](docs/images/screenshot.png)

Marked isn't affiliated with the commercial Marked 2 app. It has no accounts, telemetry, auto-updater, cloud sync or network access.

## Features

- **Native document handling:** one window per document, tabs, autosave, Versions, Revert To, Duplicate, Rename, Move To, Open Recent, Find & Replace, spell check, print, and window restoration on relaunch.
- **Live preview:** tables, task lists, strikethrough, autolinks, footnotes, code blocks and relative images. Follows light and dark mode. Switch between Split, Editor Only and Preview Only with ⌥⌘P.
- **Formatting toolbar:** every button works on the selection, toggles off, and undoes in one step. Shortcuts are listed below.
- **Editor:** color and weight tinting that never hides characters, list continuation, Tab and Shift-Tab indenting, adjustable font size, and a word, character and line count.
- **Plain text:** `.txt` files open editor-only. View ▸ Treat as Markdown turns the preview on for that window without renaming the file.
- **Output:** Print and Export as PDF use the rendered preview. Edit ▸ Copy as HTML copies the rendered selection or the whole document.
- **File handling:** reads UTF-8, UTF-16 and Windows-1252, always writes UTF-8, keeps LF or CRLF line endings, and prompts to reload when another app changes the file.

## Requirements

- macOS 14 or later (the deployment target; so far tested only on macOS 27.0.1 on Apple silicon)
- Xcode (tested with 27.1)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and install

The Xcode project is generated from `project.yml` and isn't checked in. The Makefile runs XcodeGen for you.

```bash
make build
```

```bash
make test
```

```bash
make run
```

```bash
make install
```

`make install` builds a Release copy and puts it in `/Applications`. Builds are ad-hoc signed, so no Apple developer account is needed.

To make Marked the default app for a file type, use Finder: Get Info on a file ▸ Open with: Marked ▸ Change All.

## Keyboard shortcuts

| Action | Shortcut | Action | Shortcut |
| --- | --- | --- | --- |
| Bold | ⌘B | Bulleted list | ⇧⌘8 |
| Italic | ⌘I | Numbered list | ⇧⌘7 |
| Underline | ⌘U | Task list | ⇧⌘T |
| Strikethrough | ⇧⌘X | Quote | ⇧⌘. |
| Highlight | ⇧⌘H | Inline code | ⌥⌘C |
| Heading 1–6 | ⌘1–⌘6 | Code block | ⇧⌘C |
| Link | ⌘K | Table | ⌥⌘T |
| Image | ⇧⌘I | Horizontal rule | ⇧⌘- |
| Cycle layout | ⌥⌘P | Bigger / smaller / default text | ⌘+ / ⌘− / ⌘0 |

Text color is in the toolbar and under Format ▸ Text Color. The ⇧⌘8, ⇧⌘7, ⇧⌘. and ⇧⌘- shortcuts assume a US keyboard layout.

Markdown has no syntax for underline, highlight or text color, so those tools write inline HTML (`<u>`, `<mark>`, `<span style="color: …">`). Marked renders them, but other Markdown apps may strip them or show the tags.

## Project layout

```
Marked/
  App/         App delegate and the main menu (built in code)
  Document/    NSDocument subclass, document controller, file encoding
  Window/      Document window, split view, layouts
  Editor/      Text view, tinting, Markdown commands, list handling, status counts
  Preview/     cmark rendering, WKWebView preview, printing, content blocking
  Toolbar/     NSToolbar setup
  Settings/    Preferences and the Settings window
  Resources/   App icon
MarkedTests/   Unit and in-app integration tests
docs/          Report, spec, build log and behavior reference
project.yml    XcodeGen project definition
Makefile       Build, test, run and install
```

## Documentation

- [Project and performance report](docs/REPORT.md)
- [Original spec](docs/SPEC.md)
- [Build log and acceptance results](docs/PROGRESS.md)
- [Behavior reference](docs/BEHAVIOR.md)

## Dependencies

The only third-party dependency is [swift-cmark](https://github.com/apple/swift-cmark), Apple's fork of cmark-gfm, which is BSD-2-Clause licensed. It's pinned to a specific revision in `project.yml`.

## License

No license has been chosen yet, so all rights are reserved.
