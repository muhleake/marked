# Marked Behavior Reference

How Marked behaves as a Mac document app. [SPEC.md](SPEC.md) holds the requirements; this is the day-to-day reference for its menus and file handling.

## Menus

Menus are built in code in `Marked/App/MainMenu.swift`. macOS adds some items at runtime, listed after the tree.

```
Marked
  About Marked
  Settings…                  ⌘,
  Services
  Hide Marked                ⌘H
  Hide Others                ⌥⌘H
  Show All
  Quit Marked                ⌘Q

File
  New                        ⌘N
  Open…                      ⌘O
  Open Recent
  Close                      ⌘W
  Save                       ⌘S
  Save As…                   ⇧⌘S
  Revert to Saved
  Export as PDF…
  Page Setup…                ⇧⌘P
  Print…                     ⌘P

Edit
  Undo                       ⌘Z
  Redo                       ⇧⌘Z
  Cut                        ⌘X
  Copy                       ⌘C
  Paste                      ⌘V
  Copy as HTML
  Paste and Match Style      ⌥⇧⌘V
  Delete
  Select All                 ⌘A
  Find
    Find…                    ⌘F
    Find and Replace…        ⌥⌘F
    Find Next                ⌘G
    Find Previous            ⇧⌘G
    Use Selection for Find   ⌘E
    Jump to Selection        ⌘J
  Spelling and Grammar
    Show Spelling and Grammar  ⌘:
    Check Document Now       ⌘;
    Check Spelling While Typing
    Check Grammar With Spelling
    Correct Spelling Automatically
  Substitutions
    Show Substitutions
    Smart Copy/Paste, Smart Quotes, Smart Dashes,
    Smart Links, Data Detectors, Text Replacement
  Transformations
    Make Upper Case, Make Lower Case, Capitalize
  Speech
    Start Speaking, Stop Speaking

Format
  Bold                       ⌘B
  Italic                     ⌘I
  Strikethrough              ⇧⌘X
  Heading
    Heading 1–6              ⌘1–⌘6
  Bulleted List              ⇧⌘8
  Numbered List              ⇧⌘7
  Task List                  ⇧⌘T
  Quote                      ⇧⌘.
  Inline Code                ⌥⌘C
  Code Block                 ⇧⌘C
  Link                       ⌘K
  Image                      ⇧⌘I
  Table                      ⌥⌘T
  Horizontal Rule            ⇧⌘-
  Bigger                     ⌃⌘=
  Smaller                    ⌃⌘-
  Default Size               ⌃⌘0

View
  Split, Editor Only, Preview Only
  Cycle Layout               ⌥⌘P
  Treat as Markdown
  Show Line Numbers
  Show Indentation Guides
  Zoom In                    ⌘+
  Zoom Out                   ⌘−
  Actual Size                ⌘0
  Preview Zoom
    Zoom In                  ⌥⌘=
    Zoom Out                 ⌥⌘-
    Actual Size              ⌥⌘0
    Scale to Window
  Show Toolbar
  Customize Toolbar…
  Enter Full Screen          ⌃⌘F

Window
  Minimize                   ⌘M
  Zoom
  Bring All to Front

Help
```

**Added by macOS at runtime:**

- **File:** Save As becomes Duplicate (hold ⌥ for Save As), Rename and Move To appear, and Revert to Saved becomes the Revert To submenu.
- **Window:** tab commands such as Show Tab Bar and Merge All Windows, plus the list of open windows.
- **Edit:** AutoFill, Start Dictation, and Emoji & Symbols.

## Documents

| Behavior | How Marked handles it |
| --- | --- |
| New | ⌘N opens an untitled Markdown document. A plain launch opens one too. |
| Open | `.md`, `.markdown`, `.mdown` and `.txt` |
| Save | Saves as `.md` by default. Save As offers `.md` or `.txt`. |
| Autosave | Saves in place, with the title showing Edited until then. |
| Versions | Revert To restores the last saved version or any older one. |
| Duplicate, Rename, Move To | Standard document commands |
| External changes | Prompts to reload, or to keep the current version, when another app changes the file. Identical contents are ignored. |
| Tabs | Standard window tabs |
| Restoration | Reopens windows on relaunch, with each window's layout and Treat as Markdown state. If no window can be restored, Marked opens an untitled document. |

## Encodings and line endings

- Reads UTF-8 first, then UTF-16 with or without a byte-order mark, then Windows-1252.
- Always writes UTF-8 without a byte-order mark.
- Keeps a file's LF or CRLF line endings. Text uses LF in memory.

## Plain text

- `.txt` files open editor-only, with tinting and Markdown tools off.
- View ▸ Treat as Markdown turns the preview, tinting, toolbar and list editing on for that window without renaming the file.
- Printing a plain text window prints the raw text.

## Editing

- Find, Find & Replace and Use Selection for Find use the inline find bar.
- Check spelling while typing is on by default.
- Smart quotes, smart dashes, text replacement, link detection and auto-correct are off by default, because they corrupt Markdown.
- Return continues lists. Return on an empty item ends the list.
- Tab and Shift-Tab indent and outdent list items and selected lines.
- View ▸ Show Line Numbers numbers each line of the file. A line that wraps onto several rows gets one number. View ▸ Show Indentation Guides draws a faint line at each indent level, every four spaces or tab. Both are off by default and apply to every window.

## Print and export

Print and Export as PDF use the rendered preview, in light colors, whichever theme is showing. Page Setup settings apply to both.

## Settings

Editor font size, default layout for Markdown files, preview theme, preview zoom, and Scale Preview to Window. All are saved between launches.
