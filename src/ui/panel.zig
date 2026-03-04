const std = @import("std");
const dir_mod = @import("../fs/dir.zig");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");

pub const Panel = struct {
    path: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    entries: []dir_mod.DirEntry = &.{},
    cursor: usize = 0,
    scroll_offset: usize = 0,
    tagged: [4096]bool = [_]bool{false} ** 4096,
    tagged_count: usize = 0,
    sort_mode: dir_mod.SortMode = .name,
    sort_ascending: bool = true,
    allocator: std.mem.Allocator,
    is_active: bool = false,

    pub fn init(allocator: std.mem.Allocator) Panel {
        return Panel{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Panel) void {
        if (self.entries.len > 0) {
            self.allocator.free(self.entries);
            self.entries = &.{};
        }
    }

    pub fn getPath(self: *const Panel) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn setPath(self: *Panel, p: []const u8) void {
        const len = @min(p.len, self.path.len);
        // Use a temp buffer to handle the case where p is a slice of self.path
        var tmp: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(tmp[0..len], p[0..len]);
        @memcpy(self.path[0..len], tmp[0..len]);
        self.path_len = len;
    }

    pub fn loadDirectory(self: *Panel, show_hidden: bool) !void {
        if (self.entries.len > 0) {
            self.allocator.free(self.entries);
        }

        self.entries = try dir_mod.listDirectory(self.allocator, self.getPath(), show_hidden);
        dir_mod.sortEntries(self.entries, self.sort_mode, self.sort_ascending);

        // Reset tagged
        for (&self.tagged) |*t| t.* = false;
        self.tagged_count = 0;

        // Clamp cursor
        if (self.entries.len == 0) {
            self.cursor = 0;
            self.scroll_offset = 0;
        } else if (self.cursor >= self.entries.len) {
            self.cursor = self.entries.len - 1;
        }
    }

    pub fn navigate(self: *Panel, show_hidden: bool) !void {
        if (self.entries.len == 0) return;

        const entry = &self.entries[self.cursor];
        if (entry.kind != .directory) return;

        const entry_name = entry.getName();

        if (std.mem.eql(u8, entry_name, "..")) {
            // Go to parent
            const current = self.getPath();
            if (std.mem.lastIndexOfScalar(u8, current, '/')) |last_slash| {
                if (last_slash == 0) {
                    self.setPath("/");
                } else {
                    self.setPath(current[0..last_slash]);
                }
            }
        } else {
            // Enter subdirectory
            var new_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const current = self.getPath();
            const new_path = if (current.len == 1 and current[0] == '/')
                std.fmt.bufPrint(&new_path_buf, "/{s}", .{entry_name}) catch return
            else
                std.fmt.bufPrint(&new_path_buf, "{s}/{s}", .{ current, entry_name }) catch return;
            self.setPath(new_path);
        }

        self.cursor = 0;
        self.scroll_offset = 0;
        try self.loadDirectory(show_hidden);
    }

    pub fn cursorUp(self: *Panel) void {
        if (self.cursor > 0) self.cursor -= 1;
    }

    pub fn cursorDown(self: *Panel) void {
        if (self.entries.len > 0 and self.cursor < self.entries.len - 1) {
            self.cursor += 1;
        }
    }

    pub fn pageUp(self: *Panel, visible_rows: usize) void {
        if (self.cursor > visible_rows) {
            self.cursor -= visible_rows;
        } else {
            self.cursor = 0;
        }
    }

    pub fn pageDown(self: *Panel, visible_rows: usize) void {
        if (self.entries.len == 0) return;
        self.cursor += visible_rows;
        if (self.cursor >= self.entries.len) {
            self.cursor = self.entries.len - 1;
        }
    }

    pub fn goHome(self: *Panel) void {
        self.cursor = 0;
    }

    pub fn goEnd(self: *Panel) void {
        if (self.entries.len > 0) {
            self.cursor = self.entries.len - 1;
        }
    }

    pub fn toggleTag(self: *Panel) void {
        if (self.entries.len == 0) return;
        if (self.cursor >= self.tagged.len) return;
        // Don't tag ".."
        const name = self.entries[self.cursor].getName();
        if (std.mem.eql(u8, name, "..")) return;

        self.tagged[self.cursor] = !self.tagged[self.cursor];
        if (self.tagged[self.cursor]) {
            self.tagged_count += 1;
        } else {
            if (self.tagged_count > 0) self.tagged_count -= 1;
        }
        self.cursorDown();
    }

    pub fn clearTags(self: *Panel) void {
        for (&self.tagged) |*t| t.* = false;
        self.tagged_count = 0;
    }

    pub fn getTaggedPaths(self: *Panel, allocator: std.mem.Allocator) ![][]u8 {
        var paths = std.ArrayList([]u8){};
        errdefer {
            for (paths.items) |p| allocator.free(p);
            paths.deinit(allocator);
        }

        if (self.tagged_count == 0) {
            // Just the current file
            if (self.entries.len == 0) return paths.toOwnedSlice(allocator);
            const name = self.entries[self.cursor].getName();
            if (std.mem.eql(u8, name, "..")) return paths.toOwnedSlice(allocator);
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ self.getPath(), name }) catch return paths.toOwnedSlice(allocator);
            const p = try allocator.dupe(u8, full);
            try paths.append(allocator, p);
        } else {
            for (self.entries, 0..) |entry, i| {
                if (i < self.tagged.len and self.tagged[i]) {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ self.getPath(), entry.getName() }) catch continue;
                    const p = try allocator.dupe(u8, full);
                    try paths.append(allocator, p);
                }
            }
        }

        return paths.toOwnedSlice(allocator);
    }

    pub fn adjustScroll(self: *Panel, visible_rows: usize) void {
        if (visible_rows == 0) return;
        if (self.cursor < self.scroll_offset) {
            self.scroll_offset = self.cursor;
        } else if (self.cursor >= self.scroll_offset + visible_rows) {
            self.scroll_offset = self.cursor - visible_rows + 1;
        }
    }

    pub fn getCurrentEntry(self: *const Panel) ?*const dir_mod.DirEntry {
        if (self.entries.len == 0 or self.cursor >= self.entries.len) return null;
        return &self.entries[self.cursor];
    }

    pub fn getCurrentName(self: *const Panel) []const u8 {
        if (self.getCurrentEntry()) |e| return e.getName();
        return "";
    }

    pub fn render(self: *Panel, term: *term_mod.Terminal, x: u16, y: u16, width: u16, height: u16, colors: theme_mod.ThemeColors) void {
        if (width < 4 or height < 3) return;

        const inner_w = width - 2;
        const list_h: u16 = if (height > 2) height - 2 else 1;

        self.adjustScroll(list_h);

        // Draw top border with path
        self.drawBorder(term, x, y, width, colors);

        // Draw entries
        var row: u16 = 0;
        while (row < list_h) : (row += 1) {
            const entry_idx = self.scroll_offset + row;
            const screen_y = y + 1 + row;

            // Fill row with background
            var col: u16 = 0;
            while (col < width) : (col += 1) {
                term.setCell(x + col, screen_y, .{ .char = ' ', .fg = colors.panel_fg, .bg = colors.panel_bg });
            }

            if (entry_idx >= self.entries.len) continue;

            const entry = &self.entries[entry_idx];
            const is_selected = entry_idx == self.cursor and self.is_active;
            const is_tagged = entry_idx < self.tagged.len and self.tagged[entry_idx];

            var fg = colors.panel_fg;
            var bg = colors.panel_bg;
            var bold = false;

            if (is_selected) {
                fg = colors.selected_fg;
                bg = colors.selected_bg;
                bold = true;
            } else if (is_tagged) {
                fg = colors.tagged_fg;
            } else {
                switch (entry.kind) {
                    .directory => {
                        fg = colors.dir_fg;
                        bold = true;
                    },
                    .symlink => fg = colors.link_fg,
                    .file => {
                        if (entry.is_executable) fg = colors.exec_fg;
                    },
                    .other => {},
                }
            }

            // Border left
            term.setCell(x, screen_y, .{ .char = '\u{2502}', .fg = colors.border_fg, .bg = colors.panel_bg });

            // Entry name
            const name = entry.getName();
            const name_area = if (inner_w > 14) inner_w - 14 else 1;
            self.drawEntryName(term, x + 1, screen_y, name_area, name, entry.kind, fg, bg, bold);

            // Size column
            if (inner_w > 14) {
                const size_x = x + 1 + name_area + 1;
                if (entry.kind == .directory) {
                    term.writeString(size_x, screen_y, "  <DIR>", fg, bg, bold);
                } else {
                    const size_str = dir_mod.formatSize(entry.size);
                    term.writeString(size_x, screen_y, &size_str, fg, bg, false);
                }
            }

            // Border right
            term.setCell(x + width - 1, screen_y, .{ .char = '\u{2502}', .fg = colors.border_fg, .bg = colors.panel_bg });
        }

        // Bottom border
        self.drawBottomBorder(term, x, y + height - 1, width, colors);
    }

    fn drawEntryName(self: *const Panel, term: *term_mod.Terminal, x: u16, y: u16, max_width: u16, name: []const u8, kind: dir_mod.EntryKind, fg: theme_mod.Color, bg: theme_mod.Color, bold: bool) void {
        _ = self;
        const display_name = if (name.len > max_width and max_width > 3)
            name[0 .. max_width - 1] // truncate
        else
            name;

        term.writeString(x, y, display_name, fg, bg, bold);

        if (name.len > max_width and max_width > 3) {
            term.setCell(x + max_width - 1, y, .{ .char = '~', .fg = fg, .bg = bg });
        }

        // Dir indicator
        if (kind == .directory and display_name.len < max_width) {
            term.setCell(x + @as(u16, @intCast(display_name.len)), y, .{ .char = '/', .fg = fg, .bg = bg, .bold = bold });
        }
    }

    fn drawBorder(self: *const Panel, term: *term_mod.Terminal, x: u16, y: u16, width: u16, colors: theme_mod.ThemeColors) void {
        // Top-left corner
        term.setCell(x, y, .{ .char = '\u{250C}', .fg = colors.border_fg, .bg = colors.panel_bg });

        // Top line
        var col: u16 = 1;
        while (col < width - 1) : (col += 1) {
            term.setCell(x + col, y, .{ .char = '\u{2500}', .fg = colors.border_fg, .bg = colors.panel_bg });
        }

        // Top-right corner
        term.setCell(x + width - 1, y, .{ .char = '\u{2510}', .fg = colors.border_fg, .bg = colors.panel_bg });

        // Path title in top border
        const path = self.getPath();
        const max_title = if (width > 6) width - 6 else 1;
        const title = if (path.len > max_title) path[path.len - max_title ..] else path;
        const title_x = x + 2;
        term.setCell(title_x - 1, y, .{ .char = ' ', .fg = colors.border_fg, .bg = colors.panel_bg });
        term.writeString(title_x, y, title, if (self.is_active) colors.selected_bg else colors.border_fg, colors.panel_bg, self.is_active);
        if (title.len < max_title) {
            term.setCell(title_x + @as(u16, @intCast(title.len)), y, .{ .char = ' ', .fg = colors.border_fg, .bg = colors.panel_bg });
        }
    }

    fn drawBottomBorder(self: *const Panel, term: *term_mod.Terminal, x: u16, y: u16, width: u16, colors: theme_mod.ThemeColors) void {
        term.setCell(x, y, .{ .char = '\u{2514}', .fg = colors.border_fg, .bg = colors.panel_bg });
        var col: u16 = 1;
        while (col < width - 1) : (col += 1) {
            term.setCell(x + col, y, .{ .char = '\u{2500}', .fg = colors.border_fg, .bg = colors.panel_bg });
        }
        term.setCell(x + width - 1, y, .{ .char = '\u{2518}', .fg = colors.border_fg, .bg = colors.panel_bg });

        // Tagged count or entry info
        if (self.tagged_count > 0) {
            var buf: [32]u8 = undefined;
            const info = std.fmt.bufPrint(&buf, " {d} tagged ", .{self.tagged_count}) catch return;
            if (info.len + 2 < width) {
                term.writeString(x + 2, y, info, colors.tagged_fg, colors.panel_bg, false);
            }
        }
    }

    pub fn quickSearch(self: *Panel, query: []const u8) bool {
        return self.quickSearchFrom(query, self.cursor);
    }

    pub fn quickSearchNext(self: *Panel, query: []const u8) bool {
        if (self.entries.len == 0) return false;
        const start = if (self.cursor + 1 < self.entries.len) self.cursor + 1 else 0;
        return self.quickSearchFrom(query, start);
    }

    fn quickSearchFrom(self: *Panel, query: []const u8, start: usize) bool {
        if (query.len == 0 or self.entries.len == 0) return false;

        var i = start;
        var checked: usize = 0;
        while (checked < self.entries.len) {
            const name = self.entries[i].getName();
            if (startsWithCaseInsensitive(name, query)) {
                self.cursor = i;
                return true;
            }
            i = if (i + 1 < self.entries.len) i + 1 else 0;
            checked += 1;
        }
        return false;
    }

    fn startsWithCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        for (needle, 0..) |nc, i| {
            if (std.ascii.toLower(nc) != std.ascii.toLower(haystack[i])) return false;
        }
        return true;
    }
};

test "Panel cursor movement" {
    var panel = Panel.init(std.testing.allocator);
    defer panel.deinit();
    panel.setPath("/tmp");
    try panel.loadDirectory(false);

    panel.cursor = 0;
    panel.cursorDown();
    if (panel.entries.len > 1) {
        try std.testing.expectEqual(@as(usize, 1), panel.cursor);
    }
    panel.cursorUp();
    try std.testing.expectEqual(@as(usize, 0), panel.cursor);
    // Should not go below 0
    panel.cursorUp();
    try std.testing.expectEqual(@as(usize, 0), panel.cursor);
}

test "Panel home and end" {
    var panel = Panel.init(std.testing.allocator);
    defer panel.deinit();
    panel.setPath("/tmp");
    try panel.loadDirectory(false);

    panel.goEnd();
    if (panel.entries.len > 0) {
        try std.testing.expectEqual(panel.entries.len - 1, panel.cursor);
    }
    panel.goHome();
    try std.testing.expectEqual(@as(usize, 0), panel.cursor);
}
