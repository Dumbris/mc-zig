const std = @import("std");
const posix = std.posix;
const theme_mod = @import("config/theme.zig");

pub const Cell = struct {
    char: u21 = ' ',
    fg: theme_mod.Color = 7,
    bg: theme_mod.Color = 0,
    bold: bool = false,
    underline: bool = false,
    dim: bool = false,
};

pub const Terminal = struct {
    width: u16 = 80,
    height: u16 = 24,
    front: []Cell = &.{},
    back: []Cell = &.{},
    original_termios: posix.termios = undefined,
    tty_fd: posix.fd_t = 0,
    allocator: std.mem.Allocator,
    writer_buf: std.ArrayList(u8) = .empty,
    in_alt_screen: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Terminal {
        var term = Terminal{
            .allocator = allocator,
        };

        // Open /dev/tty for terminal control
        term.tty_fd = posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0) catch 0;
        if (term.tty_fd == 0) {
            term.tty_fd = posix.STDIN_FILENO;
        }

        term.updateSize();
        try term.allocBuffers();
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        if (self.front.len > 0) self.allocator.free(self.front);
        if (self.back.len > 0) self.allocator.free(self.back);
        self.writer_buf.deinit(self.allocator);
        if (self.tty_fd != posix.STDIN_FILENO and self.tty_fd != 0) {
            posix.close(self.tty_fd);
        }
    }

    fn allocBuffers(self: *Terminal) !void {
        const size: usize = @as(usize, self.width) * @as(usize, self.height);
        if (self.front.len > 0) self.allocator.free(self.front);
        if (self.back.len > 0) self.allocator.free(self.back);
        self.front = try self.allocator.alloc(Cell, size);
        self.back = try self.allocator.alloc(Cell, size);
        self.clear();
    }

    pub fn clear(self: *Terminal) void {
        for (self.front) |*c| c.* = .{};
        for (self.back) |*c| c.* = .{ .char = 0 };
    }

    pub fn updateSize(self: *Terminal) void {
        var ws: posix.winsize = undefined;
        const rc = std.posix.system.ioctl(self.tty_fd, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (rc == 0) {
            self.width = ws.col;
            self.height = ws.row;
        }
    }

    pub fn handleResize(self: *Terminal) !void {
        self.updateSize();
        try self.allocBuffers();
    }

    pub fn enableRawMode(self: *Terminal) !void {
        self.original_termios = try posix.tcgetattr(self.tty_fd);
        var raw = self.original_termios;

        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        raw.oflag.OPOST = false;

        raw.cc[@intFromEnum(posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(posix.V.TIME)] = 1; // 100ms timeout

        try posix.tcsetattr(self.tty_fd, .FLUSH, raw);
    }

    pub fn disableRawMode(self: *Terminal) void {
        posix.tcsetattr(self.tty_fd, .FLUSH, self.original_termios) catch {};
    }

    pub fn enterAltScreen(self: *Terminal) !void {
        try self.writeStr("\x1b[?1049h");
        try self.writeStr("\x1b[?25l");
        try self.flushWriter();
        self.in_alt_screen = true;
    }

    pub fn leaveAltScreen(self: *Terminal) !void {
        try self.writeStr("\x1b[?25h");
        try self.writeStr("\x1b[?1049l");
        try self.flushWriter();
        self.in_alt_screen = false;
    }

    pub fn setCell(self: *Terminal, x: u16, y: u16, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        if (idx < self.front.len) {
            self.front[idx] = cell;
        }
    }

    pub fn writeString(self: *Terminal, x: u16, y: u16, text: []const u8, fg: theme_mod.Color, bg: theme_mod.Color, bold: bool) void {
        var col = x;
        for (text) |ch| {
            if (col >= self.width) break;
            self.setCell(col, y, .{ .char = ch, .fg = fg, .bg = bg, .bold = bold });
            col += 1;
        }
    }

    pub fn fillRow(self: *Terminal, y: u16, fg: theme_mod.Color, bg: theme_mod.Color) void {
        var x: u16 = 0;
        while (x < self.width) : (x += 1) {
            self.setCell(x, y, .{ .char = ' ', .fg = fg, .bg = bg });
        }
    }

    pub fn render(self: *Terminal) !void {
        var last_fg: theme_mod.Color = 255;
        var last_bg: theme_mod.Color = 255;
        var last_bold: bool = false;
        var last_dim: bool = false;
        var last_underline: bool = false;

        const size: usize = @as(usize, self.width) * @as(usize, self.height);
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const front = self.front[i];
            const back = self.back[i];

            if (front.char == back.char and front.fg == back.fg and front.bg == back.bg and
                front.bold == back.bold and front.underline == back.underline and front.dim == back.dim)
            {
                continue;
            }

            const y: u16 = @intCast(i / @as(usize, self.width));
            const x: u16 = @intCast(i % @as(usize, self.width));

            try self.writeFmt("\x1b[{d};{d}H", .{ y + 1, x + 1 });

            if (front.bold != last_bold or front.dim != last_dim or front.underline != last_underline) {
                try self.writeStr("\x1b[0m");
                last_fg = 255;
                last_bg = 255;
                last_bold = false;
                last_dim = false;
                last_underline = false;
                if (front.bold) {
                    try self.writeStr("\x1b[1m");
                    last_bold = true;
                }
                if (front.dim) {
                    try self.writeStr("\x1b[2m");
                    last_dim = true;
                }
                if (front.underline) {
                    try self.writeStr("\x1b[4m");
                    last_underline = true;
                }
            }

            if (front.fg != last_fg) {
                try self.writeFmt("\x1b[38;5;{d}m", .{front.fg});
                last_fg = front.fg;
            }
            if (front.bg != last_bg) {
                try self.writeFmt("\x1b[48;5;{d}m", .{front.bg});
                last_bg = front.bg;
            }

            if (front.char < 128) {
                try self.writer_buf.append(self.allocator, @intCast(front.char));
            } else {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(front.char, &buf) catch 1;
                try self.writer_buf.appendSlice(self.allocator, buf[0..len]);
            }
        }

        try self.writeStr("\x1b[0m");
        try self.flushWriter();

        @memcpy(self.back, self.front);
    }

    fn writeStr(self: *Terminal, s: []const u8) !void {
        try self.writer_buf.appendSlice(self.allocator, s);
    }

    fn writeFmt(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.writer_buf.writer(self.allocator), fmt, args);
    }

    fn flushWriter(self: *Terminal) !void {
        if (self.writer_buf.items.len == 0) return;
        const stdout = std.fs.File.stdout();
        stdout.writeAll(self.writer_buf.items) catch {};
        self.writer_buf.clearRetainingCapacity();
    }
};

test "Cell default values" {
    const c = Cell{};
    try std.testing.expectEqual(@as(u21, ' '), c.char);
    try std.testing.expectEqual(@as(u8, 7), c.fg);
    try std.testing.expectEqual(@as(u8, 0), c.bg);
}

test "setCell within bounds" {
    var buf: [80 * 24]Cell = undefined;
    var back_buf: [80 * 24]Cell = undefined;
    for (&buf) |*c| c.* = .{};
    for (&back_buf) |*c| c.* = .{ .char = 0 };
    var term = Terminal{
        .width = 80,
        .height = 24,
        .front = &buf,
        .back = &back_buf,
        .allocator = std.testing.allocator,
    };
    term.setCell(5, 3, .{ .char = 'A', .fg = 10, .bg = 0 });
    const idx: usize = 3 * 80 + 5;
    try std.testing.expectEqual(@as(u21, 'A'), term.front[idx].char);
}
