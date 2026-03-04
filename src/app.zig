const std = @import("std");
const posix = std.posix;
const term_mod = @import("terminal.zig");
const input_mod = @import("input.zig");
const theme_mod = @import("config/theme.zig");
const config_mod = @import("config/config.zig");
const panel_mod = @import("ui/panel.zig");
const dialog_mod = @import("ui/dialog.zig");
const statusbar = @import("ui/statusbar.zig");
const layout_mod = @import("ui/layout.zig");
const ops = @import("fs/ops.zig");
const viewer_mod = @import("viewer/viewer.zig");

pub const AppMode = enum {
    normal,
    panel_hidden,
    viewer,
    dialog,
    quick_search,
    menu,
};

const MenuId = enum { left, file, command, options, right };

const MenuItem = struct {
    label: []const u8,
    action: MenuAction,
};

const MenuAction = enum {
    sort_name,
    sort_size,
    sort_date,
    sort_ext,
    toggle_hidden,
    theme,
    refresh,
    swap_panels,
    equal_panels,
    quit,
};

pub const App = struct {
    mode: AppMode = .normal,
    panels: [2]panel_mod.Panel = undefined,
    active_panel: u1 = 0,
    terminal: term_mod.Terminal = undefined,
    config: config_mod.Config = undefined,
    running: bool = true,
    dialog: ?dialog_mod.Dialog = null,
    pending_operation: ?PendingOp = null,
    viewer: viewer_mod.Viewer = undefined,
    input_parser: input_mod.InputParser = .{},
    layout: layout_mod.Layout = undefined,
    search_buf: [128]u8 = undefined,
    search_len: usize = 0,
    allocator: std.mem.Allocator,
    needs_full_redraw: bool = true,
    theme_index: usize = 0,
    menu_id: MenuId = .left,
    menu_cursor: usize = 0,
    cmd_buf: [1024]u8 = undefined,
    cmd_len: usize = 0,
    cmd_cursor: usize = 0,

    const PendingOp = struct {
        kind: ops.OperationKind,
        sources: [][]u8 = &.{},
        dest_dir: []const u8 = "",
    };

    pub fn init(allocator: std.mem.Allocator, left_path: []const u8, right_path: []const u8) !App {
        var app = App{
            .allocator = allocator,
        };

        // Load config
        config_mod.ensureDefaultConfig();
        app.config = config_mod.loadConfigFile(allocator);

        // Find initial theme index
        for (theme_mod.builtin_themes, 0..) |t, i| {
            if (std.mem.eql(u8, t.name, app.config.theme_name[0..app.config.theme_name_len])) {
                app.theme_index = i;
                break;
            }
        }

        // Init terminal
        app.terminal = try term_mod.Terminal.init(allocator);
        app.layout = layout_mod.Layout.calculate(app.terminal.width, app.terminal.height);

        // Init panels
        app.panels[0] = panel_mod.Panel.init(allocator);
        app.panels[0].setPath(left_path);
        app.panels[0].is_active = true;

        app.panels[1] = panel_mod.Panel.init(allocator);
        app.panels[1].setPath(right_path);

        // Init viewer
        app.viewer = viewer_mod.Viewer.init(allocator);

        // Load directory listings
        app.panels[0].loadDirectory(app.config.show_hidden) catch {};
        app.panels[1].loadDirectory(app.config.show_hidden) catch {};

        return app;
    }

    pub fn deinit(self: *App) void {
        self.viewer.deinit();
        self.panels[0].deinit();
        self.panels[1].deinit();
        self.freePendingOp();
        self.terminal.deinit();
    }

    fn freePendingOp(self: *App) void {
        if (self.pending_operation) |*po| {
            for (po.sources) |s| self.allocator.free(s);
            if (po.sources.len > 0) self.allocator.free(po.sources);
            self.pending_operation = null;
        }
    }

    pub fn run(self: *App) !void {
        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode();

        try self.terminal.enterAltScreen();
        defer self.terminal.leaveAltScreen() catch {};

        while (self.running) {
            // Render
            if (self.mode != .panel_hidden) {
                self.renderFrame();
                try self.terminal.render();
            }

            // Input
            if (input_mod.pollInput(self.terminal.tty_fd, 50)) {
                if (input_mod.readInput(self.terminal.tty_fd)) |byte| {
                    if (self.input_parser.feed(byte)) |event| {
                        self.handleInput(event);
                    }
                    // Read remaining bytes of escape sequence
                    while (input_mod.pollInput(self.terminal.tty_fd, 10)) {
                        if (input_mod.readInput(self.terminal.tty_fd)) |next_byte| {
                            if (self.input_parser.feed(next_byte)) |event| {
                                self.handleInput(event);
                            }
                        } else break;
                    }
                }
            }
        }
    }

    fn handleInput(self: *App, event: input_mod.InputEvent) void {
        switch (self.mode) {
            .normal => self.handleNormalInput(event),
            .panel_hidden => self.handleHiddenInput(event),
            .viewer => self.handleViewerInput(event),
            .dialog => self.handleDialogInput(event),
            .quick_search => self.handleSearchInput(event),
            .menu => self.handleMenuInput(event),
        }
    }

    fn handleNormalInput(self: *App, event: input_mod.InputEvent) void {
        const panel = &self.panels[self.active_panel];
        const vis_rows = self.layout.panelListingHeight();
        const has_cmd = self.cmd_len > 0;

        switch (event.key) {
            .up => if (!has_cmd) panel.cursorUp(),
            .down => if (!has_cmd) panel.cursorDown(),
            .page_up => if (!has_cmd) panel.pageUp(vis_rows),
            .page_down => if (!has_cmd) panel.pageDown(vis_rows),
            .home => if (has_cmd) {
                self.cmd_cursor = 0;
            } else panel.goHome(),
            .end => if (has_cmd) {
                self.cmd_cursor = self.cmd_len;
            } else panel.goEnd(),
            .left => if (has_cmd) {
                if (self.cmd_cursor > 0) self.cmd_cursor -= 1;
            },
            .right => if (has_cmd) {
                if (self.cmd_cursor < self.cmd_len) self.cmd_cursor += 1;
            },
            .enter => {
                if (has_cmd) {
                    self.executeShellCommand();
                } else {
                    const entry = panel.getCurrentEntry() orelse return;
                    if (entry.kind == .directory) {
                        panel.navigate(self.config.show_hidden) catch {};
                    } else if (entry.is_executable) {
                        self.executeFile();
                    }
                }
            },
            .backspace => {
                if (has_cmd and self.cmd_cursor > 0) {
                    const i = self.cmd_cursor;
                    if (i < self.cmd_len) {
                        std.mem.copyForwards(u8, self.cmd_buf[i - 1 .. self.cmd_len - 1], self.cmd_buf[i..self.cmd_len]);
                    }
                    self.cmd_len -= 1;
                    self.cmd_cursor -= 1;
                }
            },
            .escape => {
                self.cmd_len = 0;
                self.cmd_cursor = 0;
            },
            .tab => {
                if (!has_cmd) {
                    self.panels[self.active_panel].is_active = false;
                    self.active_panel = ~self.active_panel;
                    self.panels[self.active_panel].is_active = true;
                }
            },
            .insert => if (!has_cmd) panel.toggleTag(),
            .delete => {
                if (has_cmd and self.cmd_cursor < self.cmd_len) {
                    const i = self.cmd_cursor;
                    if (i + 1 < self.cmd_len) {
                        std.mem.copyForwards(u8, self.cmd_buf[i .. self.cmd_len - 1], self.cmd_buf[i + 1 .. self.cmd_len]);
                    }
                    self.cmd_len -= 1;
                }
            },
            .f3 => if (!has_cmd) self.openViewer(),
            .f4 => if (!has_cmd) self.openEditor(),
            .f5 => if (!has_cmd) self.startCopy(),
            .f6 => if (!has_cmd) self.startMove(),
            .shift_f6 => if (!has_cmd) self.startRename(),
            .f7 => if (!has_cmd) self.startMkdir(),
            .f8 => if (!has_cmd) self.startDelete(),
            .f10 => self.running = false,
            .ctrl_o => self.togglePanels(),
            .ctrl_c => {
                if (has_cmd) {
                    self.cmd_len = 0;
                    self.cmd_cursor = 0;
                }
            },
            .ctrl_s => {
                if (!has_cmd) {
                    self.mode = .quick_search;
                    self.search_len = 0;
                }
            },
            .ctrl_r => {
                if (!has_cmd) {
                    panel.loadDirectory(self.config.show_hidden) catch {};
                }
            },
            .f9 => self.openMenu(.options),
            .f2 => self.openMenu(.file),
            .char => {
                if (!has_cmd) {
                    if (event.char == 'q' or event.char == 'Q') {
                        self.running = false;
                        return;
                    } else if (event.char == '.') {
                        self.config.show_hidden = !self.config.show_hidden;
                        self.panels[0].loadDirectory(self.config.show_hidden) catch {};
                        self.panels[1].loadDirectory(self.config.show_hidden) catch {};
                        return;
                    }
                }
                if (self.cmd_len < self.cmd_buf.len) {
                    const byte: u8 = @intCast(event.char & 0xFF);
                    if (byte >= 0x20 and byte < 0x7f) {
                        if (self.cmd_cursor < self.cmd_len) {
                            std.mem.copyBackwards(u8, self.cmd_buf[self.cmd_cursor + 1 .. self.cmd_len + 1], self.cmd_buf[self.cmd_cursor..self.cmd_len]);
                        }
                        self.cmd_buf[self.cmd_cursor] = byte;
                        self.cmd_len += 1;
                        self.cmd_cursor += 1;
                    }
                }
            },
            else => {},
        }
    }

    fn handleHiddenInput(self: *App, event: input_mod.InputEvent) void {
        switch (event.key) {
            .ctrl_o => self.togglePanels(),
            .f10 => self.running = false,
            else => {},
        }
    }

    fn handleViewerInput(self: *App, event: input_mod.InputEvent) void {
        const vis_rows = if (self.terminal.height > 2) self.terminal.height - 2 else 1;

        switch (event.key) {
            .up => self.viewer.scrollUp(),
            .down => self.viewer.scrollDown(vis_rows),
            .page_up => self.viewer.pageUp(vis_rows),
            .page_down => self.viewer.pageDown(vis_rows),
            .home => self.viewer.goHome(),
            .end => self.viewer.goEnd(vis_rows),
            .f2 => self.viewer.toggleReadability() catch {},
            .f4 => self.viewer.toggleHex() catch {},
            .f10 => {
                self.mode = .normal;
                self.needs_full_redraw = true;
            },
            .char => {
                if (event.char == 'q' or event.char == 'Q') {
                    self.mode = .normal;
                    self.needs_full_redraw = true;
                }
            },
            else => {},
        }
    }

    fn handleDialogInput(self: *App, event: input_mod.InputEvent) void {
        if (self.dialog == null) {
            self.mode = .normal;
            return;
        }
        var dlg = &self.dialog.?;

        switch (event.key) {
            .enter => {
                const result = dlg.confirm();
                self.processDialogResult(result);
            },
            .escape => {
                self.dialog = null;
                self.freePendingOp();
                self.mode = .normal;
            },
            .tab => dlg.nextButton(),
            .left => dlg.prevButton(),
            .right => dlg.nextButton(),
            .backspace => dlg.handleBackspace(),
            .delete => dlg.handleDelete(),
            .char => {
                if (dlg.kind == .input) {
                    dlg.handleChar(event.char);
                } else if (dlg.kind == .file_conflict) {
                    // Shortcut keys for conflict dialog
                    switch (event.char) {
                        'o', 'O' => self.processDialogResult(.overwrite),
                        's', 'S' => self.processDialogResult(.skip),
                        'r', 'R' => self.processDialogResult(.rename_choice),
                        'a', 'A' => self.processDialogResult(.overwrite_all),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    fn handleSearchInput(self: *App, event: input_mod.InputEvent) void {
        switch (event.key) {
            .escape, .enter => {
                self.mode = .normal;
            },
            .ctrl_s => {
                // Next match
                _ = self.panels[self.active_panel].quickSearchNext(self.search_buf[0..self.search_len]);
            },
            .backspace => {
                if (self.search_len > 0) {
                    self.search_len -= 1;
                    _ = self.panels[self.active_panel].quickSearch(self.search_buf[0..self.search_len]);
                }
            },
            .char => {
                if (self.search_len < self.search_buf.len and event.char < 128) {
                    self.search_buf[self.search_len] = @intCast(event.char);
                    self.search_len += 1;
                    _ = self.panels[self.active_panel].quickSearch(self.search_buf[0..self.search_len]);
                }
            },
            else => {},
        }
    }

    // --- File Operations ---

    fn openViewer(self: *App) void {
        const panel = &self.panels[self.active_panel];
        if (panel.getCurrentEntry()) |entry| {
            // Only open regular files and symlinks, not directories/sockets/pipes
            if (entry.kind != .file and entry.kind != .symlink) return;
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ panel.getPath(), entry.getName() }) catch return;
            self.viewer.open(path) catch return;
            self.mode = .viewer;
        }
    }

    fn openEditor(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const entry = panel.getCurrentEntry() orelse return;
        if (entry.kind != .file and entry.kind != .symlink) return;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ panel.getPath(), entry.getName() }) catch return;

        // Leave alternate screen and disable raw mode for editor
        self.terminal.leaveAltScreen() catch {};
        self.terminal.disableRawMode();

        // Get editor from config or environment
        const editor_env = std.posix.getenv("EDITOR");
        const editor = editor_env orelse self.config.getEditor();

        // Spawn editor
        const argv = [_][]const u8{ editor, path };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.spawn() catch {
            // Try fallback to vi
            const fallback = [_][]const u8{ "vi", path };
            var child2 = std.process.Child.init(&fallback, self.allocator);
            child2.stdin_behavior = .Inherit;
            child2.stdout_behavior = .Inherit;
            child2.stderr_behavior = .Inherit;
            child2.spawn() catch return;
            _ = child2.wait() catch {};
            self.terminal.enableRawMode() catch {};
            self.terminal.enterAltScreen() catch {};
            panel.loadDirectory(self.config.show_hidden) catch {};
            self.needs_full_redraw = true;
            return;
        };
        _ = child.wait() catch {};

        // Restore terminal
        self.terminal.enableRawMode() catch {};
        self.terminal.enterAltScreen() catch {};
        panel.loadDirectory(self.config.show_hidden) catch {};
        self.needs_full_redraw = true;
    }

    fn executeFile(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const entry = panel.getCurrentEntry() orelse return;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ panel.getPath(), entry.getName() }) catch return;

        self.runExternalCommand(&.{path}, panel.getPath());
    }

    fn executeShellCommand(self: *App) void {
        if (self.cmd_len == 0) return;

        const cmd_text = self.cmd_buf[0..self.cmd_len];
        const cwd = self.panels[self.active_panel].getPath();

        self.cmd_len = 0;
        self.cmd_cursor = 0;

        self.runExternalCommand(&.{ "/bin/sh", "-c", cmd_text }, cwd);
    }

    fn runExternalCommand(self: *App, argv: []const []const u8, cwd: []const u8) void {
        self.terminal.leaveAltScreen() catch {};
        self.terminal.disableRawMode();

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.cwd = cwd;
        child.spawn() catch |err| {
            const err_out = std.fs.File.stderr();
            var ebuf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&ebuf, "Failed to run: {s}\r\n", .{@errorName(err)}) catch "Failed to run command\r\n";
            err_out.writeAll(msg) catch {};
            waitForEnter();
            self.terminal.enableRawMode() catch {};
            self.terminal.enterAltScreen() catch {};
            self.needs_full_redraw = true;
            return;
        };
        _ = child.wait() catch {};

        waitForEnter();

        self.terminal.enableRawMode() catch {};
        self.terminal.enterAltScreen() catch {};
        self.panels[0].loadDirectory(self.config.show_hidden) catch {};
        self.panels[1].loadDirectory(self.config.show_hidden) catch {};
        self.needs_full_redraw = true;
    }

    fn waitForEnter() void {
        const out = std.fs.File.stderr();
        out.writeAll("\r\nPress Enter to continue...") catch {};
        const stdin = std.fs.File.stdin();
        var buf: [1]u8 = undefined;
        while (true) {
            const n = stdin.read(&buf) catch break;
            if (n == 0) break;
            if (buf[0] == 0x0d or buf[0] == 0x0a) break;
        }
    }

    fn startCopy(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const other = &self.panels[~self.active_panel];
        const sources = panel.getTaggedPaths(self.allocator) catch return;
        if (sources.len == 0) {
            self.allocator.free(sources);
            return;
        }

        const name = if (sources.len == 1) std.fs.path.basename(sources[0]) else "selected files";

        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Copy {s} to {s}?", .{ name, other.getPath() }) catch return;

        self.pending_operation = .{
            .kind = .copy,
            .sources = sources,
            .dest_dir = other.getPath(),
        };

        self.dialog = dialog_mod.Dialog.initConfirm("Copy", msg);
        self.mode = .dialog;
    }

    fn startMove(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const other = &self.panels[~self.active_panel];
        const sources = panel.getTaggedPaths(self.allocator) catch return;
        if (sources.len == 0) {
            self.allocator.free(sources);
            return;
        }

        const name = if (sources.len == 1) std.fs.path.basename(sources[0]) else "selected files";

        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Move {s} to {s}?", .{ name, other.getPath() }) catch return;

        self.pending_operation = .{
            .kind = .move,
            .sources = sources,
            .dest_dir = other.getPath(),
        };

        self.dialog = dialog_mod.Dialog.initConfirm("Move", msg);
        self.mode = .dialog;
    }

    fn startRename(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const entry = panel.getCurrentEntry() orelse return;
        const name = entry.getName();
        if (std.mem.eql(u8, name, "..")) return;

        self.dialog = dialog_mod.Dialog.initInput("Rename", name);
        self.pending_operation = .{
            .kind = .move,
        };
        self.mode = .dialog;
    }

    fn startMkdir(self: *App) void {
        self.dialog = dialog_mod.Dialog.initInput("Create directory", "");
        self.mode = .dialog;
    }

    fn startDelete(self: *App) void {
        const panel = &self.panels[self.active_panel];
        const sources = panel.getTaggedPaths(self.allocator) catch return;
        if (sources.len == 0) {
            self.allocator.free(sources);
            return;
        }

        const name = if (sources.len == 1) std.fs.path.basename(sources[0]) else "selected files";

        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Delete {s}?", .{name}) catch return;

        self.pending_operation = .{
            .kind = .delete,
            .sources = sources,
        };

        self.dialog = dialog_mod.Dialog.initConfirm("Delete", msg);
        self.mode = .dialog;
    }

    fn processDialogResult(self: *App, result: dialog_mod.DialogResult) void {
        if (self.dialog == null) return;
        const dlg = &self.dialog.?;

        switch (result) {
            .ok => {
                if (dlg.kind == .input) {
                    const input_text = dlg.getInput();
                    if (self.pending_operation) |po| {
                        if (po.kind == .move) {
                            // Rename operation
                            self.executeRename(input_text);
                        }
                    } else {
                        // Mkdir operation
                        self.executeMkdir(input_text);
                    }
                } else {
                    // Confirm dialog - execute pending operation
                    self.executePendingOp();
                }
            },
            .cancel => {},
            .overwrite, .overwrite_all => self.executePendingOp(),
            .skip => {}, // Skip this file
            .rename_choice => {}, // TODO: prompt for new name
            .none => return, // Don't close dialog
        }

        self.dialog = null;
        self.freePendingOp();
        self.mode = .normal;
        // Refresh panels
        self.panels[0].loadDirectory(self.config.show_hidden) catch {};
        self.panels[1].loadDirectory(self.config.show_hidden) catch {};
    }

    fn executePendingOp(self: *App) void {
        const po = self.pending_operation orelse return;

        for (po.sources) |src_path| {
            const basename = std.fs.path.basename(src_path);
            var dest_buf: [std.fs.max_path_bytes]u8 = undefined;

            switch (po.kind) {
                .copy => {
                    const dest = std.fmt.bufPrint(&dest_buf, "{s}/{s}", .{ po.dest_dir, basename }) catch continue;

                    // Check for conflicts
                    if (ops.fileExists(dest)) {
                        // For now, overwrite (conflict dialog to be triggered separately)
                    }

                    // Check if it's a directory
                    const stat = std.fs.openFileAbsolute(src_path, .{}) catch {
                        // Might be a directory
                        ops.copyDirectoryRecursive(src_path, dest, null) catch {
                            self.showError("Copy failed");
                        };
                        continue;
                    };
                    stat.close();
                    ops.copyFile(src_path, dest, null) catch {
                        self.showError("Copy failed");
                    };
                },
                .move => {
                    const dest = std.fmt.bufPrint(&dest_buf, "{s}/{s}", .{ po.dest_dir, basename }) catch continue;
                    ops.moveFile(src_path, dest, null) catch {
                        self.showError("Move failed");
                    };
                },
                .delete => {
                    ops.deleteFile(src_path) catch {
                        self.showError("Delete failed");
                    };
                },
            }
        }

        self.panels[self.active_panel].clearTags();
    }

    fn executeRename(self: *App, new_name: []const u8) void {
        if (new_name.len == 0) return;
        const panel = &self.panels[self.active_panel];
        const entry = panel.getCurrentEntry() orelse return;
        const old_name = entry.getName();

        var old_buf: [std.fs.max_path_bytes]u8 = undefined;
        var new_buf: [std.fs.max_path_bytes]u8 = undefined;
        const old_path = std.fmt.bufPrint(&old_buf, "{s}/{s}", .{ panel.getPath(), old_name }) catch return;
        const new_path = std.fmt.bufPrint(&new_buf, "{s}/{s}", .{ panel.getPath(), new_name }) catch return;

        ops.renameEntry(old_path, new_path) catch {
            self.showError("Rename failed");
        };
    }

    fn executeMkdir(self: *App, name: []const u8) void {
        if (name.len == 0) return;
        const panel = &self.panels[self.active_panel];

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ panel.getPath(), name }) catch return;

        ops.makeDirectory(path) catch {
            self.showError("Mkdir failed");
        };
    }

    fn showError(self: *App, message: []const u8) void {
        self.dialog = dialog_mod.Dialog.initError("Error", message);
        self.mode = .dialog;
    }

    // --- Menu System ---

    const left_menu = [_]MenuItem{
        .{ .label = "Sort by name", .action = .sort_name },
        .{ .label = "Sort by size", .action = .sort_size },
        .{ .label = "Sort by date", .action = .sort_date },
        .{ .label = "Sort by ext", .action = .sort_ext },
    };
    const file_menu = [_]MenuItem{
        .{ .label = "Refresh       Ctrl+R", .action = .refresh },
        .{ .label = "Quit            F10", .action = .quit },
    };
    const command_menu = [_]MenuItem{
        .{ .label = "Swap panels", .action = .swap_panels },
        .{ .label = "Equal panels", .action = .equal_panels },
    };
    const options_menu = [_]MenuItem{
        .{ .label = "Theme...         F9", .action = .theme },
        .{ .label = "Toggle hidden    .", .action = .toggle_hidden },
    };
    const right_menu = [_]MenuItem{
        .{ .label = "Sort by name", .action = .sort_name },
        .{ .label = "Sort by size", .action = .sort_size },
        .{ .label = "Sort by date", .action = .sort_date },
        .{ .label = "Sort by ext", .action = .sort_ext },
    };

    fn getMenuItems(self: *const App) []const MenuItem {
        return switch (self.menu_id) {
            .left => &left_menu,
            .file => &file_menu,
            .command => &command_menu,
            .options => &options_menu,
            .right => &right_menu,
        };
    }

    fn getMenuX(self: *const App) u16 {
        return switch (self.menu_id) {
            .left => 0,
            .file => 7,
            .command => 14,
            .options => 24,
            .right => 34,
        };
    }

    fn openMenu(self: *App, id: MenuId) void {
        self.menu_id = id;
        self.menu_cursor = 0;
        self.mode = .menu;
    }

    fn handleMenuInput(self: *App, event: input_mod.InputEvent) void {
        const items = self.getMenuItems();
        switch (event.key) {
            .up => {
                if (self.menu_cursor > 0) {
                    self.menu_cursor -= 1;
                } else {
                    self.menu_cursor = items.len - 1;
                }
            },
            .down => {
                if (self.menu_cursor < items.len - 1) {
                    self.menu_cursor += 1;
                } else {
                    self.menu_cursor = 0;
                }
            },
            .left => {
                // Switch to previous menu
                self.menu_id = switch (self.menu_id) {
                    .left => .right,
                    .file => .left,
                    .command => .file,
                    .options => .command,
                    .right => .options,
                };
                self.menu_cursor = 0;
            },
            .right => {
                // Switch to next menu
                self.menu_id = switch (self.menu_id) {
                    .left => .file,
                    .file => .command,
                    .command => .options,
                    .options => .right,
                    .right => .left,
                };
                self.menu_cursor = 0;
            },
            .enter => {
                self.executeMenuAction(items[self.menu_cursor].action);
            },
            .escape, .f9, .f2 => {
                self.mode = .normal;
                self.terminal.clear();
            },
            else => {},
        }
    }

    fn executeMenuAction(self: *App, action: MenuAction) void {
        self.mode = .normal;
        self.terminal.clear();
        switch (action) {
            .sort_name => {
                const target: u1 = if (self.menu_id == .right) 1 else 0;
                self.panels[target].sort_mode = .name;
                self.panels[target].loadDirectory(self.config.show_hidden) catch {};
            },
            .sort_size => {
                const target: u1 = if (self.menu_id == .right) 1 else 0;
                self.panels[target].sort_mode = .size;
                self.panels[target].loadDirectory(self.config.show_hidden) catch {};
            },
            .sort_date => {
                const target: u1 = if (self.menu_id == .right) 1 else 0;
                self.panels[target].sort_mode = .date;
                self.panels[target].loadDirectory(self.config.show_hidden) catch {};
            },
            .sort_ext => {
                const target: u1 = if (self.menu_id == .right) 1 else 0;
                self.panels[target].sort_mode = .extension;
                self.panels[target].loadDirectory(self.config.show_hidden) catch {};
            },
            .toggle_hidden => {
                self.config.show_hidden = !self.config.show_hidden;
                self.panels[0].loadDirectory(self.config.show_hidden) catch {};
                self.panels[1].loadDirectory(self.config.show_hidden) catch {};
            },
            .theme => {
                // Cycle to next theme
                self.theme_index = (self.theme_index + 1) % theme_mod.builtin_themes.len;
                self.applyTheme(self.theme_index);
                // Reopen options menu to show result
                self.mode = .menu;
                self.menu_id = .options;
                self.menu_cursor = 0;
            },
            .refresh => {
                self.panels[self.active_panel].loadDirectory(self.config.show_hidden) catch {};
            },
            .swap_panels => {
                const tmp_path = self.panels[0].path;
                const tmp_len = self.panels[0].path_len;
                self.panels[0].path = self.panels[1].path;
                self.panels[0].path_len = self.panels[1].path_len;
                self.panels[1].path = tmp_path;
                self.panels[1].path_len = tmp_len;
                self.panels[0].loadDirectory(self.config.show_hidden) catch {};
                self.panels[1].loadDirectory(self.config.show_hidden) catch {};
            },
            .equal_panels => {
                const src = &self.panels[self.active_panel];
                const dst = &self.panels[~self.active_panel];
                dst.setPath(src.getPath());
                dst.loadDirectory(self.config.show_hidden) catch {};
            },
            .quit => {
                self.running = false;
            },
        }
    }

    fn applyTheme(self: *App, idx: usize) void {
        if (idx >= theme_mod.builtin_themes.len) return;
        const t = &theme_mod.builtin_themes[idx];
        self.config.setThemeName(t.name);
        self.terminal.clear();
    }

    fn renderDropdownMenu(self: *App) void {
        const colors = self.config.colors;
        const items = self.getMenuItems();
        const x0 = self.getMenuX();
        const y0: u16 = 1; // Below menu bar

        // Find widest item
        var max_w: u16 = 0;
        for (items) |item| {
            const w: u16 = @intCast(item.label.len);
            if (w > max_w) max_w = w;
        }
        const menu_w = max_w + 4;
        const menu_h: u16 = @intCast(items.len + 2);

        // Top border
        self.terminal.setCell(x0, y0, .{ .char = 0x250C, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        self.terminal.setCell(x0 + menu_w - 1, y0, .{ .char = 0x2510, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        var bx: u16 = x0 + 1;
        while (bx < x0 + menu_w - 1) : (bx += 1) {
            self.terminal.setCell(bx, y0, .{ .char = 0x2500, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        }

        // Items
        for (items, 0..) |item, i| {
            const y = y0 + 1 + @as(u16, @intCast(i));
            const is_sel = (i == self.menu_cursor);
            const fg: theme_mod.Color = if (is_sel) colors.selected_fg else colors.dialog_fg;
            const bg: theme_mod.Color = if (is_sel) colors.selected_bg else colors.dialog_bg;

            self.terminal.setCell(x0, y, .{ .char = 0x2502, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
            self.terminal.setCell(x0 + menu_w - 1, y, .{ .char = 0x2502, .fg = colors.dialog_fg, .bg = colors.dialog_bg });

            var cx: u16 = x0 + 1;
            while (cx < x0 + menu_w - 1) : (cx += 1) {
                self.terminal.setCell(cx, y, .{ .char = ' ', .fg = fg, .bg = bg });
            }
            self.terminal.writeString(x0 + 2, y, item.label, fg, bg, is_sel);
        }

        // Bottom border
        const yb = y0 + menu_h - 1;
        self.terminal.setCell(x0, yb, .{ .char = 0x2514, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        self.terminal.setCell(x0 + menu_w - 1, yb, .{ .char = 0x2518, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        bx = x0 + 1;
        while (bx < x0 + menu_w - 1) : (bx += 1) {
            self.terminal.setCell(bx, yb, .{ .char = 0x2500, .fg = colors.dialog_fg, .bg = colors.dialog_bg });
        }

        // Highlight active menu bar item
        const label: []const u8 = switch (self.menu_id) {
            .left => " Left ",
            .file => " File ",
            .command => " Command ",
            .options => " Options ",
            .right => " Right ",
        };
        self.terminal.writeString(x0, 0, label, colors.selected_fg, colors.selected_bg, true);
    }

    fn togglePanels(self: *App) void {
        if (self.mode == .panel_hidden) {
            // Restore
            self.terminal.enterAltScreen() catch {};
            self.mode = .normal;
            self.needs_full_redraw = true;
            self.terminal.clear();
        } else {
            // Hide
            self.terminal.leaveAltScreen() catch {};
            self.mode = .panel_hidden;
        }
    }

    // --- Rendering ---

    fn renderFrame(self: *App) void {
        if (self.mode == .viewer) {
            self.viewer.render(&self.terminal, self.config.colors);
            return;
        }

        // Handle resize
        const new_layout = layout_mod.Layout.calculate(self.terminal.width, self.terminal.height);
        if (new_layout.term_width != self.layout.term_width or new_layout.term_height != self.layout.term_height) {
            self.layout = new_layout;
            self.terminal.handleResize() catch {};
            self.needs_full_redraw = true;
        }

        self.layout = layout_mod.Layout.calculate(self.terminal.width, self.terminal.height);
        const colors = self.config.colors;

        // Menu bar
        statusbar.renderMenuBar(&self.terminal, self.layout.menu_row, colors);

        // Panels
        self.panels[0].render(
            &self.terminal,
            self.layout.left_panel_x,
            self.layout.panel_top,
            self.layout.left_panel_width,
            self.layout.panel_height,
            colors,
        );

        self.panels[1].render(
            &self.terminal,
            self.layout.right_panel_x,
            self.layout.panel_top,
            self.layout.right_panel_width,
            self.layout.panel_height,
            colors,
        );

        // Hint line
        if (self.mode == .quick_search) {
            statusbar.renderQuickSearch(&self.terminal, self.layout.hint_row, self.search_buf[0..self.search_len], colors);
        } else {
            const hint = "Tab:Panel  F5:Copy  F6:Move  F7:Mkdir  F8:Del  F10:Quit  Ctrl+O:Toggle";
            statusbar.renderHintLine(&self.terminal, self.layout.hint_row, hint, colors);
        }

        // Command line
        statusbar.renderCommandLine(&self.terminal, self.layout.command_row, self.panels[self.active_panel].getPath(), self.cmd_buf[0..self.cmd_len], self.cmd_cursor, colors);

        // Function key bar
        statusbar.renderFKeyBar(&self.terminal, self.layout.fkey_row, colors);

        // Dialog overlay
        if (self.dialog) |*dlg| {
            dlg.render(&self.terminal, colors);
        }

        // Dropdown menu overlay
        if (self.mode == .menu) {
            self.renderDropdownMenu();
        }

        self.needs_full_redraw = false;
    }
};
