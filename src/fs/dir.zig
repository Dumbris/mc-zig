const std = @import("std");

pub const EntryKind = enum {
    file,
    directory,
    symlink,
    other,
};

pub const DirEntry = struct {
    name: [256]u8 = undefined,
    name_len: usize = 0,
    size: u64 = 0,
    modified: i128 = 0,
    kind: EntryKind = .file,
    permissions: u32 = 0,
    link_target: [256]u8 = undefined,
    link_target_len: usize = 0,
    is_executable: bool = false,
    is_hidden: bool = false,

    pub fn getName(self: *const DirEntry) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getLinkTarget(self: *const DirEntry) ?[]const u8 {
        if (self.link_target_len == 0) return null;
        return self.link_target[0..self.link_target_len];
    }

    pub fn setName(self: *DirEntry, n: []const u8) void {
        const len = @min(n.len, self.name.len);
        @memcpy(self.name[0..len], n[0..len]);
        self.name_len = len;
        self.is_hidden = len > 0 and n[0] == '.';
    }
};

pub const SortMode = enum {
    name,
    size,
    date,
    extension,
};

pub fn compareEntries(a: DirEntry, b: DirEntry, sort_mode: SortMode, ascending: bool) bool {
    // ".." always first
    const a_name = a.name[0..a.name_len];
    const b_name = b.name[0..b.name_len];
    if (std.mem.eql(u8, a_name, "..")) return true;
    if (std.mem.eql(u8, b_name, "..")) return false;

    // Directories before files
    if (a.kind == .directory and b.kind != .directory) return true;
    if (a.kind != .directory and b.kind == .directory) return false;

    const result: bool = switch (sort_mode) {
        .name => lessThanStr(a_name, b_name),
        .size => a.size < b.size,
        .date => a.modified < b.modified,
        .extension => blk: {
            const a_ext = getExtension(a_name);
            const b_ext = getExtension(b_name);
            if (a_ext.len == 0 and b_ext.len == 0) break :blk lessThanStr(a_name, b_name);
            if (a_ext.len == 0) break :blk true;
            if (b_ext.len == 0) break :blk false;
            const cmp = compareCaseInsensitive(a_ext, b_ext);
            if (cmp != .eq) break :blk cmp == .lt;
            break :blk lessThanStr(a_name, b_name);
        },
    };

    return if (ascending) result else !result;
}

fn lessThanStr(a: []const u8, b: []const u8) bool {
    return compareCaseInsensitive(a, b) == .lt;
}

fn compareCaseInsensitive(a: []const u8, b: []const u8) std.math.Order {
    const len = @min(a.len, b.len);
    for (0..len) |i| {
        const ac = std.ascii.toLower(a[i]);
        const bc = std.ascii.toLower(b[i]);
        if (ac < bc) return .lt;
        if (ac > bc) return .gt;
    }
    if (a.len < b.len) return .lt;
    if (a.len > b.len) return .gt;
    return .eq;
}

fn getExtension(name: []const u8) []const u8 {
    var i = name.len;
    while (i > 0) {
        i -= 1;
        if (name[i] == '.') {
            if (i == 0) return "";
            return name[i + 1 ..];
        }
    }
    return "";
}

pub fn listDirectory(allocator: std.mem.Allocator, path: []const u8, show_hidden: bool) ![]DirEntry {
    var entries = std.ArrayList(DirEntry){};
    errdefer entries.deinit(allocator);

    var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    // Always add parent directory entry
    var parent_entry = DirEntry{};
    parent_entry.setName("..");
    parent_entry.kind = .directory;
    try entries.append(allocator, parent_entry);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!show_hidden and entry.name.len > 0 and entry.name[0] == '.') continue;

        var de = DirEntry{};
        de.setName(entry.name);
        de.kind = switch (entry.kind) {
            .directory => .directory,
            .sym_link => .symlink,
            .file => .file,
            else => .other,
        };

        // Get stat info
        if (dir.statFile(entry.name)) |stat| {
            de.size = stat.size;
            de.modified = stat.mtime;
            de.permissions = @intCast(stat.mode & 0o7777);
            de.is_executable = (stat.mode & 0o111) != 0;
        } else |_| {}

        // Resolve symlink target
        if (de.kind == .symlink) {
            var target_buf: [256]u8 = undefined;
            if (dir.readLink(entry.name, &target_buf)) |target| {
                const tlen = @min(target.len, de.link_target.len);
                @memcpy(de.link_target[0..tlen], target[0..tlen]);
                de.link_target_len = tlen;
            } else |_| {}
        }

        try entries.append(allocator, de);
    }

    return entries.toOwnedSlice(allocator);
}

