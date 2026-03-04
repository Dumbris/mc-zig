const std = @import("std");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");
const markdown = @import("markdown.zig");
const html = @import("html.zig");
const hex = @import("hex.zig");

pub const ViewMode = enum {
    text,
    hex_mode,
    markdown_readable,
    html_readable,
};

pub const Viewer = struct {
    file_path: [std.fs.max_path_bytes]u8 = undefined,
    file_path_len: usize = 0,
    content: []u8 = &.{},
    scroll_line: usize = 0,
    total_lines: usize = 0,
    mode: ViewMode = .text,
    is_markdown: bool = false,
    is_html: bool = false,
    is_binary: bool = false,
    allocator: std.mem.Allocator,
    // Cached rendered lines for readability modes
    styled_lines: []markdown.StyledLine = &.{},
    // Backing text buffer for HTML rendered lines (must outlive styled_lines)
    html_backing_text: []u8 = &.{},

    pub fn init(allocator: std.mem.Allocator) Viewer {
        return Viewer{ .allocator = allocator };
    }

    pub fn deinit(self: *Viewer) void {
        if (self.content.len > 0) self.allocator.free(self.content);
        if (self.styled_lines.len > 0) self.allocator.free(self.styled_lines);
        if (self.html_backing_text.len > 0) self.allocator.free(self.html_backing_text);
        self.content = &.{};
        self.styled_lines = &.{};
        self.html_backing_text = &.{};
    }

    pub fn getFilePath(self: *const Viewer) []const u8 {
        return self.file_path[0..self.file_path_len];
    }

    pub fn open(self: *Viewer, path: []const u8) !void {
        self.deinit();

        const len = @min(path.len, self.file_path.len);
        @memcpy(self.file_path[0..len], path[0..len]);
        self.file_path_len = len;

        // Detect file type from extension
        self.is_markdown = endsWithLower(path, ".md");
        self.is_html = endsWithLower(path, ".html") or endsWithLower(path, ".htm");

        // Read file
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const stat = try file.stat();
        const max_size: u64 = 10 * 1024 * 1024; // 10MB limit for viewer
        const read_size = @min(stat.size, max_size);

        self.content = try self.allocator.alloc(u8, @intCast(read_size));
        const n = try file.readAll(self.content);
        if (n < self.content.len) {
            self.content = self.allocator.realloc(self.content, n) catch self.content;
        }

        // Detect binary
        self.is_binary = isBinary(self.content);

        // Set initial mode
        if (self.is_binary) {
            self.mode = .hex_mode;
        } else if (self.is_markdown) {
            self.mode = .markdown_readable;
        } else if (self.is_html) {
            self.mode = .html_readable;
        } else {
            self.mode = .text;
        }

        self.scroll_line = 0;
        try self.updateLineCount();
    }

    fn updateLineCount(self: *Viewer) !void {
        // Free old styled lines
        if (self.styled_lines.len > 0) {
            self.allocator.free(self.styled_lines);
            self.styled_lines = &.{};
        }
        if (self.html_backing_text.len > 0) {
            self.allocator.free(self.html_backing_text);
            self.html_backing_text = &.{};
        }

        switch (self.mode) {
            .text => {
                self.total_lines = countLines(self.content);
            },
            .hex_mode => {
                self.total_lines = hex.getLineCount(self.content.len);
            },
            .markdown_readable => {
                self.styled_lines = markdown.renderMarkdown(self.allocator, self.content) catch &.{};
                self.total_lines = self.styled_lines.len;
            },
            .html_readable => {
                const result = html.renderHtml(self.allocator, self.content) catch {
                    self.styled_lines = &.{};
                    self.total_lines = 0;
                    return;
                };
                self.styled_lines = result.lines;
                self.html_backing_text = result.backing_text;
                self.total_lines = self.styled_lines.len;
            },
        }
    }

    pub fn toggleReadability(self: *Viewer) !void {
        if (self.is_markdown) {
            self.mode = if (self.mode == .text) .markdown_readable else .text;
        } else if (self.is_html) {
            self.mode = if (self.mode == .text) .html_readable else .text;
        }
        self.scroll_line = 0;
        try self.updateLineCount();
    }

    pub fn toggleHex(self: *Viewer) !void {
        self.mode = if (self.mode == .hex_mode) .text else .hex_mode;
        self.scroll_line = 0;
        try self.updateLineCount();
    }

    pub fn scrollUp(self: *Viewer) void {
        if (self.scroll_line > 0) self.scroll_line -= 1;
    }

    pub fn scrollDown(self: *Viewer, visible_rows: usize) void {
        if (self.total_lines > visible_rows and self.scroll_line < self.total_lines - visible_rows) {
            self.scroll_line += 1;
        }
    }

    pub fn pageUp(self: *Viewer, visible_rows: usize) void {
        if (self.scroll_line > visible_rows) {
            self.scroll_line -= visible_rows;
        } else {
            self.scroll_line = 0;
        }
    }

    pub fn pageDown(self: *Viewer, visible_rows: usize) void {
        self.scroll_line += visible_rows;
        if (self.total_lines > visible_rows and self.scroll_line > self.total_lines - visible_rows) {
            self.scroll_line = self.total_lines - visible_rows;
        }
    }

    pub fn goHome(self: *Viewer) void {
        self.scroll_line = 0;
    }

    pub fn goEnd(self: *Viewer, visible_rows: usize) void {
        if (self.total_lines > visible_rows) {
            self.scroll_line = self.total_lines - visible_rows;
        }
    }

    pub fn render(self: *Viewer, term: *term_mod.Terminal, colors: theme_mod.ThemeColors) void {
        const width = term.width;
        const height = term.height;
        if (height < 3) return;

        const content_height = height - 2; // status bar at bottom

        // Title bar
        term.fillRow(0, colors.status_fg, colors.status_bg);
        const path = self.getFilePath();
        const max_path = if (width > 20) width - 20 else 1;
        const display_path = if (path.len > max_path) path[path.len - max_path ..] else path;
        term.writeString(1, 0, display_path, colors.status_fg, colors.status_bg, true);

        // Mode indicator
        const mode_str: []const u8 = switch (self.mode) {
            .text => " [Text] ",
            .hex_mode => " [Hex] ",
            .markdown_readable => " [Markdown] ",
            .html_readable => " [HTML] ",
        };
        if (width > mode_str.len + 2) {
            term.writeString(width - @as(u16, @intCast(mode_str.len)) - 1, 0, mode_str, colors.status_fg, colors.status_bg, false);
        }

        // Content area
        switch (self.mode) {
            .text => self.renderText(term, 1, content_height, colors),
            .hex_mode => self.renderHex(term, 1, content_height, colors),
            .markdown_readable, .html_readable => self.renderStyled(term, 1, content_height, colors),
        }

        // Bottom status bar
        const status_y = height - 1;
        term.fillRow(status_y, colors.status_fg, colors.status_bg);

        var pos_buf: [32]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&pos_buf, " Line {d}/{d} ", .{ self.scroll_line + 1, self.total_lines }) catch " 0/0 ";
        term.writeString(1, status_y, pos_str, colors.status_fg, colors.status_bg, false);

        // Keys hint
        const hint: []const u8 = if (self.is_markdown or self.is_html)
            "F2:Toggle  F4:Hex  Q:Close"
        else
            "F4:Hex  Q:Close";
        if (width > hint.len + 2) {
            term.writeString(width - @as(u16, @intCast(hint.len)) - 1, status_y, hint, colors.status_fg, colors.status_bg, false);
        }
    }

    fn renderText(self: *Viewer, term: *term_mod.Terminal, start_y: u16, rows: u16, colors: theme_mod.ThemeColors) void {
        var lines = std.mem.splitScalar(u8, self.content, '\n');
        var line_num: usize = 0;

        // Skip to scroll offset
        while (line_num < self.scroll_line) {
            _ = lines.next();
            line_num += 1;
        }

        var row: u16 = 0;
        while (row < rows) : (row += 1) {
            const y = start_y + row;
            term.fillRow(y, colors.panel_fg, colors.panel_bg);

            if (lines.next()) |line| {
                const display = if (line.len > term.width) line[0..term.width] else line;
                term.writeString(0, y, display, colors.panel_fg, colors.panel_bg, false);
            }
        }
    }

    fn renderHex(self: *Viewer, term: *term_mod.Terminal, start_y: u16, rows: u16, colors: theme_mod.ThemeColors) void {
        var row: u16 = 0;
        while (row < rows) : (row += 1) {
            const line_idx = self.scroll_line + row;
            const offset = line_idx * 16;
            const y = start_y + row;

            if (offset >= self.content.len) {
                term.fillRow(y, colors.panel_fg, colors.panel_bg);
                continue;
            }

            const end = @min(offset + 16, self.content.len);
            hex.renderHexLine(term, y, term.width, offset, self.content[offset..end], colors.panel_fg, colors.panel_bg);
        }
    }

    fn renderStyled(self: *Viewer, term: *term_mod.Terminal, start_y: u16, rows: u16, colors: theme_mod.ThemeColors) void {
        var row: u16 = 0;
        while (row < rows) : (row += 1) {
            const line_idx = self.scroll_line + row;
            const y = start_y + row;

            if (line_idx >= self.styled_lines.len) {
                term.fillRow(y, colors.panel_fg, colors.panel_bg);
                continue;
            }

            markdown.renderStyledLine(term, y, term.width, self.styled_lines[line_idx], colors.panel_fg, colors.panel_bg);
        }
    }
};

