const std = @import("std");
const log = std.log.scoped(.main);
const sdl = @import("sdl3");
const gl = @import("gl");
const shaders = @import("shaders.zig");
const gfx = @import("gfx.zig");
const input = @import("input.zig");
const time = @import("time.zig");
const math = @import("math.zig");
const debug_draw = @import("debug_draw.zig");
const la = @import("linear_algebra.zig");
const app = @import("app.zig");
const tiles = @import("tiles/tiles.zig");
const tile_data = @import("tiles/tile_data.zig");
const vec3 = la.vec3;
const vec4 = la.vec4;
const mat4 = la.mat4;
const mul = la.mul;
const muln = la.muln;

const enable_multisampling = false;

var procs: gl.ProcTable = undefined;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    var arena_instance: std.heap.ArenaAllocator = .init(gpa.allocator());
    const arena = arena_instance.allocator();

    try sdl.init(.{ .video = true });
    defer sdl.shutdown();

    const window = try sdl.video.Window.init("City", 1280, 720, .{ .open_gl = true, .resizable = true, .high_pixel_density = true });
    defer window.deinit();

    try sdl.video.gl.setAttribute(.context_minor_version, 1);
    try sdl.video.gl.setAttribute(.context_profile_mask, @intFromEnum(sdl.video.gl.Profile.core));
    try sdl.video.gl.setAttribute(.depth_size, 24);
    try sdl.video.gl.setAttribute(.stencil_size, 8);
    if (enable_multisampling) {
        try sdl.video.gl.setAttribute(.multi_sample_buffers, 1);
        try sdl.video.gl.setAttribute(.multi_sample_samples, 4);
    }
    const context = try sdl.video.gl.Context.init(window);
    defer context.deinit() catch {};

    try sdl.video.gl.setSwapInterval(.vsync);

    _ = procs.init(struct {
        fn address(proc: [*:0]const u8) ?*align(4) const anyopaque {
            return @ptrCast(@alignCast(sdl.video.gl.getProcAddress(std.mem.sliceTo(proc, 0))));
        }
    }.address);
    gl.makeProcTableCurrent(&procs);

    // VAO is required for OpenGL core profile.
    var vao_dummy: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_dummy));
    gl.BindVertexArray(vao_dummy);

    try app.init(arena);

    var frame_arena_instance = std.heap.ArenaAllocator.init(gpa.allocator());
    defer frame_arena_instance.deinit();
    const frame_arena = frame_arena_instance.allocator();

    var ns_lastframe = sdl.timer.getNanosecondsSinceInit();
    mainloop: while (true) {
        time.seconds = @floatCast(@as(f64, @floatFromInt(sdl.timer.getNanosecondsSinceInit())) / 1_000_000_000);
        time.dt = blk: {
            const ns = sdl.timer.getNanosecondsSinceInit();
            const ns_delta: f64 = @floatFromInt(ns - ns_lastframe);
            ns_lastframe = ns;
            break :blk @floatCast(ns_delta / 1_000_000_000);
        };

        defer {
            _ = frame_arena_instance.reset(.retain_capacity);
            input.end_frame();
        }

        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit => break :mainloop,
                .key_down => |key| if (key.key == .escape) break :mainloop,
                .mouse_motion => |mouse| {
                    input.mx = mouse.x;
                    input.my = mouse.y;
                },
                .mouse_button_down => |mouse| {
                    input.framedown = mouse.button == .left;
                },
                else => {},
            }
        }

        const mouse_state = sdl.mouse.getState();
        input.down = mouse_state.flags.left;

        const window_size = try window.getSize();
        const pixel_size = try window.getSizeInPixels();
        app.video_width = f32_i(window_size.width);
        app.video_height = f32_i(window_size.height);
        app.video_scale = f32_i(pixel_size.width) / f32_i(window_size.width);

        gl.Viewport(0, 0, @intCast(pixel_size.width), @intCast(pixel_size.height));
        gl.ClearColor(0.2, 0.4, 0.6, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

        app.draw(frame_arena);

        try sdl.video.gl.swapWindow(window);
    }
}

fn f32_i(int: anytype) f32 {
    return @floatFromInt(int);
}
