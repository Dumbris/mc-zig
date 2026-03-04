# Shell Execution & Command Line Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add MC-style command line, executable launching, shell command execution, and fix Ctrl+C handling.

**Architecture:** Extend the existing App state machine with a command buffer, route printable chars to it in normal mode, and use the same leave-alt-screen/spawn-child pattern already used by F4 editor. Fix Ctrl+C by removing SIGINT force-exit and handling 0x03 in the input parser.

**Tech Stack:** Zig 0.15.2, POSIX termios, std.process.Child

---

### Task 1: Add Ctrl+C key event to input parser

**Files:**
- Modify: `src/input.zig:4-46` (Key enum)
- Modify: `src/input.zig:87-96` (handleGround ctrl range)

**Step 1: Add `ctrl_c` to Key enum**

In `src/input.zig`, add `ctrl_c` after `ctrl_r` in the Key enum (line ~39):

```zig
ctrl_r,
ctrl_c,
ctrl_backslash,
```

**Step 2: Handle 0x03 in handleGround**

In `src/input.zig`, the range `0x01...0x08` already covers 0x03. Add a case in the switch at line 89:

```zig
return switch (byte) {
    0x03 => InputEvent{ .key = .ctrl_c }, // Ctrl+C
    0x0f => InputEvent{ .key = .ctrl_o }, // Ctrl+O
    0x13 => InputEvent{ .key = .ctrl_s }, // Ctrl+S
    0x12 => InputEvent{ .key = .ctrl_r }, // Ctrl+R
    0x18 => InputEvent{ .key = .ctrl_x }, // Ctrl+X
    0x1c => InputEvent{ .key = .ctrl_backslash }, // Ctrl+backslash
    else => null,
};
```

**Step 3: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass (no test touches Ctrl+C)

**Step 4: Commit**

```bash
git add src/input.zig
git commit -m "Add ctrl_c key event to input parser"
```

---

### Task 2: Fix SIGINT handler — don't force-exit

**Files:**
- Modify: `src/main.zig:18-24` (handleSigint)
- Modify: `src/app.zig:168-214` (handleNormalInput)

**Step 1: Change SIGINT handler to no-op**

In `src/main.zig`, replace the `handleSigint` function (lines 18-24):

```zig
fn handleSigint(_: c_int) callconv(.c) void {
    // Do nothing — Ctrl+C is handled in the input parser.
    // During shell command execution, we're out of raw mode
    // so SIGINT goes to the child process naturally.
}
```

**Step 2: Handle `.ctrl_c` in app's normal mode as no-op**

In `src/app.zig` `handleNormalInput`, add before the `else => {}` at line 213:

```zig
.ctrl_c => {}, // Ignore in normal mode — prevents accidental exit
```

**Step 3: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass

**Step 4: Commit**

```bash
git add src/main.zig src/app.zig
git commit -m "Fix Ctrl+C: no longer force-exits mc"
```

---

### Task 3: Add command buffer fields to App struct

**Files:**
- Modify: `src/app.zig:43-61` (App struct fields)

**Step 1: Add command buffer fields**

In `src/app.zig`, add after `menu_cursor` (line 61):

```zig
menu_cursor: usize = 0,
// Command line buffer
cmd_buf: [1024]u8 = undefined,
cmd_len: usize = 0,
cmd_cursor: usize = 0,
```

**Step 2: Build**

