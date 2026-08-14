const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ft_lex",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const libl = b.addStaticLibrary(.{
        .name = "l",
        .target = target,
        .optimize = optimize,
    });
    libl.addCSourceFile(.{ .file = b.path("libl/libl.c"), .flags = &.{ "-std=c99" } });
    libl.linkLibC();
    b.installArtifact(libl);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run ft_lex");
    run_step.dependOn(&run_cmd.step);

    const unit = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit = b.addRunArtifact(unit);

    const check = b.addSystemCommand(&.{ "sh", "scripts/check.sh" });
    check.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_unit.step);
    test_step.dependOn(&check.step);
}
