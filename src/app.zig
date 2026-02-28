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
const traffic_pkg = @import("traffic.zig");

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
var traffic_sim: traffic_pkg.Simulation = undefined;
var allocator: std.mem.Allocator = undefined;

var gbuffer: GBuffer = undefined;

var toolbar_rect: gfx.Rect = .{
    .x = 0,
    .y = 0,
    .w = 0,
    .h = 0,
};

var current_tile: tilemap_pkg.Tile = .{ .index = 0, .rot = 0 };
var current_building_type: u3 = 0;
const Tool = enum(u2) {
    bulldozer,
    building,
    road,
    park,
};
var selected_tool: ?Tool = null;

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
    traffic_sim = traffic_pkg.Simulation.init(arena);

    var loaded = false;
    if (builtin.cpu.arch.isWasm()) {
        const size = wasm.js_get_state_size();
        if (size > 0) {
            const buf = try arena.alloc(u8, size);
            wasm.js_read_state(buf);
            var fbs = std.io.fixedBufferStream(buf);
            const reader = fbs.reader();

            var cam_bytes: [@sizeOf(vec3) + @sizeOf(f32) * 2]u8 = undefined;
            try reader.readNoEof(&cam_bytes);
            camera.position = std.mem.bytesToValue(vec3, cam_bytes[0..@sizeOf(vec3)]);
            camera.phi = std.mem.bytesToValue(f32, cam_bytes[@sizeOf(vec3)..][0..4]);
            camera.theta = std.mem.bytesToValue(f32, cam_bytes[@sizeOf(vec3) + 4 ..][0..4]);

            try tilemap.load(reader);
            loaded = true;
        }
    }

    if (!loaded) {
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

    try traffic_sim.rebuild_from_tilemap(&tilemap);
}

pub fn save_state() !void {
    var out_list = std.ArrayList(u8).empty;
    defer out_list.deinit(allocator);
    const writer = out_list.writer(allocator);

    try writer.writeAll(std.mem.asBytes(&camera.position));
    try writer.writeAll(std.mem.asBytes(&camera.phi));
    try writer.writeAll(std.mem.asBytes(&camera.theta));

    try tilemap.save(writer);

    if (builtin.cpu.arch.isWasm()) {
        wasm.js_save_state(out_list.items);
    }
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

    if (input.key_down(.r) and !key_down_r) {
        current_tile.rot +%= 1;
    }
    key_down_r = input.key_down(.r);

    traffic_sim.update(time.dt);
}

pub fn draw(frame_arena: std.mem.Allocator) void {
    update();

    const aspect_ratio = video_width / video_height;
    const projection = la.perspective(45, aspect_ratio, 0.1);
    const view = camera.view();

    const cursor_pos = calculate_cursor_world_pos(projection, view);
    const toolbar_hover = math.point_in_rect(input.mx, input.my, toolbar_rect.x, toolbar_rect.y, toolbar_rect.w, toolbar_rect.h);

    if (input.down and !toolbar_hover) {
        handle_tile_placement(cursor_pos) catch |err| log.err("Failed to place tile: {}", .{err});
    }

    gfx.begin_frame(frame_arena, video_scale);
    draw_scene_to_gbuffer(projection, view, cursor_pos);
    draw_post_process();
    traffic_sim.draw_debug_paths(projection, view);

    const ortho = la.ortho(0, video_width, video_height, 0, -1000, 1000);
    gl.Clear(gl.DEPTH_BUFFER_BIT);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    draw_toolbar(frame_arena, ortho) catch @panic("Out of memory on toolbar draw.");
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
    if (selected_tool == null) return;

    const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
    const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));
    var changed = false;

    const old_tile = tilemap.get_tile(x, y);
    switch (selected_tool.?) {
        .bulldozer => {
            if (old_tile.index != 0) {
                const was_street = tilemap_pkg.is_street(old_tile.index);
                try tilemap.set_tile(x, y, .{});
                changed = true;
                if (was_street) {
                    // Update neighbors to recalculate their connections
                    try tilemap.update_tile_autotiling(x, y + 1);
                    try tilemap.update_tile_autotiling(x + 1, y);
                    try tilemap.update_tile_autotiling(x, y - 1);
                    try tilemap.update_tile_autotiling(x - 1, y);
                }
            }
        },
        .road => {
            if (!tilemap_pkg.is_street(old_tile.index)) {
                try tilemap.place_street(x, y);
                changed = true;
            }
        },
        .building => {
            if (old_tile.index == 0 or tilemap_pkg.is_building(old_tile.index)) {
                var tile = current_tile;
                tile.rot = tilemap.get_building_orientation(x, y);
                try tilemap.set_tile(x, y, tile);
                changed = true;

                // Randomize for next placement
                current_building_type = prng.random().int(u3);
                current_tile.index = assets.tile_building_a + current_building_type;
            }
        },
        .park => {
            if (!tilemap_pkg.is_park(old_tile.index)) {
                try tilemap.place_park(x, y);
                changed = true;
            }
        },
    }

    if (changed) try traffic_sim.rebuild_from_tilemap(&tilemap);
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

    // Draw background
    gl.Disable(gl.DEPTH_TEST);
    draw_background(view, 45.0, la.normalize(vec3, .{ 1.0, 1.0, 1.0 }));

    gl.Enable(gl.DEPTH_TEST);
    draw_map(projection, view, cursor_pos);
    draw_ghost_preview(projection, view, cursor_pos);
    gl.Disable(gl.DEPTH_TEST);
}

