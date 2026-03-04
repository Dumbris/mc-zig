const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get version from git describe, fallback to build.zig.zon version
    const version = b.option([]const u8, "version", "Override version string") orelse
        std.mem.trimRight(u8, b.run(&.{ "git", "describe", "--tags", "--always", "--dirty" }), "\n\r ");

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "mc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", build_options);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run mc");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.root_module.addOptions("build_options", build_options);

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
