# Changelog

All notable changes to Marked.

## Unreleased

### Added

- View ▸ Show Line Numbers. Each line of the file gets one number, even when it wraps onto several rows.
- View ▸ Show Indentation Guides, a faint line at each indent level.

## 1.1.2 (2026-11-04)

### Changed

- The preview's WebKit processes start only when the preview is first shown, so `.txt` files and Editor Only windows don't run them at all.

### Fixed

- Closed windows no longer keep using memory. Before, each closed Markdown window left its preview's WebKit process running and kept about 14 MB in Marked, and each closed text window kept about 25 MB.

## 1.1.1 (2026-10-30)

### Changed

- Marked is now under the [MIT License](LICENSE). Versions up to and including 1.1 keep the Unlicense.

### Fixed

- The disk image now includes the license notices for Marked and swift-cmark.

## 1.1 (2026-10-30)

### Added

- Preview-to-editor scroll sync, so scrolling either pane moves the other.
- Zoom: ⌘+, ⌘− and ⌘0 now scale both panes.
- Preview Zoom (⌥⌘=, ⌥⌘-, ⌥⌘0) scales the preview alone, with a Scale to Window option and a Settings control.
- Pinch to zoom in the preview.
- App icon, with its vector source in `assets/` and `make icon` to regenerate it.
- [The Unlicense](LICENSE), placing Marked in the public domain.
- A [behavior reference](docs/BEHAVIOR.md) for Marked's menus and file handling.
- A downloadable disk image, so Marked can be installed without Xcode.

### Changed

- Editor-only text size moved to ⌃⌘=, ⌃⌘- and ⌃⌘0.
- Builds go to `build.noindex/`, so build copies don't show up in Spotlight.
- Editor tinting is much faster in large files. At 50,000 lines a keystroke dropped from 13.3 ms to 0.2 ms, and opening a file from 5.2 s to 0.6 s.

### Removed

- Underline, highlight and text color tools. Existing files that contain those HTML tags still render in the preview.

### Fixed

- Pressing Return in the middle of a line could leave the new line without its tint.
- With scroll bars set to Always, opening a file just taller than the window froze the app.

## 1.0 (2026-10-25)

First working version: native Mac document handling, live GitHub-flavored preview, formatting toolbar, list editing, print and PDF export, Copy as HTML, and settings.
