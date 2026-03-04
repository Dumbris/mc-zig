const std = @import("std");

pub const Color = u8; // 256-color index

pub const ThemeColors = struct {
    panel_bg: Color = 4,
    panel_fg: Color = 15,
    selected_bg: Color = 6,
    selected_fg: Color = 0,
    dir_fg: Color = 15,
    exec_fg: Color = 10,
    link_fg: Color = 14,
    tagged_fg: Color = 11,
    menu_bg: Color = 0,
    menu_fg: Color = 11,
    status_bg: Color = 6,
    status_fg: Color = 0,
    dialog_bg: Color = 7,
    dialog_fg: Color = 0,
    dialog_title_fg: Color = 4,
    border_fg: Color = 6,
    error_fg: Color = 9,
    hint_fg: Color = 8,
};

pub const Theme = struct {
    name: []const u8,
    colors: ThemeColors,
};

pub const builtin_themes = [_]Theme{
    .{
        .name = "classic",
        .colors = .{
            .panel_bg = 4,
            .panel_fg = 15,
            .selected_bg = 6,
            .selected_fg = 0,
            .dir_fg = 15,
            .exec_fg = 10,
            .link_fg = 14,
            .tagged_fg = 11,
            .menu_bg = 0,
            .menu_fg = 11,
            .status_bg = 6,
            .status_fg = 0,
            .dialog_bg = 7,
            .dialog_fg = 0,
            .dialog_title_fg = 4,
            .border_fg = 6,
            .error_fg = 9,
            .hint_fg = 8,
        },
    },
    .{
        .name = "nord",
        .colors = .{
            .panel_bg = 236,
            .panel_fg = 253,
            .selected_bg = 4,
            .selected_fg = 15,
            .dir_fg = 110,
            .exec_fg = 108,
            .link_fg = 139,
            .tagged_fg = 215,
            .menu_bg = 235,
            .menu_fg = 110,
            .status_bg = 4,
            .status_fg = 15,
            .dialog_bg = 238,
            .dialog_fg = 253,
            .dialog_title_fg = 110,
            .border_fg = 60,
            .error_fg = 131,
            .hint_fg = 242,
        },
    },
    .{
        .name = "dracula",
        .colors = .{
            .panel_bg = 235,
            .panel_fg = 253,
            .selected_bg = 141,
            .selected_fg = 235,
            .dir_fg = 117,
            .exec_fg = 84,
            .link_fg = 212,
            .tagged_fg = 228,
            .menu_bg = 236,
            .menu_fg = 141,
            .status_bg = 61,
            .status_fg = 15,
            .dialog_bg = 237,
            .dialog_fg = 253,
            .dialog_title_fg = 141,
            .border_fg = 61,
            .error_fg = 203,
            .hint_fg = 242,
        },
    },
    .{
        .name = "solarized",
        .colors = .{
            .panel_bg = 234,
            .panel_fg = 246,
            .selected_bg = 37,
            .selected_fg = 234,
            .dir_fg = 33,
            .exec_fg = 64,
            .link_fg = 136,
            .tagged_fg = 166,
            .menu_bg = 235,
            .menu_fg = 136,
            .status_bg = 37,
            .status_fg = 234,
            .dialog_bg = 236,
            .dialog_fg = 246,
            .dialog_title_fg = 33,
            .border_fg = 37,
            .error_fg = 160,
            .hint_fg = 240,
        },
    },
    .{
        .name = "gruvbox",
        .colors = .{
            .panel_bg = 235,
            .panel_fg = 223,
            .selected_bg = 214,
            .selected_fg = 235,
            .dir_fg = 109,
            .exec_fg = 142,
            .link_fg = 175,
            .tagged_fg = 208,
            .menu_bg = 236,
            .menu_fg = 214,
            .status_bg = 172,
            .status_fg = 235,
            .dialog_bg = 237,
            .dialog_fg = 223,
            .dialog_title_fg = 214,
            .border_fg = 172,
            .error_fg = 167,
            .hint_fg = 245,
        },
    },
    .{
        .name = "dos-navigator",
        .colors = .{
            .panel_bg = 6, // Cyan — the signature DN color
            .panel_fg = 14, // Yellow text on cyan
            .selected_bg = 0, // Black cursor bar
            .selected_fg = 14, // Yellow on black
            .dir_fg = 15, // White directories (bold)
            .exec_fg = 10, // Light green executables
            .link_fg = 13, // Light magenta symlinks
            .tagged_fg = 11, // Light cyan tagged
            .menu_bg = 0, // Black menu bar
            .menu_fg = 7, // Light gray menu text
            .status_bg = 6, // Cyan status bar
            .status_fg = 0, // Black on cyan
            .dialog_bg = 7, // Light gray dialogs
            .dialog_fg = 0, // Black dialog text
            .dialog_title_fg = 4, // Blue dialog titles
            .border_fg = 15, // White borders on cyan
            .error_fg = 12, // Light red errors
            .hint_fg = 0, // Black hints on cyan
        },
    },
    .{
        .name = "mono",
        .colors = .{
            .panel_bg = 0,
            .panel_fg = 7,
            .selected_bg = 7,
            .selected_fg = 0,
            .dir_fg = 15,
            .exec_fg = 10,
            .link_fg = 14,
            .tagged_fg = 11,
            .menu_bg = 7,
            .menu_fg = 0,
            .status_bg = 7,
            .status_fg = 0,
            .dialog_bg = 7,
            .dialog_fg = 0,
            .dialog_title_fg = 0,
            .border_fg = 7,
            .error_fg = 9,
            .hint_fg = 8,
        },
    },
};

pub fn findTheme(name: []const u8) ThemeColors {
    for (&builtin_themes) |*t| {
        if (std.mem.eql(u8, t.name, name)) return t.colors;
    }
    return builtin_themes[0].colors; // default to classic
}

test "findTheme returns classic by default" {
    const c = findTheme("nonexistent");
    try std.testing.expectEqual(@as(Color, 4), c.panel_bg);
}

test "findTheme finds all built-in themes" {
    const names = [_][]const u8{ "classic", "nord", "dracula", "solarized", "gruvbox", "dos-navigator", "mono" };
    for (&names) |name| {
        const c = findTheme(name);
        _ = c;
    }
}
