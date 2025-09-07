const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.cpu.arch.isWasm()) {
        try build_wasm(b, target, optimize);
    } else {
        try build_native(b, target, optimize);
    }
}

fn build_wasm(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gles,
        .version = .@"3.0",
        .extensions = &.{},
    });
    const wasm = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_wasm.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gl", .module = gl_bindings },
            },
        }),
    });
    wasm.rdynamic = true;
    wasm.entry = .disabled;
    b.installArtifact(wasm);

    b.installDirectory(.{
        .source_dir = b.path("public"),
        .install_subdir = ".",
        .install_dir = .{ .custom = "." },
    });
}

fn build_native(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
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
            .root_source_file = b.path("src/main_sdl.zig"),
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
