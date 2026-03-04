const std = @import("std");
const theme = @import("theme.zig");

pub const Config = struct {
    theme_name: [64]u8 = undefined,
    theme_name_len: usize = 0,
    editor: [256]u8 = undefined,
    editor_len: usize = 0,
    show_hidden: bool = false,
    colors: theme.ThemeColors = .{},

    pub fn init() Config {
        var c = Config{};
        const default_theme = "classic";
        @memcpy(c.theme_name[0..default_theme.len], default_theme);
        c.theme_name_len = default_theme.len;
        const default_editor = "vim";
        @memcpy(c.editor[0..default_editor.len], default_editor);
        c.editor_len = default_editor.len;
        c.colors = theme.findTheme(default_theme);
        return c;
    }

    pub fn getThemeName(self: *const Config) []const u8 {
        return self.theme_name[0..self.theme_name_len];
    }

    pub fn getEditor(self: *const Config) []const u8 {
        return self.editor[0..self.editor_len];
    }

    pub fn setThemeName(self: *Config, name: []const u8) void {
        const len = @min(name.len, self.theme_name.len);
        @memcpy(self.theme_name[0..len], name[0..len]);
        self.theme_name_len = len;
        self.colors = theme.findTheme(self.theme_name[0..len]);
    }

    pub fn setEditor(self: *Config, ed: []const u8) void {
        const len = @min(ed.len, self.editor.len);
        @memcpy(self.editor[0..len], ed[0..len]);
        self.editor_len = len;
    }
};

const IniLine = union(enum) {
    section: []const u8,
    key_value: struct { key: []const u8, value: []const u8 },
    empty,
};

fn parseIniLine(line: []const u8) IniLine {
    var s = line;
    // Trim leading whitespace
    while (s.len > 0 and (s[0] == ' ' or s[0] == '\t')) s = s[1..];
    if (s.len == 0 or s[0] == '#' or s[0] == ';') return .empty;

    if (s[0] == '[') {
        if (std.mem.indexOfScalar(u8, s, ']')) |end| {
            return .{ .section = s[1..end] };
        }
        return .empty;
    }

    if (std.mem.indexOfScalar(u8, s, '=')) |eq| {
        var key = s[0..eq];
        var value = s[eq + 1 ..];
        // Trim whitespace from key
        while (key.len > 0 and (key[key.len - 1] == ' ' or key[key.len - 1] == '\t')) key = key[0 .. key.len - 1];
        // Trim whitespace from value
        while (value.len > 0 and (value[0] == ' ' or value[0] == '\t')) value = value[1..];
        while (value.len > 0 and (value[value.len - 1] == ' ' or value[value.len - 1] == '\t' or value[value.len - 1] == '\r')) value = value[0 .. value.len - 1];
        return .{ .key_value = .{ .key = key, .value = value } };
    }

    return .empty;
}

pub fn loadFromContent(content: []const u8) Config {
    var cfg = Config.init();
    var current_section: []const u8 = "";

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const parsed = parseIniLine(line);
        switch (parsed) {
            .section => |s| {
                current_section = s;
            },
            .key_value => |kv| {
                if (std.mem.eql(u8, current_section, "general")) {
                    if (std.mem.eql(u8, kv.key, "theme")) {
                        cfg.setThemeName(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "editor")) {
                        cfg.setEditor(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "show_hidden")) {
                        cfg.show_hidden = std.mem.eql(u8, kv.value, "true");
                    }
                }
            },
            .empty => {},
        }
    }

    return cfg;
}

pub fn loadConfigFile(allocator: std.mem.Allocator) Config {
    const home = std.posix.getenv("HOME") orelse return Config.init();
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.config/mc-zig/config.ini", .{home}) catch return Config.init();

    const file = std.fs.openFileAbsolute(path, .{}) catch return Config.init();
    defer file.close();

    const content = file.readToEndAlloc(allocator, 64 * 1024) catch return Config.init();
    defer allocator.free(content);

    return loadFromContent(content);
}

pub fn ensureDefaultConfig() void {
    const home = std.posix.getenv("HOME") orelse return;
    var dir_buf: [512]u8 = undefined;
    const dir_path = std.fmt.bufPrint(&dir_buf, "{s}/.config/mc-zig", .{home}) catch return;

    std.fs.makeDirAbsolute(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return;
    };

    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.config/mc-zig/config.ini", .{home}) catch return;

    // Only create if doesn't exist
    const file = std.fs.createFileAbsolute(path, .{ .exclusive = true }) catch return;
    defer file.close();

    const default_content =
        \\[general]
        \\theme = classic
        \\editor = vim
        \\show_hidden = false
        \\
    ;
    file.writeAll(default_content) catch {};
}

test "parseIniLine section" {
    const result = parseIniLine("[general]");
    switch (result) {
        .section => |s| try std.testing.expectEqualStrings("general", s),
        else => return error.TestUnexpectedResult,
    }
}

test "parseIniLine key_value" {
    const result = parseIniLine("theme = classic");
    switch (result) {
        .key_value => |kv| {
            try std.testing.expectEqualStrings("theme", kv.key);
            try std.testing.expectEqualStrings("classic", kv.value);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parseIniLine comment" {
    const result = parseIniLine("# comment");
    switch (result) {
        .empty => {},
        else => return error.TestUnexpectedResult,
    }
}

test "loadFromContent" {
    const content =
        \\[general]
        \\theme = dracula
        \\editor = nvim
        \\show_hidden = true
    ;
    const cfg = loadFromContent(content);
    try std.testing.expectEqualStrings("dracula", cfg.getThemeName());
    try std.testing.expectEqualStrings("nvim", cfg.getEditor());
    try std.testing.expect(cfg.show_hidden);
}