fn draw_background(view: mat4, fov: f32, sun_pos: vec3) void {
    gl.UseProgram(shaders.background.program);
    gl.UniformMatrix4fv(shaders.background.u_view, 1, gl.FALSE, @ptrCast(&view));
    gl.Uniform1f(shaders.background.u_fov, fov);
    gl.Uniform2f(shaders.background.u_resolution, video_width * video_scale, video_height * video_scale);
    gl.Uniform3f(shaders.background.u_sun_pos, sun_pos[0], sun_pos[1], sun_pos[2]);

    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, assets.tex_grass);
    gl.Uniform1i(shaders.background.u_grass_tex, 0);

    primitives.quad();
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

fn draw_map(projection: mat4, view: mat4, cursor_pos: vec3) void {
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

                    const is_hovered = x == @as(i32, @intFromFloat(@round(cursor_pos[0] - 0.5))) and y == @as(i32, @intFromFloat(@round(cursor_pos[1] - 0.5)));
                    if (selected_tool != null and is_hovered) {
                        continue;
                    }

                    const model = muln(&.{
                        la.translation(i2f(x) + 0.5, i2f(y) + 0.5, 0),
                        la.rotation(i2f(tile.rot) * 90, .{ 0, 0, 1 }),
                        la.scale(0.5, 0.5, 0.5),
                    });
                    if (tile.index > 0 and tile.index <= assets.tile_node_indices.len) {
                        assets.citykit_model.drawNode(si, model, assets.tile_node_indices[tile.index - 1]);
                    }
                }
            }
        }
    }

    traffic_sim.draw(projection, view);
}

