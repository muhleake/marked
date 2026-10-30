# Marked — rules for Claude Code

Marked is a native, single-purpose macOS Markdown editor: raw text on the left, a live GitHub-flavored preview on the right, and a small formatting toolbar on top. It opens, edits and creates `.md`/`.markdown`/`.mdown` and `.txt` files and nothing else (`.txt` opens editor-only). **Non-goals:** no rich text (RTF/DOCX), no cloud sync, no plugins, no export pipeline beyond Print/Save as PDF and Copy as HTML; no account, telemetry, auto-updater, App Store or notarization; no file browser sidebar, tags, or vault/library concept.

Source of truth: `docs/SPEC.md`. Progress: `docs/PROGRESS.md`. Behavior: `docs/BEHAVIOR.md`. Performance: `docs/REPORT.md`.

## Stack rules

- Swift 5.10+ (Swift 5 language mode), AppKit. No SwiftUI for the editor.
- Document-based: `NSDocumentController` + `MarkdownDocument: NSDocument`.
- Editor: `NSTextView` in `NSScrollView`. Preview: `WKWebView` with a bundled HTML shell + CSS.
- Markdown: `swift-cmark` (gfm branch) via SPM — `cmark-gfm` + `cmark-gfm-extensions`.
- macOS 14 minimum. Ad-hoc code signing (`CODE_SIGN_IDENTITY="-"`, no team). App Sandbox off.
- No other third-party dependencies without asking first.

## Build and test

```sh
xcodegen generate && xcodebuild -scheme Marked -destination 'platform=macOS' build
xcodegen generate && xcodebuild -scheme Marked -destination 'platform=macOS' test
```

Or `make build`, `make test`, `make run`, `make install`. Always build and run tests before saying a task is done.

## Keep it light

- No network calls, no analytics, no background work when idle.
- The preview never loads remote URLs; links open in the default browser.

## Project file

Never edit `Marked.xcodeproj` by hand. Edit `project.yml` and run `xcodegen generate`.
