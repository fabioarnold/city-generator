const std = @import("std");
const log = std.log.scoped(.app);
const gl = @import("gl");
const assets = @import("assets.zig");
const shaders = @import("shaders.zig");
const gfx = @import("engine/gfx.zig");
const input = @import("engine/input.zig");
const time = @import("engine/time.zig");
const math = @import("engine/math.zig");
const builtin = @import("builtin");
const wasm = @import("engine/web/wasm.zig");
const debug_draw = @import("engine/debug_draw.zig");
const la = @import("engine/linear_algebra.zig");
const vec3 = la.vec3;
const vec4 = la.vec4;
const mat4 = la.mat4;
const mul = la.mul;
const muln = la.muln;
const Model = @import("engine/model.zig");
const GBuffer = @import("engine/gbuffer.zig");
const primitives = @import("engine/primitives.zig");

pub var video_width: f32 = 1280;
pub var video_height: f32 = 720;
pub var video_scale: f32 = 1;

const color_green_dark = vec3{ 0.34, 0.43, 0.14 };
const color_green_light = vec3{ 0.69, 0.78, 0.26 };

const Camera = struct {
    position: vec3 = @splat(0),
    phi: f32 = 0, // Azimuth angle in degrees.
    theta: f32 = 0, // Polar angle in degrees.

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

const tilemap_pkg = @import("tilemap.zig");
pub var tilemap: tilemap_pkg.TileMap = undefined;
var allocator: std.mem.Allocator = undefined;

var gbuffer: GBuffer = undefined;

var box = gfx.Rect{
    .x = 32,
    .y = 200,
    .w = 184 + 12,
    .h = 400,
};

var current_tile: tilemap_pkg.Tile = .{ .index = 0, .rot = 0 };

pub fn init(arena: std.mem.Allocator) !void {
    allocator = arena;
    // Set up reverse Z: https://tomhultonharrop.com/mathematics/graphics/2023/08/06/reverse-z.html
    gl.Enable(gl.DEPTH_TEST);
    gl.DepthFunc(gl.GREATER);
    const glClearDepth = if (@hasDecl(gl, "ClearDepth")) gl.ClearDepth else gl.ClearDepthf;
    glClearDepth(0);

    // Blending
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // Culling
    // gl.Enable(gl.CULL_FACE);
    // gl.CullFace(gl.BACK);
    // gl.FrontFace(gl.CCW);

    try assets.load(arena);
    try shaders.load();
    debug_draw.init();
    primitives.init();
    try gfx.init(arena);
    _ = try gfx.add_font(arena, @embedFile("fonts/Tomorrow-Medium.ttf"));
    _ = try gfx.add_font(arena, @embedFile("fonts/JetBrainsMono-Regular.ttf"));

    camera.position = .{ 0, -4, 25 };
    camera.phi = 0;
    camera.theta = 45;

    gbuffer = .init(640, 400);
    try gbuffer.create();

    tilemap = tilemap_pkg.TileMap.init(arena);

    if (builtin.cpu.arch.isWasm()) {
        tilemap.load_state() catch |err| log.err("Failed to load map: {}", .{err});
    }

    if (tilemap.chunks.count() == 0) {
        // Create a small starting map
        try tilemap.place_street(0, 0);
        try tilemap.place_street(1, 0);
        try tilemap.place_street(2, 0);
        try tilemap.place_street(2, 1);
        try tilemap.place_street(2, 2);
        try tilemap.place_street(1, 2);
        try tilemap.place_street(0, 2);
        try tilemap.place_street(0, 1);
        try tilemap.place_building(1, 1, prng.random());
    }

    center_camera_on_map();
}

pub fn save_state() !void {
    try tilemap.save_state();
}

pub fn center_camera_on_map() void {
    if (tilemap.get_bounds()) |bounds| {
        const cx = @as(f32, @floatFromInt(bounds.min_x + bounds.max_x)) / 2.0;
        const cy = @as(f32, @floatFromInt(bounds.min_y + bounds.max_y)) / 2.0;
        const size_x = @as(f32, @floatFromInt(bounds.max_x - bounds.min_x + 1));
        const size_y = @as(f32, @floatFromInt(bounds.max_y - bounds.min_y + 1));
        const max_size = @max(size_x, size_y);
        const dist = @max(15.0, max_size * 2.0);

        camera.theta = -35;
        camera.phi = 45;

        const sin_theta = @sin(std.math.degreesToRadians(camera.theta));
        const cos_theta = @cos(std.math.degreesToRadians(camera.theta));
        const sin_phi = @sin(std.math.degreesToRadians(camera.phi));
        const cos_phi = @cos(std.math.degreesToRadians(camera.phi));
        const view_dir: vec3 = .{ cos_theta * sin_phi, cos_theta * cos_phi, sin_theta };

        const origin: vec3 = .{ cx, cy, 0 };
        camera.position = origin - @as(vec3, @splat(dist)) * view_dir;
    }
}

var prng = std.Random.DefaultPrng.init(1234);

var key_down_r: bool = false;

fn update() void {
    const speed_multiplier: f32 = if (input.key_down(.shift)) 5.0 else 1.0;
    const move_speed = 1.0 * speed_multiplier;
    const angular_speed = 90;
    var move: vec4 = @splat(0);
    if (input.key_down(.d)) move[0] += move_speed * time.dt;
    if (input.key_down(.a)) move[0] -= move_speed * time.dt;
    if (input.key_down(.w)) move[1] += move_speed * time.dt;
    if (input.key_down(.s)) move[1] -= move_speed * time.dt;
    if (input.key_down(.e)) move[2] += move_speed * time.dt;
    if (input.key_down(.q)) move[2] -= move_speed * time.dt;
    if (input.key_down(.right)) camera.phi += angular_speed * time.dt;
    if (input.key_down(.left)) camera.phi -= angular_speed * time.dt;
    if (input.key_down(.up)) camera.theta += angular_speed * time.dt;
    if (input.key_down(.down)) camera.theta -= angular_speed * time.dt;

    if (input.right_down) {
        const sensitivity = 0.2;
        camera.phi += input.mouse_dx * sensitivity;
        camera.theta -= input.mouse_dy * sensitivity;
    }

    camera.theta = std.math.clamp(camera.theta, -89, 89);
    camera.position += la.vec3_from_vec4(la.mul_vector(la.rotation(-camera.phi, .{ 0, 0, 1 }), move));

    box.y = video_height / 2 - box.h / 2;

    if (input.key_down(.r) and !key_down_r) {
        current_tile.rot +%= 1;
    }
    key_down_r = input.key_down(.r);
}

pub fn draw(frame_arena: std.mem.Allocator) void {
    update();

    const aspect_ratio = video_width / video_height;
    const projection = la.perspective(45, aspect_ratio, 0.1);
    const view = camera.view();

    const cursor_pos = calculate_cursor_world_pos(projection, view);
    const tilepicker_hover = math.point_in_rect(input.mx, input.my, box.x, box.y, box.w, box.h);

    if (input.down and !tilepicker_hover) {
        handle_tile_placement(cursor_pos) catch |err| log.err("Failed to place tile: {}", .{err});
    }

    gfx.begin_frame(frame_arena, video_scale);
    draw_scene_to_gbuffer(projection, view, cursor_pos);
    draw_post_process();

    const ortho = la.ortho(0, video_width, video_height, 0, -1000, 1000);
    gl.Clear(gl.DEPTH_BUFFER_BIT);
    draw_tilepicker(frame_arena, ortho) catch @panic("Out of memory on tilepicker draw.");
}

fn calculate_cursor_world_pos(projection: mat4, view: mat4) vec3 {
    const ndc_near: vec4 = .{
        2 * input.mx / video_width - 1,
        1 - 2 * input.my / video_height,
        -1,
        1,
    };
    const ndc_far: vec4 = .{ ndc_near[0], ndc_near[1], -ndc_near[2], ndc_near[3] };

    const inv = la.invert(mul(projection, view)) orelse return vec3{ 0, 0, 0 };
    var world_near = la.mul_vector(inv, ndc_near);
    var world_far = la.mul_vector(inv, ndc_far);
    world_near /= @splat(world_near[3]); // Divide by w.
    world_far /= @splat(world_far[3]); // Divide by w.

    const origin = la.vec3_from_vec4(world_near);
    const dir = la.normalize(vec3, la.vec3_from_vec4(world_far - world_near));
    const t = -origin[2] / dir[2]; // Intersect z = 0.
    return origin + @as(vec3, @splat(t)) * dir;
}

fn handle_tile_placement(cursor_pos: vec3) !void {
    const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
    const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));

    const old_tile = tilemap.get_tile(x, y);
    if (current_tile.index == 0) {
        if (old_tile.index != 0) {
            const was_street = tilemap_pkg.is_street(old_tile.index);
            try tilemap.set_tile(x, y, .{});
            if (was_street) {
                // Update neighbors to recalculate their connections
                try tilemap.update_tile_autotiling(x, y + 1);
                try tilemap.update_tile_autotiling(x + 1, y);
                try tilemap.update_tile_autotiling(x, y - 1);
                try tilemap.update_tile_autotiling(x - 1, y);
            }
        }
        return;
    }

    if (tilemap_pkg.is_street(current_tile.index)) {
        if (!tilemap_pkg.is_street(old_tile.index)) try tilemap.place_street(x, y);
    } else if (tilemap_pkg.is_building(current_tile.index)) {
        if (!tilemap_pkg.is_building(old_tile.index)) try tilemap.place_building(x, y, prng.random());
    } else {
        if (old_tile.index != current_tile.index or old_tile.rot != current_tile.rot) {
            try tilemap.set_tile(x, y, current_tile);
        }
    }
}

