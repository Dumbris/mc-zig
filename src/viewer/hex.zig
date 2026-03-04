const std = @import("std");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");

pub fn renderHexLine(
    term: *term_mod.Terminal,
    y: u16,
    width: u16,
    offset: usize,
    data: []const u8,
    fg: theme_mod.Color,
    bg: theme_mod.Color,
) void {
    // Clear line
    var x: u16 = 0;
    while (x < width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = fg, .bg = bg });
    }

    // Offset column (8 hex digits)
    var offset_buf: [10]u8 = undefined;
    const offset_str = std.fmt.bufPrint(&offset_buf, "{X:0>8} ", .{offset}) catch return;
    term.writeString(0, y, offset_str, 242, bg, false);

    // Hex bytes
    const hex_start: u16 = 10;
    var col: u16 = hex_start;
    for (data, 0..) |byte, i| {
        if (i == 8) {
            term.setCell(col, y, .{ .char = ' ', .fg = fg, .bg = bg });
            col += 1;
        }
        var hex_buf: [3]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{X:0>2}", .{byte}) catch continue;
        if (col + 2 < width) {
            term.setCell(col, y, .{ .char = hex_buf[0], .fg = fg, .bg = bg });
            term.setCell(col + 1, y, .{ .char = hex_buf[1], .fg = fg, .bg = bg });
            term.setCell(col + 2, y, .{ .char = ' ', .fg = fg, .bg = bg });
        }
        col += 3;
    }

    // Pad remaining hex area
    const expected_cols: u16 = hex_start + 16 * 3 + 1;
    while (col < expected_cols and col < width) : (col += 1) {
        term.setCell(col, y, .{ .char = ' ', .fg = fg, .bg = bg });
    }

    // ASCII column
    const ascii_start = expected_cols + 1;
    if (ascii_start < width) {
        term.setCell(ascii_start - 1, y, .{ .char = '\u{2502}', .fg = 242, .bg = bg });
    }
    for (data, 0..) |byte, i| {
        const ax = ascii_start + @as(u16, @intCast(i));
        if (ax >= width) break;
        const ch: u21 = if (byte >= 0x20 and byte < 0x7f) byte else '.';
        term.setCell(ax, y, .{ .char = ch, .fg = fg, .bg = bg });
    }
}

pub fn getLineCount(content_len: usize) usize {
    return (content_len + 15) / 16;
}

test "getLineCount" {
    try std.testing.expectEqual(@as(usize, 0), getLineCount(0));
    try std.testing.expectEqual(@as(usize, 1), getLineCount(1));
    try std.testing.expectEqual(@as(usize, 1), getLineCount(16));
    try std.testing.expectEqual(@as(usize, 2), getLineCount(17));
    try std.testing.expectEqual(@as(usize, 4), getLineCount(64));
}
