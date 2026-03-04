const std = @import("std");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");

pub const DialogKind = enum {
    confirm,
    input,
    progress,
    file_conflict,
    error_msg,
};

pub const DialogResult = enum {
    none,
    ok,
    cancel,
    overwrite,
    skip,
    rename_choice,
    overwrite_all,
};

pub const Dialog = struct {
    kind: DialogKind = .confirm,
    title: [128]u8 = undefined,
    title_len: usize = 0,
    message: [512]u8 = undefined,
    message_len: usize = 0,
    input_buffer: [256]u8 = undefined,
    input_len: usize = 0,
    input_cursor: usize = 0,
    progress: f32 = 0.0,
    progress_file: [256]u8 = undefined,
    progress_file_len: usize = 0,
    progress_done: u64 = 0,
    progress_total: u64 = 0,
    selected_button: u8 = 0,
    button_count: u8 = 2,
    result: DialogResult = .none,

    pub fn initConfirm(title: []const u8, message: []const u8) Dialog {
        var d = Dialog{};
        d.kind = .confirm;
        d.setTitle(title);
        d.setMessage(message);
        d.button_count = 2;
        return d;
    }

    pub fn initInput(title: []const u8, initial_value: []const u8) Dialog {
        var d = Dialog{};
        d.kind = .input;
        d.setTitle(title);
        d.setInput(initial_value);
        d.button_count = 2;
        return d;
    }

    pub fn initProgress(title: []const u8) Dialog {
        var d = Dialog{};
        d.kind = .progress;
        d.setTitle(title);
        d.button_count = 1;
        return d;
    }

    pub fn initConflict(filename: []const u8) Dialog {
        var d = Dialog{};
        d.kind = .file_conflict;
        d.setTitle("File exists");
        d.setMessage(filename);
        d.button_count = 4;
        return d;
    }

    pub fn initError(title: []const u8, message: []const u8) Dialog {
        var d = Dialog{};
        d.kind = .error_msg;
        d.setTitle(title);
        d.setMessage(message);
        d.button_count = 1;
        return d;
    }

    fn setTitle(self: *Dialog, t: []const u8) void {
        const len = @min(t.len, self.title.len);
        @memcpy(self.title[0..len], t[0..len]);
        self.title_len = len;
    }

    fn setMessage(self: *Dialog, m: []const u8) void {
        const len = @min(m.len, self.message.len);
        @memcpy(self.message[0..len], m[0..len]);
        self.message_len = len;
    }

    fn setInput(self: *Dialog, val: []const u8) void {
        const len = @min(val.len, self.input_buffer.len);
        @memcpy(self.input_buffer[0..len], val[0..len]);
        self.input_len = len;
        self.input_cursor = len;
    }

    pub fn getTitle(self: *const Dialog) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn getMessage(self: *const Dialog) []const u8 {
        return self.message[0..self.message_len];
    }

    pub fn getInput(self: *const Dialog) []const u8 {
        return self.input_buffer[0..self.input_len];
    }

    pub fn handleChar(self: *Dialog, ch: u21) void {
        if (self.kind != .input) return;
        if (ch > 127) return; // ASCII only for input
        if (self.input_len >= self.input_buffer.len - 1) return;

        // Insert at cursor
        if (self.input_cursor < self.input_len) {
            var i = self.input_len;
            while (i > self.input_cursor) : (i -= 1) {
                self.input_buffer[i] = self.input_buffer[i - 1];
            }
        }
        self.input_buffer[self.input_cursor] = @intCast(ch);
        self.input_len += 1;
        self.input_cursor += 1;
    }

    pub fn handleBackspace(self: *Dialog) void {
        if (self.kind != .input) return;
        if (self.input_cursor == 0) return;
        self.input_cursor -= 1;
        // Shift remaining chars left
        var i = self.input_cursor;
        while (i < self.input_len - 1) : (i += 1) {
            self.input_buffer[i] = self.input_buffer[i + 1];
        }
        self.input_len -= 1;
    }

    pub fn handleDelete(self: *Dialog) void {
        if (self.kind != .input) return;
        if (self.input_cursor >= self.input_len) return;
        var i = self.input_cursor;
        while (i < self.input_len - 1) : (i += 1) {
            self.input_buffer[i] = self.input_buffer[i + 1];
        }
        self.input_len -= 1;
    }

    pub fn cursorLeft(self: *Dialog) void {
        if (self.input_cursor > 0) self.input_cursor -= 1;
    }

    pub fn cursorRight(self: *Dialog) void {
        if (self.input_cursor < self.input_len) self.input_cursor += 1;
    }

    pub fn cursorHome(self: *Dialog) void {
        self.input_cursor = 0;
    }

    pub fn cursorEnd(self: *Dialog) void {
        self.input_cursor = self.input_len;
    }

    pub fn nextButton(self: *Dialog) void {
        self.selected_button = (self.selected_button + 1) % self.button_count;
    }

    pub fn prevButton(self: *Dialog) void {
        if (self.selected_button == 0) {
            self.selected_button = self.button_count - 1;
        } else {
            self.selected_button -= 1;
        }
    }

    pub fn confirm(self: *Dialog) DialogResult {
        switch (self.kind) {
            .confirm, .error_msg => {
                return if (self.selected_button == 0) .ok else .cancel;
            },
            .input => {
                return if (self.selected_button == 0) .ok else .cancel;
            },
            .progress => return .cancel,
            .file_conflict => {
                return switch (self.selected_button) {
                    0 => .overwrite,
                    1 => .skip,
                    2 => .rename_choice,
                    3 => .overwrite_all,
                    else => .cancel,
                };
            },
        }
    }

    pub fn render(self: *const Dialog, term: *term_mod.Terminal, colors: theme_mod.ThemeColors) void {
        const dialog_w: u16 = @min(60, term.width - 4);
        const dialog_h: u16 = switch (self.kind) {
            .confirm, .error_msg => 7,
            .input => 8,
            .progress => 8,
            .file_conflict => 9,
        };

        const dx = (term.width - dialog_w) / 2;
        const dy = (term.height - dialog_h) / 2;

        // Draw dialog background
        var row: u16 = 0;
        while (row < dialog_h) : (row += 1) {
            var col: u16 = 0;
            while (col < dialog_w) : (col += 1) {
                term.setCell(dx + col, dy + row, .{ .char = ' ', .fg = colors.dialog_fg, .bg = colors.dialog_bg });
            }
        }

        // Border
        drawDialogBorder(term, dx, dy, dialog_w, dialog_h, colors);

        // Title
        const title = self.getTitle();
        if (title.len > 0 and dialog_w > title.len + 4) {
            const title_x = dx + (dialog_w - @as(u16, @intCast(title.len))) / 2;
            term.writeString(title_x, dy, title, colors.dialog_title_fg, colors.dialog_bg, true);
        }

        // Content
        switch (self.kind) {
            .confirm, .error_msg => {
                const msg = self.getMessage();
                const msg_x = dx + 2;
                const max_w = dialog_w - 4;
                const display = if (msg.len > max_w) msg[0..max_w] else msg;
                term.writeString(msg_x, dy + 2, display, colors.dialog_fg, colors.dialog_bg, false);

                if (self.kind == .error_msg) {
                    self.drawButtons(term, dx, dy + dialog_h - 2, dialog_w, colors, &[_][]const u8{"[ OK ]"});
                } else {
                    self.drawButtons(term, dx, dy + dialog_h - 2, dialog_w, colors, &[_][]const u8{ "[ OK ]", "[ Cancel ]" });
                }
            },
            .input => {
                // Input field
                const field_x = dx + 2;
                const field_w = dialog_w - 4;
                var col: u16 = 0;
                while (col < field_w) : (col += 1) {
                    const ch: u21 = if (col < self.input_len) self.input_buffer[col] else '_';
                    const is_cursor = col == self.input_cursor;
                    term.setCell(field_x + col, dy + 3, .{
                        .char = ch,
                        .fg = if (is_cursor) colors.dialog_bg else colors.dialog_fg,
                        .bg = if (is_cursor) colors.dialog_fg else colors.dialog_bg,
                    });
                }

                self.drawButtons(term, dx, dy + dialog_h - 2, dialog_w, colors, &[_][]const u8{ "[ OK ]", "[ Cancel ]" });
            },
            .progress => {
                // Progress bar
                const bar_x = dx + 2;
                const bar_w = dialog_w - 4;
                const filled: u16 = @intFromFloat(@as(f32, @floatFromInt(bar_w)) * self.progress);
                var col: u16 = 0;
                while (col < bar_w) : (col += 1) {
                    const ch: u21 = if (col < filled) '\u{2588}' else '\u{2591}';
                    term.setCell(bar_x + col, dy + 3, .{ .char = ch, .fg = colors.selected_bg, .bg = colors.dialog_bg });
                }

                // Percentage
                var pct_buf: [8]u8 = undefined;
                const pct = std.fmt.bufPrint(&pct_buf, "{d:>3}%", .{@as(u32, @intFromFloat(self.progress * 100))}) catch "  0%";
                term.writeString(dx + dialog_w / 2 - 2, dy + 5, pct, colors.dialog_fg, colors.dialog_bg, false);

                self.drawButtons(term, dx, dy + dialog_h - 2, dialog_w, colors, &[_][]const u8{"[ Cancel ]"});
            },
            .file_conflict => {
                const msg = self.getMessage();
                const max_w = dialog_w - 4;
                const display = if (msg.len > max_w) msg[0..max_w] else msg;
                term.writeString(dx + 2, dy + 2, "File already exists:", colors.dialog_fg, colors.dialog_bg, false);
                term.writeString(dx + 2, dy + 3, display, colors.dialog_fg, colors.dialog_bg, true);

                self.drawButtons(term, dx, dy + dialog_h - 2, dialog_w, colors, &[_][]const u8{ "[O]verwrite", "[S]kip", "[R]ename", "Over[A]ll" });
            },
        }
    }

    fn drawButtons(self: *const Dialog, term: *term_mod.Terminal, dx: u16, by: u16, dialog_w: u16, colors: theme_mod.ThemeColors, labels: []const []const u8) void {
        var total_len: usize = 0;
        for (labels) |l| total_len += l.len + 2;

        var bx: u16 = dx + (dialog_w - @as(u16, @intCast(total_len))) / 2;
        for (labels, 0..) |label, i| {
            const is_sel = i == self.selected_button;
            const fg = if (is_sel) colors.dialog_bg else colors.dialog_fg;
            const bg = if (is_sel) colors.dialog_title_fg else colors.dialog_bg;
            term.writeString(bx, by, label, fg, bg, is_sel);
            bx += @intCast(label.len + 2);
        }
    }
};

