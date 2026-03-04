const std = @import("std");
const posix = std.posix;

pub const Key = enum {
    // Navigation
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    shift_f6,
    // Actions
    enter,
    tab,
    shift_tab,
    escape,
    backspace,
    delete,
    insert,
    // Control keys
    ctrl_o,
    ctrl_s,
    ctrl_r,
    ctrl_backslash,
    ctrl_x,
    // Character
    char,
    // Unknown/none
    none,
};

pub const InputEvent = struct {
    key: Key = .none,
    char: u21 = 0,
};

const State = enum {
    ground,
    escape,
    csi,
    csi_param,
    ss3,
};

pub const InputParser = struct {
    state: State = .ground,
    params: [8]u16 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    param_idx: u8 = 0,

    pub fn feed(self: *InputParser, byte: u8) ?InputEvent {
        switch (self.state) {
            .ground => return self.handleGround(byte),
            .escape => return self.handleEscape(byte),
            .csi, .csi_param => return self.handleCsi(byte),
            .ss3 => return self.handleSs3(byte),
        }
    }

    fn reset(self: *InputParser) void {
        self.state = .ground;
        self.params = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        self.param_idx = 0;
    }

    fn handleGround(self: *InputParser, byte: u8) ?InputEvent {
        switch (byte) {
            0x1b => {
                self.state = .escape;
                return null;
            },
            0x01...0x08, 0x0a...0x0c, 0x0e...0x1a => {
                // Ctrl+letter: ctrl_a=0x01, ctrl_b=0x02, etc
                return switch (byte) {
                    0x0f => InputEvent{ .key = .ctrl_o }, // Ctrl+O
                    0x13 => InputEvent{ .key = .ctrl_s }, // Ctrl+S
                    0x12 => InputEvent{ .key = .ctrl_r }, // Ctrl+R
                    0x1c => InputEvent{ .key = .ctrl_backslash }, // Ctrl+backslash
                    0x18 => InputEvent{ .key = .ctrl_x }, // Ctrl+X
                    else => null,
                };
            },
            0x09 => return InputEvent{ .key = .tab },
            0x0d => return InputEvent{ .key = .enter },
            0x7f => return InputEvent{ .key = .backspace },
            0x1c => return InputEvent{ .key = .ctrl_backslash },
            else => {
                if (byte >= 0x20 and byte < 0x7f) {
                    return InputEvent{ .key = .char, .char = byte };
                }
                // UTF-8 lead byte - simplified handling, just pass as char
                if (byte >= 0x80) {
                    return InputEvent{ .key = .char, .char = byte };
                }
                return null;
            },
        }
    }

    fn handleEscape(self: *InputParser, byte: u8) ?InputEvent {
        switch (byte) {
            '[' => {
                self.state = .csi;
                self.params = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
                self.param_idx = 0;
                return null;
            },
            'O' => {
                self.state = .ss3;
                return null;
            },
            else => {
                self.reset();
                return InputEvent{ .key = .escape };
            },
        }
    }

    fn handleCsi(self: *InputParser, byte: u8) ?InputEvent {
        // Parameter bytes
        if (byte >= '0' and byte <= '9') {
            self.state = .csi_param;
            if (self.param_idx < self.params.len) {
                self.params[self.param_idx] = self.params[self.param_idx] * 10 + (byte - '0');
            }
            return null;
        }

        if (byte == ';') {
            if (self.param_idx < self.params.len - 1) {
                self.param_idx += 1;
            }
            return null;
        }

        // Final byte - save params before reset since handleTilde needs them
        const p0 = self.params[0];
        const p1 = self.params[1];
        self.reset();
        return switch (byte) {
            'A' => InputEvent{ .key = .up },
            'B' => InputEvent{ .key = .down },
            'C' => InputEvent{ .key = .right },
            'D' => InputEvent{ .key = .left },
            'H' => InputEvent{ .key = .home },
            'F' => InputEvent{ .key = .end },
            'Z' => InputEvent{ .key = .shift_tab },
            '~' => switch (p0) {
                2 => InputEvent{ .key = .insert },
                3 => InputEvent{ .key = .delete },
                5 => InputEvent{ .key = .page_up },
                6 => InputEvent{ .key = .page_down },
                15 => InputEvent{ .key = .f5 },
                17 => if (p1 == 2) InputEvent{ .key = .shift_f6 } else InputEvent{ .key = .f6 },
                18 => InputEvent{ .key = .f7 },
                19 => InputEvent{ .key = .f8 },
                20 => InputEvent{ .key = .f9 },
                21 => InputEvent{ .key = .f10 },
                23 => InputEvent{ .key = .f11 },
                24 => InputEvent{ .key = .f12 },
                else => null,
            },
            else => null,
        };
    }

    fn handleSs3(self: *InputParser, byte: u8) ?InputEvent {
        self.reset();
        return switch (byte) {
            'P' => InputEvent{ .key = .f1 },
            'Q' => InputEvent{ .key = .f2 },
            'R' => InputEvent{ .key = .f3 },
            'S' => InputEvent{ .key = .f4 },
            'H' => InputEvent{ .key = .home },
            'F' => InputEvent{ .key = .end },
            else => null,
        };
    }
};

pub fn readInput(fd: posix.fd_t) ?u8 {
    var buf: [1]u8 = undefined;
    const n = posix.read(fd, &buf) catch return null;
    if (n == 0) return null;
    return buf[0];
}

pub fn pollInput(fd: posix.fd_t, timeout_ms: i32) bool {
    var fds = [_]posix.pollfd{.{
        .fd = fd,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    const result = posix.poll(&fds, timeout_ms) catch return false;
    return result > 0;
}

test "parse arrow keys" {
    var parser = InputParser{};
    try std.testing.expect(parser.feed(0x1b) == null);
    try std.testing.expect(parser.feed('[') == null);
    const evt = parser.feed('A');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.up, evt.?.key);
}

test "parse F5 key" {
    var parser = InputParser{};
    _ = parser.feed(0x1b);
    _ = parser.feed('[');
    _ = parser.feed('1');
    _ = parser.feed('5');
    const evt = parser.feed('~');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.f5, evt.?.key);
}

test "parse Ctrl+O" {
    var parser = InputParser{};
    const evt = parser.feed(0x0f);
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.ctrl_o, evt.?.key);
}

test "parse regular character" {
    var parser = InputParser{};
    const evt = parser.feed('a');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.char, evt.?.key);
    try std.testing.expectEqual(@as(u21, 'a'), evt.?.char);
}

test "parse Enter" {
    var parser = InputParser{};
    const evt = parser.feed(0x0d);
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.enter, evt.?.key);
}

test "parse Tab" {
    var parser = InputParser{};
    const evt = parser.feed(0x09);
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.tab, evt.?.key);
}

test "parse Insert" {
    var parser = InputParser{};
    _ = parser.feed(0x1b);
    _ = parser.feed('[');
    _ = parser.feed('2');
    const evt = parser.feed('~');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.insert, evt.?.key);
}

test "parse Shift+F6" {
    var parser = InputParser{};
    _ = parser.feed(0x1b);
    _ = parser.feed('[');
    _ = parser.feed('1');
    _ = parser.feed('7');
    _ = parser.feed(';');
    _ = parser.feed('2');
    const evt = parser.feed('~');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.shift_f6, evt.?.key);
}

test "parse F1 SS3" {
    var parser = InputParser{};
    _ = parser.feed(0x1b);
    _ = parser.feed('O');
    const evt = parser.feed('P');
    try std.testing.expect(evt != null);
    try std.testing.expectEqual(Key.f1, evt.?.key);
}