Run: `zig build`
Expected: Compiles (fields are unused but that's OK in Zig)

**Step 3: Commit**

```bash
git add src/app.zig
git commit -m "Add command line buffer fields to App"
```

---

### Task 4: Update statusbar to render command buffer text

**Files:**
- Modify: `src/ui/statusbar.zig:53-64` (renderCommandLine)
- Modify: `src/app.zig:877-878` (call site)

**Step 1: Update renderCommandLine signature and rendering**

In `src/ui/statusbar.zig`, replace `renderCommandLine` (lines 53-64):

```zig
pub fn renderCommandLine(term: *term_mod.Terminal, y: u16, path: []const u8, cmd_text: []const u8, cmd_cursor: usize, colors: theme_mod.ThemeColors) void {
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.panel_fg, .bg = 0 });
    }

    // Show current path as prompt
    const prompt_suffix = "$ ";
    const max_path_w = if (term.width > 20) term.width / 3 else 5;
    const display_path = if (path.len > max_path_w) path[path.len - max_path_w ..] else path;
    term.writeString(0, y, display_path, colors.panel_fg, 0, false);
    const prompt_end: u16 = @intCast(display_path.len);
    term.writeString(prompt_end, y, prompt_suffix, colors.panel_fg, 0, true);

    // Show command text after prompt
    const text_start: u16 = prompt_end + @as(u16, @intCast(prompt_suffix.len));
    if (cmd_text.len > 0) {
        const max_cmd = if (term.width > text_start) term.width - text_start else 0;
        const display_cmd = if (cmd_text.len > max_cmd) cmd_text[0..max_cmd] else cmd_text;
        term.writeString(text_start, y, display_cmd, colors.panel_fg, 0, false);
    }

    // Show cursor
    const cursor_x = text_start + @as(u16, @intCast(cmd_cursor));
    if (cursor_x < term.width) {
        const ch: u8 = if (cmd_cursor < cmd_text.len) cmd_text[cmd_cursor] else ' ';
        term.setCell(cursor_x, y, .{ .char = ch, .fg = 0, .bg = colors.panel_fg });
    }
}
```

**Step 2: Update call site in app.zig**

In `src/app.zig`, replace line 878:

```zig
statusbar.renderCommandLine(&self.terminal, self.layout.command_row, self.panels[self.active_panel].getPath(), self.cmd_buf[0..self.cmd_len], self.cmd_cursor, colors);
```

**Step 3: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass

**Step 4: Commit**

```bash
git add src/ui/statusbar.zig src/app.zig
git commit -m "Render command buffer text and cursor in status bar"
```

---

### Task 5: Route printable chars to command buffer in normal mode

**Files:**
- Modify: `src/app.zig:168-214` (handleNormalInput)

**Step 1: Rewrite char handling and Enter/Backspace/Escape for command buffer**

In `src/app.zig` `handleNormalInput`, replace the `.enter` and `.char` handlers. The logic:
- If `cmd_len > 0` and Enter pressed → execute command (Task 7)
- If `cmd_len == 0` and Enter pressed → navigate or execute file (existing + Task 6)
- Arrow keys only go to panel when `cmd_len == 0`
- Backspace deletes from cmd_buf
- Escape clears cmd_buf
- Printable chars append to cmd_buf (except `.` and `q` which keep their behavior when buffer is empty)

Replace the entire `handleNormalInput` function body (lines 168-215):

```zig
fn handleNormalInput(self: *App, event: input_mod.InputEvent) void {
    const panel = &self.panels[self.active_panel];
    const vis_rows = self.layout.panelListingHeight();
    const has_cmd = self.cmd_len > 0;

    switch (event.key) {
        // Navigation — only when command buffer is empty
        .up => if (!has_cmd) panel.cursorUp(),
        .down => if (!has_cmd) panel.cursorDown(),
        .page_up => if (!has_cmd) panel.pageUp(vis_rows),
        .page_down => if (!has_cmd) panel.pageDown(vis_rows),
        .home => if (has_cmd) {
            self.cmd_cursor = 0;
        } else panel.goHome(),
        .end => if (has_cmd) {
            self.cmd_cursor = self.cmd_len;
        } else panel.goEnd(),
        .left => if (has_cmd) {
            if (self.cmd_cursor > 0) self.cmd_cursor -= 1;
        },
        .right => if (has_cmd) {
            if (self.cmd_cursor < self.cmd_len) self.cmd_cursor += 1;
        },

        .enter => {
            if (has_cmd) {
                self.executeShellCommand();
            } else {
                // Check if current entry is executable
                const entry = panel.getCurrentEntry() orelse return;
                if (entry.kind == .directory) {
                    panel.navigate(self.config.show_hidden) catch {};
                } else if (entry.is_executable) {
                    self.executeFile();
                }
            }
        },

        .backspace => {
            if (has_cmd and self.cmd_cursor > 0) {
                // Remove char before cursor
                const i = self.cmd_cursor;
                if (i < self.cmd_len) {
                    std.mem.copyForwards(u8, self.cmd_buf[i - 1 .. self.cmd_len - 1], self.cmd_buf[i..self.cmd_len]);
                }
                self.cmd_len -= 1;
                self.cmd_cursor -= 1;
            }
        },

        .escape => {
            self.cmd_len = 0;
            self.cmd_cursor = 0;
        },

        .tab => {
            if (!has_cmd) {
                self.panels[self.active_panel].is_active = false;
                self.active_panel = ~self.active_panel;
                self.panels[self.active_panel].is_active = true;
            }
        },
        .insert => if (!has_cmd) panel.toggleTag(),
        .delete => {
            if (has_cmd and self.cmd_cursor < self.cmd_len) {
                const i = self.cmd_cursor;
                if (i + 1 < self.cmd_len) {
                    std.mem.copyForwards(u8, self.cmd_buf[i .. self.cmd_len - 1], self.cmd_buf[i + 1 .. self.cmd_len]);
                }
                self.cmd_len -= 1;
            }
        },

        .f3 => if (!has_cmd) self.openViewer(),
        .f4 => if (!has_cmd) self.openEditor(),
        .f5 => if (!has_cmd) self.startCopy(),
        .f6 => if (!has_cmd) self.startMove(),
        .shift_f6 => if (!has_cmd) self.startRename(),
        .f7 => if (!has_cmd) self.startMkdir(),
        .f8 => if (!has_cmd) self.startDelete(),
        .f10 => self.running = false,
        .ctrl_o => self.togglePanels(),
        .ctrl_c => {
            // Clear command buffer if non-empty, otherwise ignore
            if (has_cmd) {
                self.cmd_len = 0;
                self.cmd_cursor = 0;
            }
        },
        .ctrl_s => {
            if (!has_cmd) {
                self.mode = .quick_search;
                self.search_len = 0;
            }
        },
        .ctrl_r => {
            if (!has_cmd) {
                panel.loadDirectory(self.config.show_hidden) catch {};
            }
        },
        .f9 => self.openMenu(.options),
        .f2 => self.openMenu(.file),

        .char => {
            if (!has_cmd) {
                // Special single-char shortcuts only when buffer is empty
                if (event.char == 'q' or event.char == 'Q') {
                    self.running = false;
                    return;
                } else if (event.char == '.') {
                    self.config.show_hidden = !self.config.show_hidden;
                    self.panels[0].loadDirectory(self.config.show_hidden) catch {};
                    self.panels[1].loadDirectory(self.config.show_hidden) catch {};
                    return;
                }
            }
            // Append to command buffer
            if (self.cmd_len < self.cmd_buf.len) {
                const byte: u8 = @intCast(event.char & 0xFF);
                if (byte >= 0x20 and byte < 0x7f) {
                    // Insert at cursor position
                    if (self.cmd_cursor < self.cmd_len) {
                        std.mem.copyBackwards(u8, self.cmd_buf[self.cmd_cursor + 1 .. self.cmd_len + 1], self.cmd_buf[self.cmd_cursor..self.cmd_len]);
                    }
                    self.cmd_buf[self.cmd_cursor] = byte;
                    self.cmd_len += 1;
                    self.cmd_cursor += 1;
                }
            }
        },
        else => {},
    }
}
```

**Step 2: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass

**Step 3: Commit**

```bash
git add src/app.zig
git commit -m "Route printable chars to command buffer in normal mode"
```

---

### Task 6: Implement executeFile (Enter on executable)

**Files:**
- Modify: `src/app.zig` (add `executeFile` method after `openEditor`)

**Step 1: Add executeFile method**

In `src/app.zig`, add after `openEditor` (after line 375):

```zig
fn executeFile(self: *App) void {
    const panel = &self.panels[self.active_panel];
    const entry = panel.getCurrentEntry() orelse return;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ panel.getPath(), entry.getName() }) catch return;

    self.runExternalCommand(&.{ path }, panel.getPath());
}
```

**Step 2: Add `runExternalCommand` helper (shared with Task 7)**

Add the shared helper that handles leave-alt-screen, spawn, wait, press-enter, restore:

```zig
fn runExternalCommand(self: *App, argv: []const []const u8, cwd: []const u8) void {
    // Leave alt screen and raw mode
    self.terminal.leaveAltScreen() catch {};
    self.terminal.disableRawMode();

    // Spawn child process
    var child = std.process.Child.init(argv, self.allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.cwd = cwd;
    child.spawn() catch |err| {
        const stderr = std.fs.File.stderr();
        var ebuf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&ebuf, "Failed to run: {s}\r\n", .{@errorName(err)}) catch "Failed to run command\r\n";
        stderr.writeAll(msg) catch {};
        self.waitForEnter();
        self.terminal.enableRawMode() catch {};
        self.terminal.enterAltScreen() catch {};
        self.needs_full_redraw = true;
        return;
    };
    _ = child.wait() catch {};

    // Prompt and wait
    self.waitForEnter();

    // Restore terminal
    self.terminal.enableRawMode() catch {};
    self.terminal.enterAltScreen() catch {};

    // Refresh directories (files may have changed)
    self.panels[0].loadDirectory(self.config.show_hidden) catch {};
    self.panels[1].loadDirectory(self.config.show_hidden) catch {};
    self.needs_full_redraw = true;
}

fn waitForEnter(self: *App) void {
    _ = self;
    const out = std.fs.File.stderr();
    out.writeAll("\r\nPress Enter to continue...") catch {};
    // Read bytes until Enter (0x0d or 0x0a)
    const stdin = std.fs.File.stdin();
    var buf: [1]u8 = undefined;
    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;
        if (buf[0] == 0x0d or buf[0] == 0x0a) break;
    }
}
```

**Step 3: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass

**Step 4: Commit**

```bash
git add src/app.zig
git commit -m "Add executeFile: Enter on executable runs it"
```

---

### Task 7: Implement executeShellCommand

**Files:**
- Modify: `src/app.zig` (add `executeShellCommand` method)

**Step 1: Add executeShellCommand method**

In `src/app.zig`, add after `executeFile`:

```zig
fn executeShellCommand(self: *App) void {
    if (self.cmd_len == 0) return;

    // Build command string
    const cmd_text = self.cmd_buf[0..self.cmd_len];

    // Get CWD from active panel
    const cwd = self.panels[self.active_panel].getPath();

    // Clear command buffer
    self.cmd_len = 0;
    self.cmd_cursor = 0;

    // Execute via /bin/sh -c
    self.runExternalCommand(&.{ "/bin/sh", "-c", cmd_text }, cwd);
}
```

**Step 2: Build and run tests**

Run: `zig build test`
Expected: All 45 tests pass

**Step 3: Commit**

```bash
git add src/app.zig
git commit -m "Add shell command execution from command line"
```

---

### Task 8: tmux integration testing

**No files to modify — verification only.**

**Step 1: Build release binary**

Run: `zig build`

**Step 2: Test command line input**

```bash
tmux new-session -d -s test -x 120 -y 35
tmux send-keys -t test './zig-out/bin/mc' Enter
sleep 1
# Type "ls" — should appear in command line
tmux send-keys -t test 'ls'
sleep 0.5
tmux capture-pane -t test -p  # Verify "$ ls" visible in command row
```

**Step 3: Test shell command execution**

```bash
# Press Enter to execute "ls"
tmux send-keys -t test Enter
sleep 1
tmux capture-pane -t test -p  # Should see ls output + "Press Enter to continue..."
tmux send-keys -t test Enter
sleep 1
tmux capture-pane -t test -p  # Should be back in MC panels
```

**Step 4: Test Enter on executable**

```bash
# Navigate to an executable and press Enter
tmux send-keys -t test Enter  # on a directory to enter it
sleep 0.5
# Find mc binary in zig-out/bin, press Enter on it
# Verify it runs and shows output
```

**Step 5: Test Ctrl+O shows last output**

```bash
# After running a command, Ctrl+O should show the terminal with last output
tmux send-keys -t test C-o
sleep 0.5
tmux capture-pane -t test -p  # Should see terminal with last command output
tmux send-keys -t test C-o
sleep 0.5
tmux capture-pane -t test -p  # Should be back in panels
```

**Step 6: Test Ctrl+C doesn't kill mc**

```bash
tmux send-keys -t test C-c
sleep 0.5
tmux capture-pane -t test -p  # MC should still be running
```

**Step 7: Clean up**

```bash
tmux send-keys -t test F10
tmux kill-session -t test
```

**Step 8: Run full test suite**

Run: `zig build test`
Expected: All 45 tests pass (regression check)

---

### Task 9: Commit, tag, and push release

**Step 1: Final commit if needed**

```bash
git add -A
git status  # Verify only expected files
```

**Step 2: Update tag and push**

```bash
git tag v0.2.0
git push origin main --tags
```

The GitHub Actions release workflow will build binaries and update the Homebrew formula automatically.