const SortContext = struct {
    mode: SortMode,
    ascending: bool,

    pub fn lessThan(ctx: @This(), a: DirEntry, b: DirEntry) bool {
        return compareEntries(a, b, ctx.mode, ctx.ascending);
    }
};

pub fn sortEntries(entries: []DirEntry, mode: SortMode, ascending: bool) void {
    std.mem.sort(DirEntry, entries, SortContext{ .mode = mode, .ascending = ascending }, SortContext.lessThan);
}

pub fn formatSize(size: u64) [8]u8 {
    var buf: [8]u8 = [_]u8{' '} ** 8;
    if (size < 1024) {
        _ = std.fmt.bufPrint(&buf, "{d:>7}", .{size}) catch {};
    } else if (size < 1024 * 1024) {
        _ = std.fmt.bufPrint(&buf, "{d:>6}K", .{size / 1024}) catch {};
    } else if (size < 1024 * 1024 * 1024) {
        _ = std.fmt.bufPrint(&buf, "{d:>6}M", .{size / (1024 * 1024)}) catch {};
    } else {
        _ = std.fmt.bufPrint(&buf, "{d:>6}G", .{size / (1024 * 1024 * 1024)}) catch {};
    }
    return buf;
}

pub fn formatDate(timestamp: i128) [12]u8 {
    var buf: [12]u8 = [_]u8{' '} ** 12;
    // Convert nanoseconds to seconds
    const secs: i64 = @intCast(@divTrunc(timestamp, std.time.ns_per_s));
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, secs)) };
    const day = epoch.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();

    _ = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        yd.year,
        @as(u16, @intFromEnum(md.month)) + 1,
        @as(u16, md.day_index) + 1,
    }) catch {};
    return buf;
}

test "formatSize bytes" {
    const result = formatSize(42);
    const s = std.mem.trim(u8, &result, " ");
    try std.testing.expectEqualStrings("42", s);
}

test "formatSize kilobytes" {
    const result = formatSize(2048);
    const trimmed = std.mem.trim(u8, &result, " ");
    try std.testing.expectEqualStrings("2K", trimmed);
}

test "formatSize megabytes" {
    const result = formatSize(5 * 1024 * 1024);
    const trimmed = std.mem.trim(u8, &result, " ");
    try std.testing.expectEqualStrings("5M", trimmed);
}

test "getExtension" {
    try std.testing.expectEqualStrings("txt", getExtension("file.txt"));
    try std.testing.expectEqualStrings("md", getExtension("README.md"));
    try std.testing.expectEqualStrings("", getExtension("Makefile"));
    try std.testing.expectEqualStrings("", getExtension(".hidden"));
}

test "compareEntries parent always first" {
    var a = DirEntry{};
    a.setName("..");
    a.kind = .directory;
    var b = DirEntry{};
    b.setName("file.txt");
    try std.testing.expect(compareEntries(a, b, .name, true));
    try std.testing.expect(!compareEntries(b, a, .name, true));
}

test "compareEntries dirs before files" {
    var a = DirEntry{};
    a.setName("aaa");
    a.kind = .directory;
    var b = DirEntry{};
    b.setName("aaa");
    b.kind = .file;
    try std.testing.expect(compareEntries(a, b, .name, true));
}

test "listDirectory current dir" {
    const entries = try listDirectory(std.testing.allocator, "/tmp", false);
    defer std.testing.allocator.free(entries);
    try std.testing.expect(entries.len > 0);
    try std.testing.expectEqualStrings("..", entries[0].getName());
}
