const std = @import("std");
const posix = std.posix;
const App = @import("app.zig").App;
const config_mod = @import("config/config.zig");

var global_app: ?*App = null;

fn handleSigwinch(_: c_int) callconv(.c) void {
    if (global_app) |app| {
        app.terminal.updateSize();
        app.needs_full_redraw = true;
    }
}

fn handleSigint(_: c_int) callconv(.c) void {
    if (global_app) |app| {
        app.terminal.leaveAltScreen() catch {};
        app.terminal.disableRawMode();
    }
    posix.exit(0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Get initial directories
    var left_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;

    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch "/";
    const left_path: []const u8 = if (args.len > 1) args[1] else cwd;
    const right_path: []const u8 = if (args.len > 2) args[2] else left_path;

    // Copy paths to stable buffers (safe — cwd_buf is separate from left/right buffers)
    @memcpy(left_path_buf[0..left_path.len], left_path);
    @memcpy(right_path_buf[0..right_path.len], right_path);

    var app = try App.init(allocator, left_path_buf[0..left_path.len], right_path_buf[0..right_path.len]);
    defer app.deinit();

    global_app = &app;
    defer global_app = null;

    // Set up signal handlers
    const sigwinch_action = posix.Sigaction{
        .handler = .{ .handler = handleSigwinch },
        .mask = posix.sigemptyset(),
        .flags = std.c.SA.RESTART,
    };
    posix.sigaction(posix.SIG.WINCH, &sigwinch_action, null);

    const sigint_action = posix.Sigaction{
        .handler = .{ .handler = handleSigint },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sigint_action, null);
    posix.sigaction(posix.SIG.TERM, &sigint_action, null);

    // Run the application
    try app.run();
}

// Import all test modules
test {
    _ = @import("config/config.zig");
    _ = @import("config/theme.zig");
    _ = @import("input.zig");
    _ = @import("terminal.zig");
    _ = @import("fs/dir.zig");
    _ = @import("fs/ops.zig");
    _ = @import("ui/layout.zig");
    _ = @import("ui/panel.zig");
    _ = @import("ui/dialog.zig");
    _ = @import("viewer/viewer.zig");
    _ = @import("viewer/markdown.zig");
    _ = @import("viewer/html.zig");
    _ = @import("viewer/hex.zig");
}
