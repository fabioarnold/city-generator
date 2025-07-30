const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl3 = b.dependency("sdl3", .{ .target = target, .optimize = optimize });
    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{},
    });

    const exe = b.addExecutable(.{
        .name = "city",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl3", .module = sdl3.module("sdl3") },
                .{ .name = "gl", .module = gl_bindings },
            },
        }),
    });
    // exe.use_llvm = false;

    b.installArtifact(exe);
}
