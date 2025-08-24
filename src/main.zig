const std = @import("std");
const log = std.log.scoped(.main);
const sdl = @import("sdl3");
const gl = @import("gl");
const shaders = @import("shaders.zig");
const gfx = @import("gfx.zig");
const debug_draw = @import("debug_draw.zig");
const la = @import("linear_algebra.zig");
const tiles = @import("tiles/tiles.zig");
const tile_data = @import("tiles/tile_data.zig");
const vec3 = la.vec3;
const vec4 = la.vec4;
const mat4 = la.mat4;
const mul = la.mul;

const enable_multisampling = false;

const input = struct {
    var mx: f32 = 0;
    var my: f32 = 0;
    var framedown: bool = false;
};

const Camera = struct {
    position: vec3 = @splat(0),
    phi: f32 = 0, // azimuth angle in degrees
    theta: f32 = 0, // polar angle in degrees

    fn view(self: *const Camera) mat4 {
        const sin_theta = @sin(std.math.degreesToRadians(self.theta));
        const cos_theta = @cos(std.math.degreesToRadians(self.theta));
        const sin_phi = @sin(std.math.degreesToRadians(self.phi));
        const cos_phi = @cos(std.math.degreesToRadians(self.phi));
        const view_dir: vec3 = .{ cos_theta * sin_phi, cos_theta * cos_phi, sin_theta };
        return la.look_at(self.position, self.position + view_dir, .{ 0, 0, 1 });
    }
};
var camera: Camera = .{};

const GLTile = struct {
    vbo: gl.uint,
    ebo: gl.uint,
    ibo: gl.uint,
    index_count: gl.sizei,
    instance_count: gl.sizei,
};

const Tile = packed struct(u8) {
    index: u6,
    rot: u2,
};
var tilemap: [64][64]Tile = undefined;

const tile_array = tile_data.tiles;
var gl_tiles: [tile_array.len]GLTile = undefined;
var tile_instance_data: [tile_array.len]std.ArrayList(vec4) = undefined;