fn isBinary(content: []const u8) bool {
    const check_len = @min(content.len, 8192);
    var null_count: usize = 0;
    for (content[0..check_len]) |b| {
        if (b == 0) null_count += 1;
    }
    return null_count > check_len / 10;
}

fn countLines(content: []const u8) usize {
    if (content.len == 0) return 0;
    var count: usize = 1;
    for (content) |ch| {
        if (ch == '\n') count += 1;
    }
    return count;
}

fn endsWithLower(str: []const u8, suffix: []const u8) bool {
    if (str.len < suffix.len) return false;
    const end = str[str.len - suffix.len ..];
    for (end, suffix) |a, b| {
        if (std.ascii.toLower(a) != b) return false;
    }
    return true;
}

test "countLines" {
    try std.testing.expectEqual(@as(usize, 0), countLines(""));
    try std.testing.expectEqual(@as(usize, 1), countLines("hello"));
    try std.testing.expectEqual(@as(usize, 3), countLines("a\nb\nc"));
}

test "isBinary" {
    try std.testing.expect(!isBinary("hello world"));
    const binary = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expect(isBinary(&binary));
}

test "endsWithLower" {
    try std.testing.expect(endsWithLower("file.MD", ".md"));
    try std.testing.expect(endsWithLower("page.HTML", ".html"));
    try std.testing.expect(!endsWithLower("file.txt", ".md"));
}
