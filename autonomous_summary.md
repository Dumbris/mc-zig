# mc-zig: Autonomous Implementation Summary

## Overview

Successfully built a Midnight Commander clone in Zig 0.15.2 for iTerm2/macOS. The project compiles to a single ~1.7MB native ARM64 binary with **zero external dependencies**.

## Build & Test Status

- **Build**: PASS — `zig build` produces `zig-out/bin/mc`
- **Tests**: 45/45 PASS — `zig build test`
- **Binary**: 1,757,696 bytes, Mach-O 64-bit ARM64

## Architecture

```
src/
├── main.zig          — Entry point, signal handlers (SIGWINCH/SIGINT/SIGTERM)
├── app.zig           — Application state machine (normal/viewer/dialog/quick_search modes)
├── terminal.zig      — Raw POSIX terminal, double-buffered 256-color cell rendering
├── input.zig         — Escape sequence state machine (CSI/SS3 parser)
├── config/
│   ├── config.zig    — INI config parser (~/.config/mc-zig/config.ini)
│   └── theme.zig     — 6 built-in themes (Classic, Nord, Dracula, Solarized, Gruvbox, Mono)
├── fs/
│   ├── dir.zig       — Directory listing, sorting, size/date formatting
│   └── ops.zig       — File copy/move/delete with progress, recursive operations
├── ui/
│   ├── panel.zig     — File panel widget (navigation, tagging, quick search)
│   ├── dialog.zig    — Modal dialogs (confirm, input, progress, conflict, error)
│   ├── statusbar.zig — Function key bar, status line, command prompt
│   ├── layout.zig    — Screen layout calculator
│   └── menu.zig      — Menu bar rendering
└── viewer/
    ├── viewer.zig    — File viewer controller (text/hex/markdown/html modes)
    ├── markdown.zig  — Markdown readability renderer (headers, lists, code blocks)
    ├── html.zig      — HTML tag stripper with entity decoding
    └── hex.zig       — Hex dump viewer (16 bytes/line)
```

## Key Features Implemented

1. **Dual-panel file browser** — Two panels with independent navigation, Tab to switch
2. **File operations** — Copy (F5), Move (F6), Delete (F8), Mkdir (F7), Rename (Shift+F6)
3. **File tagging** — Insert key to tag files, batch operations on tagged files
4. **Ctrl+O panel toggle** — Switches to/from alternate screen buffer
5. **File viewer (F3)** — Text, hex, markdown readability, HTML readability modes
6. **Quick search** — Alt+letter to jump to files by prefix
7. **Editor integration** — F4 launches $EDITOR/vim/vi
8. **6 color themes** — Classic (blue), Nord, Dracula, Solarized Dark, Gruvbox, Monochrome
9. **INI configuration** — Theme, editor, show_hidden settings
10. **Signal handling** — Clean resize (SIGWINCH), clean exit (SIGINT/SIGTERM)

## Keyboard Bindings

| Key | Action |
|-----|--------|
| Tab | Switch panels |
| Enter | Enter directory / view file |
| F3 | View file |
| F4 | Edit with $EDITOR |
| F5 | Copy |
| F6 | Move |
| F7 | Make directory |
| F8 | Delete |
| F10 | Quit |
| Ctrl+O | Toggle panels/console |
| Insert | Tag/untag file |
| Shift+F6 | Rename |
| . (dot) | Toggle hidden files |

## Bugs Fixed During Implementation

1. **Zig 0.15.2 API changes** — ArrayList unmanaged API, termios flags, Sigaction, StdIo enum, stdout, symLink flags, sort context
2. **Input parser CSI bug** — `self.reset()` cleared params before `handleTilde()` read them; inlined the tilde logic with saved params
3. **Input parser range bug** — Ctrl+O (0x0f) and Ctrl+S (0x13) excluded from control key range
4. **HTML viewer use-after-free** — Intermediate text buffer freed while StyledLine slices still referenced it; introduced `HtmlRenderResult` struct to transfer buffer ownership
5. **formatSize test** — Used `trimRight` instead of `trim` for right-aligned output
6. **Overlapping memcpy crash** — `cwd` returned slice into `left_path_buf`, then `@memcpy` copied it back into the same buffer; used separate `cwd_buf`
7. **Socket file crash** — `openFileAbsolute` on Unix sockets triggers Zig's "unexpected errno" panic trace; added entry kind guard to only view regular files/symlinks

## Manual Testing (tmux)

All features verified interactively in tmux:
- Dual panels render correctly with borders and file listings
- Cursor navigation (arrows, Home, Page)
- Tab switches active panel
- Enter navigates into directories
- F3 viewer: text mode, hex mode (F4 toggle), markdown readability, HTML readability, F2 toggle
- F7 mkdir dialog with text input and OK/Cancel buttons
- F5 copy dialog with confirmation
- Ctrl+O panel toggle (alternate screen buffer)
- F10 clean exit
- Socket files safely ignored (no crash)

## Usage

```bash
zig build                    # Build
zig-out/bin/mc               # Run in current directory
zig-out/bin/mc /path1 /path2 # Run with specific panel directories
zig build test               # Run tests
```