fn drawDialogBorder(term: *term_mod.Terminal, x: u16, y: u16, w: u16, h: u16, colors: theme_mod.ThemeColors) void {
    // Corners
    term.setCell(x, y, .{ .char = '\u{2554}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
    term.setCell(x + w - 1, y, .{ .char = '\u{2557}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
    term.setCell(x, y + h - 1, .{ .char = '\u{255A}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
    term.setCell(x + w - 1, y + h - 1, .{ .char = '\u{255D}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });

    // Horizontal
    var col: u16 = 1;
    while (col < w - 1) : (col += 1) {
        term.setCell(x + col, y, .{ .char = '\u{2550}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
        term.setCell(x + col, y + h - 1, .{ .char = '\u{2550}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
    }

    // Vertical
    var r: u16 = 1;
    while (r < h - 1) : (r += 1) {
        term.setCell(x, y + r, .{ .char = '\u{2551}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
        term.setCell(x + w - 1, y + r, .{ .char = '\u{2551}', .fg = colors.dialog_title_fg, .bg = colors.dialog_bg });
    }
}

test "Dialog initConfirm" {
    const d = Dialog.initConfirm("Test", "Are you sure?");
    try std.testing.expectEqualStrings("Test", d.getTitle());
    try std.testing.expectEqualStrings("Are you sure?", d.getMessage());
    try std.testing.expectEqual(DialogKind.confirm, d.kind);
}

test "Dialog input handling" {
    var d = Dialog.initInput("Name", "");
    d.handleChar('h');
    d.handleChar('i');
    try std.testing.expectEqualStrings("hi", d.getInput());
    d.handleBackspace();
    try std.testing.expectEqualStrings("h", d.getInput());
}

test "Dialog button navigation" {
    var d = Dialog.initConfirm("Test", "msg");
    try std.testing.expectEqual(@as(u8, 0), d.selected_button);
    d.nextButton();
    try std.testing.expectEqual(@as(u8, 1), d.selected_button);
    d.nextButton();
    try std.testing.expectEqual(@as(u8, 0), d.selected_button); // wraps
}
