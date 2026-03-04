# MC-Zig: Midnight Commander Clone Design

## Overview

A fast, Zig-native dual-panel file manager inspired by Midnight Commander and FAR Manager, targeting iTerm2 on macOS. Uses direct ANSI escape sequences for maximum performance — no ncurses dependency.

## Architecture

### Approach: Raw Terminal + Event Loop

Direct POSIX termios + ANSI escape sequences. No external TUI library. This gives us:
- Zero dependency overhead
- Full control over rendering pipeline
- Double-buffered screen updates (diff-based, only redraw changed cells)
- Sub-millisecond input response times

### Core Modules

```
src/
├── main.zig          # Entry point, arg parsing
├── app.zig           # Application state machine
├── terminal.zig      # Raw mode, escape sequences, screen buffer
├── input.zig         # Input parsing (keys, mouse, escape sequences)
├── event.zig         # Event loop (poll-based I/O)
├── ui/
│   ├── panel.zig     # File panel widget
│   ├── dialog.zig    # Modal dialogs (copy, move, mkdir, confirm)
│   ├── menu.zig      # Top menu bar (F9)
│   ├── statusbar.zig # Function key bar + hint line
│   └── layout.zig    # Layout manager (vertical/horizontal split)
├── fs/
│   ├── ops.zig       # File operations (copy, move, delete, mkdir)
│   ├── dirlist.zig   # Directory listing + sorting
│   └── watcher.zig   # File change detection (kqueue on macOS)
├── viewer/
│   ├── viewer.zig    # Internal file viewer
│   ├── hex.zig       # Hex view mode
│   ├── markdown.zig  # Markdown readability renderer
│   └── html.zig      # HTML readability renderer (strip tags, format)
├── config/
│   ├── config.zig    # Configuration loading/saving
│   └── theme.zig     # Color theme system
└── utils/
    ├── utf8.zig      # UTF-8 string utilities
    └── path.zig      # Path manipulation
```

### Build Output

Single static binary: `zig-out/bin/mc`

## UI Layout

```
┌─ Menu Bar ──────────────────────────────────────────────────┐
│ Left    File    Command    Options                          │
├────────────── Left Panel ─┬──────────── Right Panel ────────┤
│ /home/user/projects       │ /home/user/documents            │
│ ..                   <DIR>│ ..                        <DIR> │
│ src/                 <DIR>│ notes.md               1.2K    │
│ README.md            4.5K│ report.pdf            52.3K    │
│ build.zig            2.1K│ image.png            128.0K    │
│                           │                                 │
├───────────────────────────┴─────────────────────────────────┤
│ Hint: Use F5 to copy, F6 to move                          │
├─────────────────────────────────────────────────────────────┤
│ user@host:~/projects$                                       │
├─────────────────────────────────────────────────────────────┤
│ 1Help 2Menu 3View 4Edit 5Copy 6Move 7Mkdir 8Del 9Menu 10Quit│
└─────────────────────────────────────────────────────────────┘
```

## Key Features

### 1. Dual Panel File Browser
- Tab switches active panel
- Arrow keys navigate, Enter opens dir/executes file
- Insert tags files for batch operations
- Alt+T cycles listing modes (brief/full/long)
- Quick search with Ctrl+S

### 2. File Operations
- F5: Copy (active → inactive panel)
- F6: Move/Rename
- Shift+F6: Rename only
- F7: Create directory
- F8: Delete (with confirmation dialog)
- All operations show progress for large files

### 3. Ctrl+O Panel Toggle
- Hides panels, reveals full terminal with shell output
- Preserves the subshell scrollback
- Press Ctrl+O again to restore panels
- Current directory syncs between MC and shell

### 4. File Viewer (F3)
- Text mode with line wrapping
- Hex mode toggle (F4 within viewer)
- Search with regex (F7)
- For .md files: raw mode + readability mode (parsed markdown with formatting)
- For .html files: raw mode + readability mode (stripped tags, formatted text)
- Toggle between modes with F2

### 5. Editor Integration (F4)
- Launches $EDITOR (defaults to vim)
- Falls back to vi if vim not found
- Returns to MC after editor exits

### 6. Color Themes

Config file: `~/.config/mc-zig/config.ini`

Built-in themes:
1. **Classic** — Blue panels, cyan highlights (traditional MC)
2. **Nord** — Arctic, bluish tones (cool, easy on eyes)
3. **Dracula** — Dark purple background, vibrant accents
4. **Solarized Dark** — Precision-engineered warm/cool palette
5. **Gruvbox** — Retro warm tones, high contrast
6. **Monochrome** — Pure grayscale for minimal terminals

Theme format (INI):
```ini
[theme]
name = classic
panel_bg = blue
panel_fg = white
selected_bg = cyan
selected_fg = black
menu_bg = black
menu_fg = yellow
status_bg = cyan
status_fg = black
dialog_bg = white
dialog_fg = black
```

### 7. Directory Hotlist
- Ctrl+\ opens hotlist
- Ctrl+X H adds current directory
- Persistent across sessions

## Assumptions (Design Decisions)

1. **No mouse support initially** — keyboard-only like original MC
2. **No FTP/VFS** — local filesystem only per requirements
3. **No built-in editor** — shells out to vim/nvim/vi
4. **UTF-8 only** — no legacy encoding support
5. **macOS primary target** — uses kqueue for file watching, POSIX for terminal
6. **Config format: INI** — simple, no TOML/YAML dependency
7. **256-color support** — uses 256-color ANSI palette for themes (works in all modern terminals)
8. **Markdown rendering** — basic: headers, bold, italic, lists, code blocks
9. **HTML readability** — strip tags, preserve paragraph structure, basic formatting
10. **File size display** — human-readable (K, M, G) with automatic scaling
11. **Sorting** — name (default), size, date, extension; toggle with panel menu
12. **Symlink handling** — show target, follow for navigation
13. **Permission display** — rwx format in long listing mode
14. **Progress dialogs** — for copy/move operations over 1MB
15. **Zig build system** — `zig build` produces `mc` binary, `zig build test` runs tests