fn draw_ghost_preview(projection: mat4, view: mat4, cursor_pos: vec3) void {
    if (selected_tool == null) return;

    const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
    const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));

    var target_tile = current_tile;
    var preview_color: [4]f32 = .{ 1.0, 1.0, 1.0, 0.5 };

    switch (selected_tool.?) {
        .bulldozer => {
            // If delete tool, use the old tile but tinted red.
            const old_tile = tilemap.get_tile(x, y);
            if (old_tile.index == 0) return; // Nothing to delete.
            target_tile = old_tile;
            preview_color = .{ 1.0, 0.0, 0.0, 0.5 };
        },
        .building => {
            target_tile.rot = tilemap.get_building_orientation(x, y);
        },
        .road => {
            target_tile = tilemap.get_street_autotile(x, y);
        },
        .park => {
            preview_color = .{ 0.2, 0.8, 0.2, 0.5 };
        },
    }

    // Disable color write for depth pre-pass
    gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
    gl.DepthFunc(gl.GREATER); // Reverse Z

    const model = muln(&.{
        la.translation(i2f(x) + 0.5, i2f(y) + 0.5, 0.0),
        la.rotation(i2f(target_tile.rot) * 90, .{ 0, 0, 1 }),
        la.scale(0.5, 0.5, 0.5),
    });

    const si: Model.ShaderInfo = .{ .model_loc = shaders.default.u_model };
    if (target_tile.index > 0 and target_tile.index <= assets.tile_node_indices.len) {
        assets.citykit_model.drawNode(si, model, assets.tile_node_indices[target_tile.index - 1]);
    }

    // Re-enable color write, set depth to EQUAL, enable blending
    gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);
    gl.DepthFunc(gl.EQUAL);
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    gl.UseProgram(shaders.ghost.program);
    gl.Uniform4f(shaders.ghost.u_tint, preview_color[0], preview_color[1], preview_color[2], preview_color[3]);

    gl.UniformMatrix4fv(shaders.ghost.u_projection, 1, gl.FALSE, @ptrCast(&projection));
    gl.UniformMatrix4fv(shaders.ghost.u_view, 1, gl.FALSE, @ptrCast(&view));

    const si_ghost: Model.ShaderInfo = .{ .model_loc = shaders.ghost.u_model };
    if (target_tile.index > 0 and target_tile.index <= assets.tile_node_indices.len) {
        assets.citykit_model.drawNode(si_ghost, model, assets.tile_node_indices[target_tile.index - 1]);
    }

    // Restore state
    gl.UseProgram(shaders.default.program);
    gl.DepthFunc(gl.GREATER);
    gl.Disable(gl.BLEND);
}