fn update_instance_data() !void {
    for (&tile_instance_data) |*i| i.clearRetainingCapacity();
    for (0..tilemap.len) |row| {
        for (0..tilemap[row].len) |col| {
            const tile = tilemap[row][col];
            if (tile.index == 0) continue;
            try tile_instance_data[tile.index - 1].append(.{ @floatFromInt(col), @floatFromInt(row), 0, @floatFromInt(tile.rot) });
        }
    }

    for (&gl_tiles, &tile_instance_data) |*gl_tile, *instance_data| {
        gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.ibo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.DYNAMIC_DRAW);
        gl_tile.instance_count = @intCast(instance_data.items.len);
    }
}

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

    var procs: gl.ProcTable = undefined;
    _ = procs.init(struct {
        fn address(proc: [*:0]const u8) ?*align(4) const anyopaque {
            return @ptrCast(@alignCast(sdl.video.gl.getProcAddress(std.mem.sliceTo(proc, 0))));
        }
    }.address);
    gl.makeProcTableCurrent(&procs);

    // Set up reverse Z: https://tomhultonharrop.com/mathematics/graphics/2023/08/06/reverse-z.html
    gl.Enable(gl.DEPTH_TEST);
    gl.DepthFunc(gl.GREATER);
    gl.ClearDepth(0);

    // Blending
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // Culling
    // gl.Enable(gl.CULL_FACE);
    // gl.CullFace(gl.BACK);
    // gl.FrontFace(gl.CCW);

    // VAO is required for OpenGL core profile.
    var vao_dummy: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_dummy));
    gl.BindVertexArray(vao_dummy);

    tilemap = @splat(@splat(.{ .index = 1, .rot = 0 }));
    // do city block
    {
        const w = 8;
        const h = 8;
        const street_side = 2;
        const street_zebra = 3;
        const curb = 5;
        const curb_corner = 6;
        for (0..h) |y| {
            for (0..w) |x| {
                tilemap[28 + y][28 + x].index = 0;
            }
        }
        for (0..w) |x| {
            const street_tile: u6 = if (x == 0 or x == w - 1) street_zebra else street_side;
            tilemap[25][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[26][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[27][28 + x] = .{ .index = curb, .rot = 3 };
            tilemap[36][28 + x] = .{ .index = curb, .rot = 1 };
            tilemap[37][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[38][28 + x] = .{ .index = street_tile, .rot = 1 };
        }
        for (0..h) |y| {
            const street_tile: u6 = if (y == 0 or y == h - 1) street_zebra else street_side;
            tilemap[28 + y][25] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][26] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][27] = .{ .index = curb, .rot = 0 };
            tilemap[28 + y][36] = .{ .index = curb, .rot = 2 };
            tilemap[28 + y][37] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][38] = .{ .index = street_tile, .rot = 0 };
        }
        tilemap[27][27] = .{ .index = curb_corner, .rot = 3 };
        tilemap[27][36] = .{ .index = curb_corner, .rot = 2 };
        tilemap[36][36] = .{ .index = curb_corner, .rot = 1 };
        tilemap[36][27] = .{ .index = curb_corner, .rot = 0 };
    }

    // per tile instance data
    for (&tile_instance_data) |*i| i.* = .init(arena);
    for (0..tilemap.len) |row| {
        for (0..tilemap[row].len) |col| {
            const tile = tilemap[row][col];
            if (tile.index == 0) continue;
            try tile_instance_data[tile.index - 1].append(.{ @floatFromInt(col), @floatFromInt(row), 0, @floatFromInt(tile.rot) });
        }
    }

    var vbos: [gl_tiles.len]gl.uint = undefined;
    var ebos: [gl_tiles.len]gl.uint = undefined;
    var ibos: [gl_tiles.len]gl.uint = undefined;
    gl.GenBuffers(vbos.len, &vbos);
    gl.GenBuffers(ebos.len, &ebos);
    gl.GenBuffers(ibos.len, &ibos);
    for (&gl_tiles, tile_array, tile_instance_data, vbos, ebos, ibos) |*gl_tile, tile, instance_data, vbo, ebo, ibo| {
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(tile.vertex_data.len * @sizeOf(f32)), tile.vertex_data.ptr, gl.STATIC_DRAW);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(tile.index_data.len * @sizeOf(u16)), tile.index_data.ptr, gl.STATIC_DRAW);
        gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.STATIC_DRAW);
        gl_tile.* = .{
            .vbo = vbo,
            .ebo = ebo,
            .ibo = ibo,
            .index_count = @intCast(tile.index_data.len),
            .instance_count = @intCast(instance_data.items.len),
        };
    }

    var texture: gl.uint = undefined;
    gl.GenTextures(1, @ptrCast(&texture));
    gl.BindTexture(gl.TEXTURE_2D, texture);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, tiles.image.width, tiles.image.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, tiles.image.pixels);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    shaders.load();
    debug_draw.init();
    gfx.init(arena);

    camera.position = .{ 32 + 8, 32 - 8, 16 };
    camera.phi = -45;
    camera.theta = -55;

    var frame_arena_instance = std.heap.ArenaAllocator.init(gpa.allocator());
    defer frame_arena_instance.deinit();
    const frame_arena = frame_arena_instance.allocator();

    var ns_lastframe = sdl.timer.getNanosecondsSinceInit();
    mainloop: while (true) {
        const dt: f32 = blk: {
            const ns = sdl.timer.getNanosecondsSinceInit();
            const ns_delta: f64 = @floatFromInt(ns - ns_lastframe);
            ns_lastframe = ns;
            break :blk @floatCast(ns_delta / 1_000_000_000);
        };

        input.framedown = false;
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

        const key_state = sdl.keyboard.getState();
        const move_speed = 25;
        const angular_speed = 90;
        var move: vec4 = @splat(0);
        if (key_state[@intFromEnum(sdl.Scancode.d)]) move[0] += move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.a)]) move[0] -= move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.w)]) move[1] += move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.s)]) move[1] -= move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.e)]) move[2] += move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.q)]) move[2] -= move_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.right)]) camera.phi += angular_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.left)]) camera.phi -= angular_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.up)]) camera.theta += angular_speed * dt;
        if (key_state[@intFromEnum(sdl.Scancode.down)]) camera.theta -= angular_speed * dt;
        camera.position += la.vec3_from_vec4(la.mul_vector(la.rotation(-camera.phi, .{ 0, 0, 1 }), move));

        const window_size = try window.getSize();
        const pixel_size = try window.getSizeInPixels();

        // const projection = la.ortho(-6.4, 6.4, -3.6, 3.6, -100, 100);
        const aspect_ratio = f32_i(window_size.width) / f32_i(window_size.height);
        const projection = la.perspective(45, aspect_ratio, 0.1);
        const view = camera.view();

        // screen to world
        const cursor_pos = blk: {
            const ndc_near: vec4 = .{
                2 * input.mx / f32_i(window_size.width) - 1,
                1 - 2 * input.my / f32_i(window_size.height),
                -1,
                1,
            };
            const ndc_far: vec4 = .{ ndc_near[0], ndc_near[1], -ndc_near[2], ndc_near[3] };

            const inv = la.invert(mul(projection, view)).?;
            var world_near = la.mul_vector(inv, ndc_near);
            var world_far = la.mul_vector(inv, ndc_far);
            world_near /= @splat(world_near[3]); // div by w
            world_far /= @splat(world_far[3]); // div by w

            const origin = la.vec3_from_vec4(world_near);
            const dir = la.normalize(vec3, la.vec3_from_vec4(world_far - world_near));
            const t = -origin[2] / dir[2]; // intersect z = 0
            break :blk origin + @as(vec3, @splat(t)) * dir;
        };

        if (input.framedown) {
            const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
            const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));
            if (x >= 0 and x < 64 and y >= 0 and y < 64) {
                const row: usize = @intCast(y);
                const col: usize = @intCast(x);
                tilemap[row][col] = .{ .index = 4, .rot = 0 };
                try update_instance_data();
            }
        }

        gl.Viewport(0, 0, @intCast(pixel_size.width), @intCast(pixel_size.height));
        gl.ClearColor(0.2, 0.4, 0.6, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

        _ = frame_arena_instance.reset(.retain_capacity);
        const pixel_ratio = f32_i(pixel_size.width) / f32_i(window_size.width);
        gfx.begin_frame(frame_arena, pixel_ratio);

        gl.UseProgram(shaders.tile_shader.program);
        gl.BindTexture(gl.TEXTURE_2D, texture);
        gl.UniformMatrix4fv(shaders.tile_shader.projection_loc, 1, gl.FALSE, @ptrCast(&projection));
        gl.UniformMatrix4fv(shaders.tile_shader.view_loc, 1, gl.FALSE, @ptrCast(&view));
        gl.EnableVertexAttribArray(0);
        gl.EnableVertexAttribArray(1);
        gl.EnableVertexAttribArray(2);
        gl.EnableVertexAttribArray(3);
        gl.VertexAttribDivisor(3, 1);
        for (gl_tiles) |gl_tile| {
            gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.vbo);
            gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 0);
            gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 3 * @sizeOf(f32));
            gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 6 * @sizeOf(f32));
            gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.ibo);
            gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_tile.ebo);
            gl.DrawElementsInstanced(gl.TRIANGLES, gl_tile.index_count, gl.UNSIGNED_SHORT, null, gl_tile.instance_count);
        }

        {
            // draw cursor highlight quad
            gl.Disable(gl.DEPTH_TEST);
            defer gl.Enable(gl.DEPTH_TEST);

            debug_draw.begin(&projection, &view);
            const tile_x = @round(cursor_pos[0] - 0.5);
            const tile_y = @round(cursor_pos[1] - 0.5);
            const model = la.mul(la.translation(tile_x, tile_y, 0), la.scale(1, 1, 1));
            debug_draw.quad(&model);

            const ortho = la.ortho(0, f32_i(window_size.width), f32_i(window_size.height), 0, -1, 1);
            // const ortho = la.ortho(0, f32_i(window_size.width), 0, f32_i(window_size.height), -1, 1);
            gfx.begin(&ortho, &la.identity());
            gfx.set_color(.{ 0, 0, 0, 1 });
            gfx.transform(&la.scale(2, 2, 1));
            gfx.draw_text("Toolbox", 16, 16);
            gfx.transform(&la.identity());

            var box_path = try gfx.Path.init(frame_arena, 100);
            box_path.rect_rounded(16, 16, 160, 688, 8);
            gfx.set_color(.{ 0.95, 0.95, 0.95, 1 });
            try gfx.fill_path(&box_path);
            gfx.set_color(.{ 0, 0, 0, 1 });
            gfx.set_stroke_width(2);
            try gfx.stroke_path(&box_path);

            var path = try gfx.Path.init(frame_arena, 100);
            path.move_to(100, 100);
            path.line_to(200, 100);
            path.bezier_to(150, 100, 150, 200, 200, 200);
            path.line_to(100, 200);
            path.bezier_to(150, 200, 150, 100, 100, 100);
            path.close();
            gfx.set_color(.{ 1, 0, 0, 1 });
            try gfx.fill_path(&path);

            gfx.set_color(.{ 0, 0, 0, 1 });
            gfx.set_stroke_width(4);
            try gfx.stroke_path(&path);
        }

        try sdl.video.gl.swapWindow(window);
    }
}

fn f32_i(int: anytype) f32 {
    return @floatFromInt(int);
}
