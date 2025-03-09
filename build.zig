const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const okredis = b.addModule("okredis", .{
        .root_source_file = b.path("src/root.zig"),
    });
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    b.default_step.dependOn(&run_lib_unit_tests.step);

    const docs_step = b.step("docs", "Emit docs");

    const docs_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = lib_unit_tests.getEmittedDocs(),
    });

    docs_step.dependOn(&docs_install.step);
    b.default_step.dependOn(docs_step);

    // example
    const example_step = b.step("example", "Build example");
    const simple_example = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("example.zig"),
    });
    simple_example.root_module.addImport("okredis", okredis);
    const example_install = b.addInstallArtifact(simple_example, .{});
    example_step.dependOn(&example_install.step);
    b.default_step.dependOn(example_step);

    const run_example = b.addRunArtifact(simple_example);

    run_example.step.dependOn(b.getInstallStep());

    const run_step = b.step("run-example", "Run the example");
    run_step.dependOn(&run_example.step);
}