fn draw_toolbar(_: std.mem.Allocator, projection: mat4) !void {
    const num_tools = 4;
    const tile_width: f32 = 64;
    const pad: f32 = 6;
    const gap: f32 = 4;
    const box_w: f32 = num_tools * tile_width + (num_tools - 1) * gap + 2 * pad; // +4 for border
    const box_h: f32 = tile_width + 2 * pad;
    toolbar_rect = .{
        .x = video_width / 2.0 - box_w / 2.0,
        .y = video_height - box_h, // Flush to bottom
        .w = box_w,
        .h = box_h,
    };

    gfx.begin(&projection, &la.identity());

    // Windows 2000 Colors
    const color_face = gfx.Color{ 0.75, 0.75, 0.75, 1.0 }; // #C0C0C0
    const color_light = gfx.Color{ 1.0, 1.0, 1.0, 1.0 };
    const color_shadow = gfx.Color{ 0.5, 0.5, 0.5, 1.0 };
    const color_dark = gfx.Color{ 0.0, 0.0, 0.0, 1.0 };

    // Draw Main Toolbar Box
    gfx.set_color(color_face);
    gfx.fill_rect(toolbar_rect);

    // Toolbar Outer Bevel
    // Top & Left (Light)
    gfx.set_color(color_light);
    gfx.fill_rect(.{ .x = toolbar_rect.x, .y = toolbar_rect.y, .w = toolbar_rect.w, .h = 1 });
    gfx.fill_rect(.{ .x = toolbar_rect.x, .y = toolbar_rect.y, .w = 1, .h = toolbar_rect.h });
    // Bottom & Right (Shadow)
    gfx.set_color(color_shadow);
    gfx.fill_rect(.{ .x = toolbar_rect.x, .y = toolbar_rect.y + toolbar_rect.h - 1, .w = toolbar_rect.w, .h = 1 });
    gfx.fill_rect(.{ .x = toolbar_rect.x + toolbar_rect.w - 1, .y = toolbar_rect.y, .w = 1, .h = toolbar_rect.h });

    const active_index: ?usize = if (selected_tool) |tool| switch (tool) {
        .bulldozer => 0,
        .building => 1,
        .road => 2,
        .park => 3,
    } else null;
    var new_active_index = active_index;
    var changed_selection = false;

    const icon_textures = [_]gl.uint{
        assets.tex_bulldozer,
        assets.tex_buildings,
        assets.tex_streets,
        assets.tex_park,
    };

    for (0..4) |i| {
        const cx = toolbar_rect.x + pad + i2f(i) * (tile_width + gap);
        const cy = toolbar_rect.y + pad;
        const hover = math.point_in_rect(input.mx, input.my, cx, cy, tile_width, tile_width);

        if (hover and input.framedown) {
            changed_selection = true;
            if (active_index != null and active_index.? == i) {
                new_active_index = null;
            } else {
                new_active_index = i;
            }
        }

        const pressed = active_index != null and active_index.? == i;

        // Draw Button Bevel
        if (pressed) {
            // Sunken Look
            // Top & Left (Dark)
            gfx.set_color(color_dark);
            gfx.fill_rect(.{ .x = cx, .y = cy, .w = tile_width, .h = 1 });
            gfx.fill_rect(.{ .x = cx, .y = cy, .w = 1, .h = tile_width });
            // Inner Top & Left (Shadow)
            gfx.set_color(color_shadow);
            gfx.fill_rect(.{ .x = cx + 1, .y = cy + 1, .w = tile_width - 1, .h = 1 });
            gfx.fill_rect(.{ .x = cx + 1, .y = cy + 1, .w = 1, .h = tile_width - 1 });
            // Bottom & Right (Light)
            gfx.set_color(color_light);
            gfx.fill_rect(.{ .x = cx, .y = cy + tile_width - 1, .w = tile_width, .h = 1 });
            gfx.fill_rect(.{ .x = cx + tile_width - 1, .y = cy, .w = 1, .h = tile_width });
        } else {
            // Raised Look
            // Top & Left (Light)
            gfx.set_color(color_light);
            gfx.fill_rect(.{ .x = cx, .y = cy, .w = tile_width, .h = 1 });
            gfx.fill_rect(.{ .x = cx, .y = cy, .w = 1, .h = tile_width });
            // Bottom & Right (Dark)
            gfx.set_color(color_dark);
            gfx.fill_rect(.{ .x = cx, .y = cy + tile_width - 1, .w = tile_width, .h = 1 });
            gfx.fill_rect(.{ .x = cx + tile_width - 1, .y = cy, .w = 1, .h = tile_width });
            // Inner Bottom & Right (Shadow)
            gfx.set_color(color_shadow);
            gfx.fill_rect(.{ .x = cx + 1, .y = cy + tile_width - 2, .w = tile_width - 2, .h = 1 });
            gfx.fill_rect(.{ .x = cx + tile_width - 2, .y = cy + 1, .w = 1, .h = tile_width - 2 });
        }

        // Icon
        const icon_padding: f32 = 4;
        const icon_size = tile_width - 2 * icon_padding;
        const offset: f32 = if (pressed) 1.0 else 0.0;

        if (hover and !pressed) {
            gfx.set_color(.{ 1.2, 1.2, 1.2, 1.0 });
        } else {
            gfx.set_color(.{ 1, 1, 1, 1 });
        }

        const icon_rect = gfx.Rect{ .x = cx + icon_padding + offset, .y = cy + icon_padding + offset, .w = icon_size, .h = icon_size };
        gfx.set_texture(icon_textures[i], icon_rect);
        gfx.fill_rect(icon_rect);
        gfx.set_texture(0, .zero);
    }

    if (changed_selection) {
        if (new_active_index) |idx| {
            selected_tool = switch (idx) {
                0 => .bulldozer,
                1 => .building,
                2 => .road,
                3 => .park,
                else => unreachable,
            };
        } else {
            selected_tool = null;
        }
    }

    if (selected_tool) |tool| {
        switch (tool) {
            .bulldozer => current_tile.index = 0,
            .building => current_tile.index = assets.tile_building_a + current_building_type,
            .road => current_tile.index = assets.tile_road_straight,
            .park => current_tile.index = 14, // Park
        }
    }
}

// Short helper function to make the code more readable.
fn i2f(int: anytype) f32 {
    return @floatFromInt(int);
}
