const std = @import("std");

pub const OperationKind = enum {
    copy,
    move,
    delete,
};

pub const ConflictChoice = enum {
    overwrite,
    skip,
    rename,
    cancel,
    overwrite_all,
};

pub const ProgressCallback = *const fn (bytes_done: u64, bytes_total: u64) void;

const CHUNK_SIZE: usize = 64 * 1024;

pub fn copyFile(src_path: []const u8, dest_path: []const u8, progress_cb: ?ProgressCallback) !void {
    const src = try std.fs.openFileAbsolute(src_path, .{});
    defer src.close();

    const stat = try src.stat();
    const total: u64 = stat.size;

    const dest = try std.fs.createFileAbsolute(dest_path, .{});
    defer dest.close();

    var buf: [CHUNK_SIZE]u8 = undefined;
    var done: u64 = 0;

    while (true) {
        const n = try src.read(&buf);
        if (n == 0) break;
        try dest.writeAll(buf[0..n]);
        done += n;
        if (progress_cb) |cb| cb(done, total);
    }

    // Preserve permissions
    const mode: std.fs.File.Mode = stat.mode;
    dest.chmod(mode) catch {};
}

pub fn moveFile(src_path: []const u8, dest_path: []const u8, progress_cb: ?ProgressCallback) !void {
    // Try rename first (fast path, same filesystem)
    std.fs.renameAbsolute(src_path, dest_path) catch |err| {
        if (err == error.RenameAcrossMountPoints) {
            // Cross-filesystem: copy then delete
            try copyFile(src_path, dest_path, progress_cb);
            try std.fs.deleteFileAbsolute(src_path);
            return;
        }
        return err;
    };
}

pub fn deleteFile(path: []const u8) !void {
    std.fs.deleteFileAbsolute(path) catch |err| {
        if (err == error.IsDir) {
            try deleteDirectoryRecursive(path);
            return;
        }
        return err;
    };
}

pub fn deleteDirectoryRecursive(path: []const u8) !void {
    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
        return err;
    };

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var child_buf: [std.fs.max_path_bytes]u8 = undefined;
        const child_path = std.fmt.bufPrint(&child_buf, "{s}/{s}", .{ path, entry.name }) catch continue;

        switch (entry.kind) {
            .directory => try deleteDirectoryRecursive(child_path),
            else => std.fs.deleteFileAbsolute(child_path) catch {},
        }
    }
    dir.close();

    std.fs.deleteDirAbsolute(path) catch {};
}

pub fn makeDirectory(path: []const u8) !void {
    try std.fs.makeDirAbsolute(path);
}

pub fn renameEntry(old_path: []const u8, new_path: []const u8) !void {
    try std.fs.renameAbsolute(old_path, new_path);
}

pub fn fileExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub fn getFileSize(path: []const u8) u64 {
    const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
    defer file.close();
    const stat = file.stat() catch return 0;
    return stat.size;
}

pub fn copyDirectoryRecursive(src_path: []const u8, dest_path: []const u8, progress_cb: ?ProgressCallback) !void {
    // Create destination directory
    std.fs.makeDirAbsolute(dest_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var dir = try std.fs.openDirAbsolute(src_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var src_child_buf: [std.fs.max_path_bytes]u8 = undefined;
        var dst_child_buf: [std.fs.max_path_bytes]u8 = undefined;
        const src_child = std.fmt.bufPrint(&src_child_buf, "{s}/{s}", .{ src_path, entry.name }) catch continue;
        const dst_child = std.fmt.bufPrint(&dst_child_buf, "{s}/{s}", .{ dest_path, entry.name }) catch continue;

        switch (entry.kind) {
            .directory => try copyDirectoryRecursive(src_child, dst_child, progress_cb),
            .file => try copyFile(src_child, dst_child, progress_cb),
            .sym_link => {
                // Copy symlink
                var target_buf: [std.fs.max_path_bytes]u8 = undefined;
                if (dir.readLink(entry.name, &target_buf)) |target| {
                    std.fs.symLinkAbsolute(target, dst_child, .{}) catch {};
                } else |_| {}
            },
            else => {},
        }
    }
}

test "makeDirectory and deleteDirectoryRecursive" {
    const test_dir = "/tmp/mc-zig-test-dir";
    makeDirectory(test_dir) catch {};
    defer deleteDirectoryRecursive(test_dir) catch {};

    // Should exist
    try std.testing.expect(fileExists(test_dir));
}

test "copyFile" {
    // Create test file
    const src = "/tmp/mc-zig-test-src.txt";
    const dest = "/tmp/mc-zig-test-dest.txt";
    defer std.fs.deleteFileAbsolute(src) catch {};
    defer std.fs.deleteFileAbsolute(dest) catch {};

    {
        const f = try std.fs.createFileAbsolute(src, .{});
        defer f.close();
        try f.writeAll("hello mc-zig");
    }

    try copyFile(src, dest, null);
    try std.testing.expect(fileExists(dest));
}

test "fileExists" {
    try std.testing.expect(!fileExists("/tmp/mc-zig-nonexistent-12345"));
    try std.testing.expect(fileExists("/tmp"));
}
