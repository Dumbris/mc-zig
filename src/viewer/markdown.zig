const std = @import("std");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");

pub const StyledLine = struct {
    text: []const u8,
    bold: bool = false,
    dim: bool = false,
    underline: bool = false,
    fg_override: ?theme_mod.Color = null,
    indent: u16 = 0,
};

pub fn renderMarkdown(
    allocator: std.mem.Allocator,
    content: []const u8,
) ![]StyledLine {
    var lines = std.ArrayList(StyledLine){};
    errdefer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, content, '\n');
    var in_code_block = false;

    while (iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "```")) {
            in_code_block = !in_code_block;
            try lines.append(allocator, .{ .text = line, .dim = true, .fg_override = 242 });
            continue;
        }

        if (in_code_block) {
            try lines.append(allocator, .{ .text = line, .dim = true, .indent = 2, .fg_override = 242 });
            continue;
        }

        // Headers
        if (std.mem.startsWith(u8, line, "### ")) {
            try lines.append(allocator, .{ .text = line[4..], .bold = true, .fg_override = 214 });
        } else if (std.mem.startsWith(u8, line, "## ")) {
            try lines.append(allocator, .{ .text = line[3..], .bold = true, .fg_override = 208 });
        } else if (std.mem.startsWith(u8, line, "# ")) {
            try lines.append(allocator, .{ .text = line[2..], .bold = true, .fg_override = 196 });
        }
        // Unordered list
        else if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ")) {
            try lines.append(allocator, .{ .text = line, .indent = 1, .fg_override = 114 });
        }
        // Ordered list
        else if (line.len > 2 and std.ascii.isDigit(line[0]) and line[1] == '.') {
            try lines.append(allocator, .{ .text = line, .indent = 1, .fg_override = 114 });
        }
        // Blockquote
        else if (std.mem.startsWith(u8, line, "> ")) {
            try lines.append(allocator, .{ .text = line[2..], .dim = true, .indent = 2, .fg_override = 245 });
        }
        // Horizontal rule
        else if (std.mem.startsWith(u8, line, "---") or std.mem.startsWith(u8, line, "***")) {
            try lines.append(allocator, .{ .text = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}", .dim = true });
        }
        // Empty line
        else if (line.len == 0) {
            try lines.append(allocator, .{ .text = "" });
        }
        // Regular text
        else {
            try lines.append(allocator, .{ .text = line });
        }
    }

    return lines.toOwnedSlice(allocator);
}

pub fn renderStyledLine(
    term: *term_mod.Terminal,
    y: u16,
    width: u16,
    sline: StyledLine,
    default_fg: theme_mod.Color,
    bg: theme_mod.Color,
) void {
    // Clear row
    var x: u16 = 0;
    while (x < width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = default_fg, .bg = bg });
    }

    const fg = sline.fg_override orelse default_fg;
    const start_x = sline.indent * 2;
    var col: u16 = start_x;

    // Render inline formatting
    var i: usize = 0;
    const text = sline.text;
    var current_bold = sline.bold;
    var current_underline = sline.underline;

    while (i < text.len and col < width) {
        // Check for bold markers **
        if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
            current_bold = !current_bold;
            i += 2;
            continue;
        }
        // Check for italic/underline marker *
        if (text[i] == '*' and (i == 0 or text[i - 1] != '*') and (i + 1 >= text.len or text[i + 1] != '*')) {
            current_underline = !current_underline;
            i += 1;
            continue;
        }
        // Check for inline code `
        if (text[i] == '`') {
            i += 1;
            // Render until next backtick
            while (i < text.len and text[i] != '`' and col < width) {
                term.setCell(col, y, .{ .char = text[i], .fg = 242, .bg = bg, .dim = true });
                col += 1;
                i += 1;
            }
            if (i < text.len) i += 1; // skip closing backtick
            continue;
        }

        term.setCell(col, y, .{
            .char = text[i],
            .fg = fg,
            .bg = bg,
            .bold = current_bold,
            .underline = current_underline,
            .dim = sline.dim,
        });
        col += 1;
        i += 1;
    }
}

test "renderMarkdown headers" {
    const content = "# Title\n## Subtitle\nNormal text";
    const lines = try renderMarkdown(std.testing.allocator, content);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("Title", lines[0].text);
    try std.testing.expect(lines[0].bold);
    try std.testing.expectEqualStrings("Subtitle", lines[1].text);
    try std.testing.expect(lines[1].bold);
    try std.testing.expectEqualStrings("Normal text", lines[2].text);
    try std.testing.expect(!lines[2].bold);
}

test "renderMarkdown code block" {
    const content = "```\ncode here\n```";
    const lines = try renderMarkdown(std.testing.allocator, content);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expect(lines[1].dim);
}

test "renderMarkdown lists" {
    const content = "- item 1\n- item 2";
    const lines = try renderMarkdown(std.testing.allocator, content);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqual(@as(u16, 1), lines[0].indent);
}