fn draw_scene_to_gbuffer(projection: mat4, view: mat4, cursor_pos: vec3) void {
    const width: u16 = @intFromFloat(video_scale * video_width);
    const height: u16 = @intFromFloat(video_scale * video_height);
    gbuffer.resize(width, height);

    gbuffer.begin();
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    defer {
        gbuffer.end();
        gl.Viewport(0, 0, width, height);
    }

    gl.Enable(gl.DEPTH_TEST);
    draw_map(projection, view);
    draw_ghost_preview(cursor_pos);
    gl.Disable(gl.DEPTH_TEST);
}

fn draw_post_process() void {
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_color);
    gl.ActiveTexture(gl.TEXTURE1);
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_normal);
    gl.ActiveTexture(gl.TEXTURE2);
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_depth);
    gl.ActiveTexture(gl.TEXTURE0);
    gl.UseProgram(shaders.cavity.program);
    gl.Uniform2f(shaders.cavity.u_pixel, video_scale / i2f(gbuffer.width), video_scale / i2f(gbuffer.height));
    primitives.quad();
}

fn draw_map(projection: mat4, view: mat4) void {
    gl.UseProgram(shaders.default.program);
    gl.UniformMatrix4fv(shaders.default.u_projection, 1, gl.FALSE, @ptrCast(&projection));
    gl.UniformMatrix4fv(shaders.default.u_view, 1, gl.FALSE, @ptrCast(&view));
    const si: Model.ShaderInfo = .{ .model_loc = shaders.default.u_model };

    var iter = tilemap.chunks.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const chunk = entry.value_ptr.*;
        for (chunk.tiles, 0..) |row, ly| {
            for (row, 0..) |tile, lx| {
                if (tile.index > 0) {
                    const x: i32 = @as(i32, key.x) * tilemap_pkg.chunk_size + @as(i32, @intCast(lx));
                    const y: i32 = @as(i32, key.y) * tilemap_pkg.chunk_size + @as(i32, @intCast(ly));
                    const model = muln(&.{
                        la.translation(i2f(x) + 0.5, i2f(y) + 0.5, 0),
                        la.rotation(i2f(tile.rot) * 90, .{ 0, 0, 1 }),
                        la.scale(0.5, 0.5, 0.5),
                    });
                    assets.model_tiles[tile.index - 1].draw(si, model);
                }
            }
        }
    }

    const model = muln(&.{
        la.translation(0.15 + 0.5, 1 + 0.5, 0.07 * 0.5),
        la.rotation(180, .{ 0, 0, 1 }),
        la.scale(0.1, 0.1, 0.1),
    });
    assets.model_car_small.draw(si, model);
}

