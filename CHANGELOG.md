# Changelog

All notable changes to Marked.

## Unreleased

### Added

- Preview-to-editor scroll sync, so scrolling either pane moves the other.
- Zoom: ⌘+, ⌘− and ⌘0 now scale both panes.
- Preview Zoom (⌥⌘=, ⌥⌘-, ⌥⌘0) scales the preview alone, with a Scale to Window option and a Settings control.
- Pinch to zoom in the preview.
- App icon, with its vector source in `assets/` and `make icon` to regenerate it.
- [The Unlicense](LICENSE), placing Marked in the public domain.
- A [behavior reference](docs/BEHAVIOR.md) for Marked's menus and file handling.

### Changed

- Editor-only text size moved to ⌃⌘=, ⌃⌘- and ⌃⌘0.
- Editor tinting is much faster in large files. At 50,000 lines a keystroke dropped from 13.3 ms to 0.2 ms, and opening a file from 5.2 s to 0.6 s.

### Removed

- Underline, highlight and text color tools. Existing files that contain those HTML tags still render in the preview.

### Fixed

- Pressing Return in the middle of a line could leave the new line without its tint.

## 1.0 (2026-10-25)

First working version: native Mac document handling, live GitHub-flavored preview, formatting toolbar, list editing, print and PDF export, Copy as HTML, and settings.
