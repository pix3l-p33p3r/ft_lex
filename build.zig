const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build libl as a static library
    const libl = b.addStaticLibrary(.{
        .name = "l",
        .root_source_file = .{ .path = "libl/src/libl.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Install libl headers
    const install_headers = b.addInstallFileWithDir(
        .{ .path = "libl/include/libl.h" },
        .header,
        "libl.h"
    );
    libl.step.dependOn(&install_headers.step);

    // Make libl available to other targets
    const libl_module = b.addModule("libl", .{
        .source_file = .{ .path = "libl/src/libl.zig" },
    });

    // Build ft_lex executable
    const exe = b.addExecutable(.{
        .name = "ft_lex",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("libl", libl_module);
    exe.linkLibrary(libl);
    b.installArtifact(exe);
    b.installArtifact(libl);

    // Add tests
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
