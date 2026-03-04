const std = @import("std");
const md = @import("markdown.zig");
const theme_mod = @import("../config/theme.zig");

const HtmlState = enum {
    text,
    tag,
    entity,
};

pub const HtmlRenderResult = struct {
    lines: []md.StyledLine,
    backing_text: []u8,

    pub fn deinit(self: HtmlRenderResult, allocator: std.mem.Allocator) void {
        allocator.free(self.lines);
        allocator.free(self.backing_text);
    }
};

pub fn renderHtml(
    allocator: std.mem.Allocator,
    content: []const u8,
) !HtmlRenderResult {
    // Strip HTML tags and convert to styled lines
    var result = std.ArrayList(u8){};

    var state: HtmlState = .text;
    var tag_name_buf: [64]u8 = undefined;
    var tag_name_len: usize = 0;
    var entity_buf: [16]u8 = undefined;
    var entity_len: usize = 0;
    var in_tag_name = false;
    var is_closing_tag = false;
    var in_pre = false;

    for (content) |ch| {
        switch (state) {
            .text => {
                if (ch == '<') {
                    state = .tag;
                    tag_name_len = 0;
                    in_tag_name = true;
                    is_closing_tag = false;
                } else if (ch == '&') {
                    state = .entity;
                    entity_len = 0;
                } else {
                    if (ch == '\n' and !in_pre) {
                        // Collapse consecutive newlines
                        if (result.items.len == 0 or result.items[result.items.len - 1] != '\n') {
                            try result.append(allocator, '\n');
                        }
                    } else {
                        try result.append(allocator, ch);
                    }
                }
            },
            .tag => {
                if (ch == '>') {
                    // Process tag
                    const tag = tag_name_buf[0..tag_name_len];
                    if (is_closing_tag) {
                        if (eqlLower(tag, "pre") or eqlLower(tag, "code")) {
                            in_pre = false;
                        }
                    } else {
                        if (eqlLower(tag, "br") or eqlLower(tag, "br/")) {
                            try result.append(allocator, '\n');
                        } else if (eqlLower(tag, "p") or eqlLower(tag, "div")) {
                            if (result.items.len > 0 and result.items[result.items.len - 1] != '\n') {
                                try result.append(allocator, '\n');
                            }
                            try result.append(allocator, '\n');
                        } else if (eqlLower(tag, "h1") or eqlLower(tag, "h2") or eqlLower(tag, "h3") or
                            eqlLower(tag, "h4") or eqlLower(tag, "h5") or eqlLower(tag, "h6"))
                        {
                            try result.append(allocator, '\n');
                            try result.appendSlice(allocator, "# ");
                        } else if (eqlLower(tag, "li")) {
                            try result.append(allocator, '\n');
                            try result.appendSlice(allocator, "- ");
                        } else if (eqlLower(tag, "pre") or eqlLower(tag, "code")) {
                            in_pre = true;
                        }
                    }
                    state = .text;
                } else if (ch == '/' and tag_name_len == 0) {
                    is_closing_tag = true;
                } else if (in_tag_name) {
                    if (ch == ' ' or ch == '\t' or ch == '\n') {
                        in_tag_name = false;
                    } else if (tag_name_len < tag_name_buf.len) {
                        tag_name_buf[tag_name_len] = ch;
                        tag_name_len += 1;
                    }
                }
            },
            .entity => {
                if (ch == ';') {
                    const ent = entity_buf[0..entity_len];
                    if (eqlLower(ent, "amp")) {
                        try result.append(allocator, '&');
                    } else if (eqlLower(ent, "lt")) {
                        try result.append(allocator, '<');
                    } else if (eqlLower(ent, "gt")) {
                        try result.append(allocator, '>');
                    } else if (eqlLower(ent, "quot")) {
                        try result.append(allocator, '"');
                    } else if (eqlLower(ent, "nbsp")) {
                        try result.append(allocator, ' ');
                    } else if (eqlLower(ent, "apos")) {
                        try result.append(allocator, '\'');
                    }
                    state = .text;
                } else if (entity_len < entity_buf.len) {
                    entity_buf[entity_len] = ch;
                    entity_len += 1;
                } else {
                    // Entity too long, dump as-is
                    try result.append(allocator, '&');
                    try result.appendSlice(allocator, entity_buf[0..entity_len]);
                    state = .text;
                }
            },
        }
    }

    // Transfer ownership of the text buffer so styled lines can reference it
    const backing = try result.toOwnedSlice(allocator);
    const lines = try md.renderMarkdown(allocator, backing);
    return .{ .lines = lines, .backing_text = backing };
}

fn eqlLower(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != bc) return false;
    }
    return true;
}

test "strip basic HTML tags" {
    const html = "<p>Hello <b>world</b></p>";
    const result = try renderHtml(std.testing.allocator, html);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.lines.len > 0);
    // Should contain "Hello world" without tags
    var found = false;
    for (result.lines) |line| {
        if (std.mem.indexOf(u8, line.text, "Hello") != null) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "decode HTML entities" {
    const html = "&amp; &lt; &gt; &quot;";
    const result = try renderHtml(std.testing.allocator, html);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.lines.len > 0);
    var found = false;
    for (result.lines) |line| {
        if (std.mem.indexOf(u8, line.text, "& < > \"") != null) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "HTML headings" {
    const html = "<h1>Title</h1><p>Text</p>";
    const result = try renderHtml(std.testing.allocator, html);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.lines.len > 0);
}
