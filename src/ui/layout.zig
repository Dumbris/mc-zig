const std = @import("std");

pub const Layout = struct {
    term_width: u16,
    term_height: u16,

    // Menu bar
    menu_row: u16 = 0,

    // Panel area
    panel_top: u16 = 1,
    panel_height: u16 = 0,
    left_panel_x: u16 = 0,
    left_panel_width: u16 = 0,
    right_panel_x: u16 = 0,
    right_panel_width: u16 = 0,

    // Bottom area
    hint_row: u16 = 0,
    command_row: u16 = 0,
    fkey_row: u16 = 0,

    pub fn calculate(width: u16, height: u16) Layout {
        var l = Layout{
            .term_width = width,
            .term_height = height,
        };

        // Row allocation:
        // Row 0: menu bar
        // Rows 1..height-3: panels
        // Row height-3: hint line
        // Row height-2: command line
        // Row height-1: function key bar
        l.menu_row = 0;
        l.panel_top = 1;

        if (height > 4) {
            l.panel_height = height - 4;
        } else {
            l.panel_height = 1;
        }

        l.hint_row = l.panel_top + l.panel_height;
        l.command_row = l.hint_row + 1;
        l.fkey_row = if (height > 0) height - 1 else 0;

        // Panel width: split evenly
        l.left_panel_x = 0;
        l.left_panel_width = width / 2;
        l.right_panel_x = l.left_panel_width;
        l.right_panel_width = width - l.left_panel_width;

        return l;
    }

    pub fn panelListingHeight(self: *const Layout) u16 {
        // Panel height minus 2 (top border + header row)
        if (self.panel_height > 2) return self.panel_height - 2;
        return 1;
    }
};

test "calculate basic layout" {
    const l = Layout.calculate(80, 24);
    try std.testing.expectEqual(@as(u16, 0), l.menu_row);
    try std.testing.expectEqual(@as(u16, 1), l.panel_top);
    try std.testing.expectEqual(@as(u16, 20), l.panel_height);
    try std.testing.expectEqual(@as(u16, 21), l.hint_row);
    try std.testing.expectEqual(@as(u16, 22), l.command_row);
    try std.testing.expectEqual(@as(u16, 23), l.fkey_row);
    try std.testing.expectEqual(@as(u16, 40), l.left_panel_width);
    try std.testing.expectEqual(@as(u16, 40), l.right_panel_width);
}

test "calculate small terminal" {
    const l = Layout.calculate(40, 10);
    try std.testing.expectEqual(@as(u16, 6), l.panel_height);
    try std.testing.expectEqual(@as(u16, 20), l.left_panel_width);
}
