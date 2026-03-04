const std = @import("std");
const posix = std.posix;
const App = @import("app.zig").App;
const config_mod = @import("config/config.zig");
const build_options = @import("build_options");

const version = std.mem.trimRight(u8, build_options.version, &.{ '\n', '\r' });

var global_app: ?*App = null;

fn handleSigwinch(_: c_int) callconv(.c) void {
    if (global_app) |app| {
        app.terminal.updateSize();
        app.needs_full_redraw = true;
    }
}

fn handleSigint(_: c_int) callconv(.c) void {
    // No-op: Ctrl+C handled in input parser.
    // During shell command execution we're out of raw mode,
    // so SIGINT goes to the child process naturally.
}

fn printHelp() void {
    const out = std.fs.File.stdout();
    var buf: [128]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "mc-zig {s}\r\n", .{version}) catch "mc-zig\r\n";
    out.writeAll(header) catch {};
    out.writeAll(
        "Midnight Commander clone in Zig\r\n" ++
        "\r\n" ++
        "Usage: mc [options] [left_dir] [right_dir]\r\n" ++
        "\r\n" ++
        "Options:\r\n" ++
        "  -h, --help     Show this help\r\n" ++
        "  -v, --version  Show version\r\n" ++
        "\r\n" ++
        "Keys:\r\n" ++
        "  Tab       Switch panel\r\n" ++
        "  Enter     Enter dir / view file\r\n" ++
        "  F2        File menu\r\n" ++
        "  F3        View file\r\n" ++
        "  F4        Edit ($EDITOR)\r\n" ++
        "  F5        Copy\r\n" ++
        "  F6        Move\r\n" ++
        "  F7        Mkdir\r\n" ++
        "  F8        Delete\r\n" ++
        "  F9        Options menu\r\n" ++
        "  F10       Quit\r\n" ++
        "  Ins       Tag/untag\r\n" ++
        "  Ctrl+O    Toggle console\r\n" ++
        "  Shift+F6  Rename\r\n" ++
        "  .         Toggle hidden\r\n" ++
        "  Alt+key   Quick search\r\n"
    ) catch {};
}

fn printVersion() void {
    const out = std.fs.File.stdout();
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "mc-zig {s}\r\n", .{version}) catch "mc-zig\r\n";
    out.writeAll(msg) catch {};
}

fn printUnknownOption(arg: []const u8) void {
    const err_out = std.fs.File.stderr();
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "mc: unknown option '{s}'\r\nTry 'mc --help' for more information.\r\n", .{arg}) catch return;
    err_out.writeAll(msg) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Handle flags before initializing the app
    var positional_start: usize = 1;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            printVersion();
            return;
        } else if (arg.len > 0 and arg[0] == '-') {
            printUnknownOption(arg);
            posix.exit(1);
        } else {
            break;
        }
        positional_start += 1;
    }

    // Get initial directories
    var left_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;

    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch "/";
    const left_path: []const u8 = if (positional_start < args.len) args[positional_start] else cwd;
    const right_path: []const u8 = if (positional_start + 1 < args.len) args[positional_start + 1] else left_path;

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
