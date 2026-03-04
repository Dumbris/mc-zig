const std = @import("std");
const term_mod = @import("../terminal.zig");
const theme_mod = @import("../config/theme.zig");

const FKeyLabel = struct {
    num: []const u8,
    label: []const u8,
};

const fkey_labels = [_]FKeyLabel{
    .{ .num = "1", .label = "Help" },
    .{ .num = "2", .label = "Menu" },
    .{ .num = "3", .label = "View" },
    .{ .num = "4", .label = "Edit" },
    .{ .num = "5", .label = "Copy" },
    .{ .num = "6", .label = "Move" },
    .{ .num = "7", .label = "Mkdir" },
    .{ .num = "8", .label = "Del" },
    .{ .num = "9", .label = "Menu" },
    .{ .num = "10", .label = "Quit" },
};

pub fn renderFKeyBar(term: *term_mod.Terminal, y: u16, colors: theme_mod.ThemeColors) void {
    // Fill row
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.status_fg, .bg = colors.status_bg });
    }

    const item_width = term.width / 10;
    for (&fkey_labels, 0..) |fk, i| {
        const bx: u16 = @intCast(i * item_width);
        if (bx >= term.width) break;

        // Number part (bright)
        term.writeString(bx, y, fk.num, colors.status_fg, colors.status_bg, true);

        // Label part
        const num_w: u16 = @intCast(fk.num.len);
        term.writeString(bx + num_w, y, fk.label, colors.panel_bg, colors.status_bg, false);
    }
}

pub fn renderHintLine(term: *term_mod.Terminal, y: u16, hint: []const u8, colors: theme_mod.ThemeColors) void {
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.hint_fg, .bg = colors.panel_bg });
    }
    const display = if (hint.len > term.width) hint[0..term.width] else hint;
    term.writeString(0, y, display, colors.hint_fg, colors.panel_bg, false);
}

pub fn renderCommandLine(term: *term_mod.Terminal, y: u16, path: []const u8, colors: theme_mod.ThemeColors) void {
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.panel_fg, .bg = 0 });
    }

    // Show current path as prompt
    const max_w = if (term.width > 3) term.width - 3 else 1;
    const display = if (path.len > max_w) path[path.len - max_w ..] else path;
    term.writeString(0, y, display, colors.panel_fg, 0, false);
    term.writeString(@intCast(display.len), y, "$ ", colors.panel_fg, 0, true);
}

pub fn renderMenuBar(term: *term_mod.Terminal, y: u16, colors: theme_mod.ThemeColors) void {
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.menu_fg, .bg = colors.menu_bg });
    }
    term.writeString(1, y, "Left", colors.menu_fg, colors.menu_bg, false);
    term.writeString(8, y, "File", colors.menu_fg, colors.menu_bg, false);
    term.writeString(15, y, "Command", colors.menu_fg, colors.menu_bg, false);
    term.writeString(25, y, "Options", colors.menu_fg, colors.menu_bg, false);
    term.writeString(35, y, "Right", colors.menu_fg, colors.menu_bg, false);
}

pub fn renderQuickSearch(term: *term_mod.Terminal, y: u16, query: []const u8, colors: theme_mod.ThemeColors) void {
    var x: u16 = 0;
    while (x < term.width) : (x += 1) {
        term.setCell(x, y, .{ .char = ' ', .fg = colors.hint_fg, .bg = colors.panel_bg });
    }
    term.writeString(0, y, "Search: ", colors.hint_fg, colors.panel_bg, true);
    if (query.len > 0) {
        const max_w = if (term.width > 10) term.width - 10 else 1;
        const display = if (query.len > max_w) query[0..max_w] else query;
        term.writeString(8, y, display, colors.selected_bg, colors.panel_bg, true);
    }
}
