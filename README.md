# Marginleaf

A small, fast, native Mac app for reading and editing Markdown, with inline comments you can copy out and hand to someone else (or to an AI agent).

It opens fast, stays small, and does one thing: show a note nicely, or show its source so you can edit it.

> Apple Silicon, macOS 13 or later. Free and open source (MIT).

## Features

- **Preview and Source** are the same file in two views. `Cmd+E` switches between them.
- **Preview:** GitHub-flavoured Markdown (tables, task lists, footnotes, strikethrough, autolinks), images next to the note, light and dark mode that follows the system, prose in a readable column while tables and code use the full window width.
- **Source:** a plain native text view with light Markdown colouring. No toolbar, no autocomplete, built to stay responsive on large files.
- **Inline comments**, in both Preview and Source:
  - Select text and press `Option+Cmd+M` (or right-click → Comment), write, `Cmd+Enter` saves.
  - Hover any paragraph, list item, table or code block in the Preview: it is outlined and the pointer turns into a comment bubble. Click (without selecting text) to comment on the whole block.
  - Highlights are yellow; click one to edit or delete it. The toolbar toggle hides them.
  - `Shift+Cmd+C` copies every comment, with the highlighted text and line numbers, as Markdown.
  - Comments live next to the note in `note.md.comments.json`. They follow the text when you edit the note, as long as the passage still starts the same way.
- **File explorer** on the left, like a notes vault: `Ctrl+Cmd+S` shows or hides it, `Shift+Cmd+O` picks another folder.
- **Find and replace** in Source (`Option+Cmd+F`).
- **Safe saving:** line endings (LF/CRLF), BOM and the trailing newline are preserved, and an unchanged file saves back byte for byte.
- **Live reload:** if the file changes on disk (git, an editor, a script) Marginleaf reloads it, or asks if you have unsaved edits.
- **Safe to open anything:** raw HTML in a note is dropped and the preview runs no scripts.

## Install

1. Download `Marginleaf.dmg` from the [latest release](../../releases/latest).
2. Open it. A window appears with the app and an Applications folder: **drag Marginleaf onto Applications**.
3. First launch: Marginleaf is not signed with an Apple Developer ID (that costs $99 a year), so macOS blocks it the first time. Do either of these once:
   - **macOS 15 or later:** open the app, dismiss the warning, then go to *System Settings → Privacy & Security*, scroll down and click **Open Anyway**.
   - **Any version:** run `xattr -dr com.apple.quarantine /Applications/Marginleaf.app` in Terminal.
4. Optional, make it the default for Markdown: select any `.md` file in Finder, *File → Get Info → Open with → Marginleaf → Change All…*.

Prefer to build it yourself? See below.

## Build from source

You need a Mac with Xcode or the Xcode command line tools (Swift 5.9 or later).

```sh
git clone https://github.com/fernandomoitinho/marginleaf.git
cd marginleaf
swift test                      # unit tests
bash scripts/make-app.sh        # builds build/Marginleaf.app and build/Marginleaf.dmg
open build/Marginleaf.app
```

`create-dmg` (`brew install create-dmg`) is optional: with it the disk image gets the drag-to-Applications layout, without it you get a plain image.

## How it is put together

```
Sources/MarginleafCore/   Pure Swift, no AppKit, unit-tested:
                          Renderer (Markdown → HTML via cmark-gfm), Style (preview CSS),
                          TextCodec (UTF-8, CRLF, BOM round trips), FenceScanner (code fences),
                          Comments (model, JSON sidecar, copy format).
Sources/Marginleaf/       The app (AppKit + WebKit):
                          MarkdownDocument (NSDocument: read, write, external changes),
                          DocumentWindowController (toolbar, Source/Preview, sidebar),
                          CommentsController (selection, highlights, popover, injected script),
                          MarkdownHighlighter (per-paragraph colouring), SidebarViewController,
                          MainMenu, AppDelegate.
Resources/                Info.plist, app icon, disk image background.
scripts/                  make-app.sh (.app and .dmg), smoke.sh (CI launch check).
Tests/MarginleafCoreTests/
```

Design notes:

- The Preview is a `WKWebView` with page JavaScript turned off and a strict Content-Security-Policy. The comment script runs in a separate content world through `WKUserScript`, so it works even though the note's own scripts cannot.
- cmark's `sourcepos` option tags each block with its source lines. That is how a comment made on rendered text gets a line number, and how comments are found again after the file changes.
- Typing only recolours the paragraph being edited, so a keystroke costs the same whatever the file size.
- Saving runs on a background thread from a snapshot taken on the main thread, so a slow disk never freezes the window.

## Contributing

Issues and pull requests are welcome. Please run `swift test` first and keep the app light: no new dependencies unless there is a strong reason. Features that are out of scope on purpose: tabs, split view, PDF export, cross-file search, wikilinks, sync.

## Credits and license

MIT, see [LICENSE](LICENSE). Markdown rendering by GitHub's [cmark-gfm](https://github.com/github/cmark-gfm) through [swift-cmark](https://github.com/swiftlang/swift-cmark) (BSD-2-Clause).
