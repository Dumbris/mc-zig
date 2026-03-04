# mc-zig

A fast [Midnight Commander](https://midnight-commander.org/) clone built in Zig for macOS/iTerm2. Single binary, zero dependencies, 256-color terminal UI.

![Zig](https://img.shields.io/badge/Zig-0.15.2-f7a41d?logo=zig&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Dual-panel file browser** with independent navigation
- **File operations**: Copy (F5), Move (F6), Delete (F8), Mkdir (F7), Rename (Shift+F6)
- **File tagging**: Insert to tag, batch operations on tagged files
- **File viewer (F3)**: Text, hex, Markdown readability, HTML readability modes
- **Editor integration**: F4 launches `$EDITOR` / vim / vi
- **Ctrl+O**: Toggle panels to see the terminal underneath
- **Quick search**: Alt+letter to jump by prefix
- **7 color themes**: Classic, Nord, Dracula, Solarized, Gruvbox, DOS Navigator, Mono
- **Dropdown menus**: F9 for options, F2 for file menu, full menu bar navigation
- **INI configuration**: `~/.config/mc-zig/config.ini`

## Install

### Homebrew

```bash
brew install Dumbris/tap/mc-zig
```

### From source

Requires [Zig 0.15.2+](https://ziglang.org/download/):

```bash
git clone https://github.com/Dumbris/mc-zig.git
cd mc-zig
zig build -Doptimize=ReleaseFast
cp zig-out/bin/mc /usr/local/bin/
```

## Usage

```bash
mc                       # Open in current directory
mc /path/left /path/right # Open with specific panel directories
```

## Keyboard Bindings

| Key | Action |
|-----|--------|
| Tab | Switch active panel |
| Enter | Enter directory / view file |
| F2 | File menu |
| F3 | View file |
| F4 | Edit with $EDITOR |
| F5 | Copy to other panel |
| F6 | Move to other panel |
| F7 | Create directory |
| F8 | Delete |
| F9 | Options menu |
| F10 | Quit |
| Ctrl+O | Toggle panels / console |
| Insert | Tag / untag file |
| Shift+F6 | Rename |
| `.` | Toggle hidden files |
| Alt+letter | Quick search |

## Themes

Switch themes via F9 > Theme or the Options menu.

| Theme | Description |
|-------|-------------|
| Classic | Traditional MC blue panels |
| Nord | Arctic, north-bluish palette |
| Dracula | Dark purple theme |
| Solarized | Ethan Schoonover's dark scheme |
| Gruvbox | Retro groove colors |
| DOS Navigator | Authentic cyan DOS feel |
| Mono | Black and white |

## Configuration

Config file at `~/.config/mc-zig/config.ini`:

```ini
[general]
theme=classic
editor=vim
show_hidden=false
```

## Building & Testing

```bash
zig build              # Debug build
zig build -Doptimize=ReleaseFast  # Release build
zig build test         # Run all 45 tests
zig build run          # Build and run
```

## Architecture

```
src/
├── main.zig          Entry point, signal handlers
├── app.zig           Application state machine
├── terminal.zig      Raw POSIX terminal, double-buffered rendering
├── input.zig         Escape sequence parser (CSI/SS3)
├── config/           INI config + 7 color themes
├── fs/               Directory listing, file operations
├── ui/               Panel, dialog, statusbar, menu, layout
└── viewer/           Text, hex, markdown, HTML viewers
```

## License

MIT
