# Shell Execution & Command Line Design

Date: 2026-03-04

## Overview

Add shell command execution to mc-zig: MC-style auto-capture command line, Enter on executables, Ctrl+C forwarding to child processes, and Ctrl+O to view last output.

## Features

### 1. Command Line Input (MC-style auto-capture)

Any printable character typed in normal mode appends to a command buffer. The status bar command line shows `<path>$ <typed_text>` with a cursor.

- **Printable chars** (0x20-0x7e): append to `command_buffer`
- **Backspace**: delete char before cursor
- **Enter**: execute the command string via shell
- **Escape**: clear buffer, return focus to panels
- **Left/Right/Home/End**: cursor movement within buffer
- Panel keys (F2-F10, Tab, arrows when buffer empty) still work normally

New field in App: `command_buffer: [1024]u8`, `command_len: u16`, `command_cursor: u16`.

### 2. Enter on Executable

When Enter is pressed on a file with `is_executable=true` and command buffer is empty:

1. Build full path from panel CWD + entry name
2. Leave alt screen, disable raw mode
3. Spawn process with inherited stdio via `std.process.Child`
4. Wait for exit
5. Print "Press Enter to continue..."
6. Wait for Enter keypress (raw read from stdin)
7. Restore raw mode, enter alt screen, refresh panels

### 3. Shell Command Execution

When Enter is pressed with non-empty command buffer:

1. Save command text, clear buffer
2. Leave alt screen, disable raw mode
3. Spawn `/bin/sh -c "<command>"` with CWD = active panel directory
4. Child inherits stdin/stdout/stderr (fully interactive)
5. Ctrl+C forwarded to child naturally (not in raw mode)
6. After child exits, print "Press Enter to continue..."
7. Wait for Enter keypress
8. Restore raw mode, enter alt screen
9. Refresh both panel directory listings (files may have changed)

### 4. Ctrl+O Enhancement

Current behavior: toggles alt screen on/off. Enhanced:

- Last command output is visible in terminal scrollback when panels are hidden
- No code change needed beyond running commands in normal screen buffer
- Ctrl+O toggles panels to reveal the output naturally

### 5. Ctrl+C Handling

- **In normal mode**: 0x03 byte treated as no-op (prevents accidental exit)
- **During command execution**: not in raw mode, Ctrl+C goes to child via terminal driver
- Remove SIGINT handler that force-exits. Add 0x03 handling in input parser ground state.
- Keep SIGTERM handler for clean shutdown.

## Files to Modify

| File | Changes |
|------|---------|
| `src/app.zig` | Add command buffer fields, `executeShellCommand()`, `executeFile()`, modify `handleNormalInput()` to route printable chars to command buffer |
| `src/input.zig` | Add 0x03 (Ctrl+C) to ground state handler as `.ctrl_c` key event |
| `src/main.zig` | Remove SIGINT force-exit handler, handle Ctrl+C gracefully |
| `src/ui/statusbar.zig` | Update `renderCommandLine()` to show command buffer text and cursor |
| `src/terminal.zig` | Add `waitForEnter()` helper (disable raw briefly, read until Enter) |

## Testing

- Unit tests: command buffer append/delete/clear operations
- tmux integration: type command, verify execution, verify Ctrl+O shows output
- tmux integration: Enter on executable runs it
- tmux integration: Ctrl+C during command kills child, not mc
- Regression: all 45 existing tests must pass
