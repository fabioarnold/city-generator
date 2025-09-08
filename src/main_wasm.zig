const std = @import("std");
const gl = @import("gl");
const webgl = @import("web/gl.zig");
const wasm = @import("web/wasm.zig");
const time = @import("time.zig");
const input = @import("input.zig");
const log = std.log.scoped(.main_wasm);
const assert = std.debug.assert;
const shaders = @import("shaders.zig");
const app = @import("app.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wasm.log,
};

var proc_table: gl.ProcTable = undefined;
fn gl_load_address(proc: [*:0]const u8) ?gl.PROC {
    const function_name: []const u8 = std.mem.sliceTo(proc, 0);
    if (webgl_functions.get(function_name)) |function| return function;
    // log.warn("gl function not defined: {s}", .{function_name});
    return null;
}

var webgl_functions: std.StringHashMap(gl.PROC) = undefined;
fn init_webgl_functions(allocator: std.mem.Allocator) !void {
    webgl_functions = .init(allocator);
    try webgl_functions.ensureTotalCapacity(@typeInfo(webgl).@"struct".decls.len);
    inline for (@typeInfo(webgl).@"struct".decls) |decl| {
        if (@typeInfo(@TypeOf(@field(webgl, decl.name))) == .@"fn") {
            webgl_functions.putAssumeCapacity(decl.name, &@field(webgl, decl.name));
        }
    }
}

var frame_arena_instance: std.heap.ArenaAllocator = undefined;

export fn on_init() callconv(.c) void {
    const allocator = std.heap.wasm_allocator;
    frame_arena_instance = std.heap.ArenaAllocator.init(allocator);

    init_webgl_functions(allocator) catch @panic("oom");
    _ = proc_table.init(gl_load_address);
    gl.makeProcTableCurrent(&proc_table);

    app.init(allocator) catch @panic("app init failed");

    t_prev = @floatCast(wasm.performance.now() / 1000.0);
}

export fn on_resize(width: c_uint, height: c_uint, scale: f32) callconv(.c) void {
    app.video_width = @floatFromInt(width);
    app.video_height = @floatFromInt(height);
    app.video_scale = scale;
    gl.Viewport(0, 0, @intFromFloat(scale * app.video_width), @intFromFloat(scale * app.video_height));
}

var t_prev: f32 = 0;
export fn on_animation_frame() callconv(.c) void {
    t_prev = time.seconds;
    time.seconds = @floatCast(wasm.performance.now() / 1000.0);
    time.dt = time.seconds - t_prev;

    gl.ClearColor(0.2, 0.4, 0.6, 1);
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
    // input.set_cursor(.auto);

    const frame_arena = frame_arena_instance.allocator();
    app.draw(frame_arena);

    input.end_frame();
}