fn draw_ghost_preview(cursor_pos: vec3) void {
    if (current_tile.index == 0) return;

    const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
    const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));

    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE);
    // Use a simpler shader or just modulate alpha if possible.
    // The current shader might not support alpha transparency easily if it's deferred or specific.
    // But since we are drawing into gbuffer, it might be tricky.
    // Actually, gbuffer usually doesn't handle transparency well.
    // Let's draw it after gbuffer if we want true transparency,
    // OR just draw it into gbuffer with a special flag.
    // For now, let's just draw it into the gbuffer and see.

    const model = muln(&.{
        la.translation(i2f(x) + 0.5, i2f(y) + 0.5, 0.01),
        la.rotation(i2f(current_tile.rot) * 90, .{ 0, 0, 1 }),
        la.scale(0.5, 0.5, 0.5),
    });

    const si: Model.ShaderInfo = .{ .model_loc = shaders.default.u_model };
    assets.model_tiles[current_tile.index - 1].draw(si, model);

    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
}

fn draw_tilepicker(frame_arena: std.mem.Allocator, projection: mat4) !void {
    gfx.begin(&projection, &la.identity());

    var box_path = try gfx.Path.init(frame_arena, 100);
    box_path.rect_rounded(box, 4);
    gfx.set_color(.{ 0.93, 0.91, 0.9, 1 });
    gfx.fill_path(&box_path);
    gfx.set_color(.{ 0.3, 0.3, 0.3, 1 });
    gfx.set_stroke_width(2);
    gfx.stroke_path(&box_path);

    gfx.set_color(.{ 0, 0, 0, 1 });
    var text_rot: [6]u8 = "rot: 0".*;
    text_rot[5] += current_tile.rot;
    gfx.set_font_id(0);
    gfx.set_font_size(16);
    gfx.draw_text("TILE PICKER", box.x + 8, box.y + 8);
    gfx.draw_text(&text_rot, box.x + 8, box.y + 32);

    if (true) {
        gl.Enable(gl.DEPTH_TEST);
        defer gl.Disable(gl.DEPTH_TEST);

        // draw tiles on buttons
        gl.UseProgram(shaders.default.program);
        // gl.BindTexture(gl.TEXTURE_2D, tile_texture);
        gl.UniformMatrix4fv(shaders.default.u_projection, 1, gl.FALSE, @ptrCast(&projection));
        gl.UniformMatrix4fv(shaders.default.u_view, 1, gl.FALSE, @ptrCast(&la.identity()));

        gl.EnableVertexAttribArray(0);
        gl.EnableVertexAttribArray(1);
        gl.EnableVertexAttribArray(2);
        gl.DisableVertexAttribArray(3);
        const tile_width = 48;
        const tile_height = 32;
        const ncols = 3;
        const pad = 28;
        for (assets.model_tiles[0..], 0..) |*tile, i| {
            const x: f32 = box.x + i2f(i % ncols) * (tile_width) + pad;
            var y: f32 = box.y + 64 + i2f(i / ncols) * (tile_height + pad) + pad;
            if ((i % ncols) == 1) y += (tile_height + pad) / 2;
            const hover = math.point_in_rect(input.mx, input.my, x, y, tile_width, tile_width);
            const scale: f32 = if (hover) 0.6 else 0.5;
            const iso = muln(&.{
                la.scale(-scale, scale, scale),
                la.rotation(45, .{ 1, 0, 0 }),
                la.rotation(if (hover) time.seconds * 360 else 225, .{ 0, 0, 1 }),
            });
            const model = muln(&.{
                la.translation(x + 24, y + 16, -32),
                iso,
                la.scale(tile_width, tile_width, tile_width),
            });
            tile.draw(.{ .model_loc = shaders.default.u_model }, model);

            if (input.framedown and hover) {
                current_tile.index = @intCast(i + 1);
            }
        }
    }
}

// Short helper function to make the code more readable.
fn i2f(int: anytype) f32 {
    return @floatFromInt(int);
}
