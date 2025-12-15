const std = @import("std");
const log = std.log.scoped(.app);
const gl = @import("gl");
const assets = @import("assets.zig");
const shaders = @import("shaders.zig");
const gfx = @import("gfx.zig");
const input = @import("input.zig");
const time = @import("time.zig");
const math = @import("math.zig");
const debug_draw = @import("debug_draw.zig");
const la = @import("linear_algebra.zig");
const vec3 = la.vec3;
const vec4 = la.vec4;
const mat4 = la.mat4;
const mul = la.mul;
const muln = la.muln;
const Model = @import("model.zig");
const GBuffer = @import("gbuffer.zig");
const primitives = @import("primitives.zig");

pub var video_width: f32 = 1280;
pub var video_height: f32 = 720;
pub var video_scale: f32 = 1;

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

const Tile = packed struct(u8) {
    index: u6,
    rot: u2,
};
var tilemap: [8][8]Tile = undefined;

var gbuffer: GBuffer = undefined;

const box_x = 32;
var box_y: f32 = 200;
const box_w = 184 + 12;
const box_h = 400;

var current_tile: Tile = .{ .index = 0, .rot = 0 };

pub fn init(arena: std.mem.Allocator) !void {
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
    gfx.init(arena);

    camera.position = .{ 0, 1, 0.7 };
    camera.phi = 60;
    camera.theta = -15;

    gbuffer = .init(640, 400);
    try gbuffer.create();

    const tiles = [_]Tile{
        .{ .index = 10, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 12, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 12, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 10, .rot = 2 },
        .{ .index = 9, .rot = 0 },
        .{ .index = 1, .rot = 3 },
        .{ .index = 5, .rot = 0 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 0 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 9, .rot = 0 },
        .{ .index = 6, .rot = 3 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 0 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 12, .rot = 0 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 13, .rot = 2 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 13, .rot = 2 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 12, .rot = 2 },
        .{ .index = 9, .rot = 0 },
        .{ .index = 3, .rot = 3 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 0 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 12, .rot = 0 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 13, .rot = 2 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 13, .rot = 2 },
        .{ .index = 9, .rot = 1 },
        .{ .index = 12, .rot = 2 },
        .{ .index = 9, .rot = 0 },
        .{ .index = 2, .rot = 3 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 0 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 1, .rot = 2 },
        .{ .index = 9, .rot = 2 },
        .{ .index = 10, .rot = 0 },
        .{ .index = 9, .rot = 3 },
        .{ .index = 12, .rot = 3 },
        .{ .index = 9, .rot = 3 },
        .{ .index = 12, .rot = 3 },
        .{ .index = 9, .rot = 3 },
        .{ .index = 9, .rot = 3 },
        .{ .index = 10, .rot = 3 },
    };

    for (&tilemap, 0..) |*row, y| {
        for (&row.*, 0..) |*tile, x| {
            tile.* = tiles[8 * y + x];
        }
    }
}

var key_down_r: bool = false;
var key_down_x: bool = false;

fn update() void {
    const move_speed = 10;
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
    camera.theta = std.math.clamp(camera.theta, -89, 89);
    camera.position += la.vec3_from_vec4(la.mul_vector(la.rotation(-camera.phi, .{ 0, 0, 1 }), move));

    box_y = video_height / 2 - box_h / 2;

    if (input.key_down(.r) and !key_down_r) {
        current_tile.rot +%= 1;
    }
    key_down_r = input.key_down(.r);

    if (input.key_down(.x) and !key_down_x) {
        dump_tilemap();
    }
    key_down_x = input.key_down(.x);
}

fn dump_tilemap() void {
    for (tilemap) |row| {
        for (row) |tile| {
            log.info("{any},", .{tile});
        }
    }
}

pub fn draw(frame_arena: std.mem.Allocator) void {
    update();

    const aspect_ratio = video_width / video_height;
    const projection = la.perspective(45, aspect_ratio, 0.1);
    // const scale: f32 = 10;
    // const projection = la.ortho(-aspect_ratio * scale, aspect_ratio * scale, -scale, scale, -100, 100);
    const view = camera.view();

    // screen to world
    const cursor_pos = blk: {
        const ndc_near: vec4 = .{
            2 * input.mx / video_width - 1,
            1 - 2 * input.my / video_height,
            -1,
            1,
        };
        const ndc_far: vec4 = .{ ndc_near[0], ndc_near[1], -ndc_near[2], ndc_near[3] };

        const inv = la.invert(mul(projection, view)) orelse break :blk vec3{ 0, 0, 0 };
        var world_near = la.mul_vector(inv, ndc_near);
        var world_far = la.mul_vector(inv, ndc_far);
        world_near /= @splat(world_near[3]); // div by w
        world_far /= @splat(world_far[3]); // div by w

        const origin = la.vec3_from_vec4(world_near);
        const dir = la.normalize(vec3, la.vec3_from_vec4(world_far - world_near));
        const t = -origin[2] / dir[2]; // intersect z = 0
        break :blk origin + @as(vec3, @splat(t)) * dir;
    };

    const tilepicker_hover = math.point_in_rect(input.mx, input.my, box_x, box_y, box_w, box_h);
    if (input.down and !tilepicker_hover) {
        const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
        const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));
        if (x >= 0 and x < tilemap[0].len and y >= 0 and y < tilemap.len) {
            const row: usize = @intCast(y);
            const col: usize = @intCast(x);
            tilemap[row][col] = current_tile;
        }
    }

    gfx.begin_frame(frame_arena, video_scale);

    {
        // draw to gbuffer at lower res
        {
            const width: u16 = @intFromFloat(video_scale * video_width);
            const height: u16 = @intFromFloat(video_scale * video_height);
            // gbuffer.resize(width / 8, height / 8);
            gbuffer.resize(width, height);

            gbuffer.begin();
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
            defer {
                gbuffer.end();
                gl.Viewport(0, 0, width, height);
            }

            gl.Enable(gl.DEPTH_TEST);
            draw_map(projection, view);
            gl.Disable(gl.DEPTH_TEST);
        }

        gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_color);
        gl.ActiveTexture(gl.TEXTURE1);
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_normal);
        gl.ActiveTexture(gl.TEXTURE2);
        gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_depth);
        gl.ActiveTexture(gl.TEXTURE0);
        gl.UseProgram(shaders.cavity.program);
        gl.Uniform2f(shaders.cavity.u_pixel, video_scale / f32_i(gbuffer.width), video_scale / f32_i(gbuffer.height));
        primitives.quad();
    }

    if (false) {
        // draw cursor highlight quad
        debug_draw.begin(&projection, &view);
        const tile_x = @round(cursor_pos[0] - 0.5);
        const tile_y = @round(cursor_pos[1] - 0.5);
        const model = la.mul(la.translation(tile_x, tile_y, 0), la.scale(1, 1, 1));
        debug_draw.quad(&model);
    }

    if (true) {
        const ortho = la.ortho(0, video_width, video_height, 0, -1000, 1000);
        gl.Clear(gl.DEPTH_BUFFER_BIT);
        // const ortho = la.ortho(0, video_width, 0, video_height, -1, 1);
        draw_tilepicker(frame_arena, ortho) catch @panic("oom");
    }
}

fn draw_map(projection: mat4, view: mat4) void {
    gl.UseProgram(shaders.default.program);
    gl.UniformMatrix4fv(shaders.default.u_projection, 1, gl.FALSE, @ptrCast(&projection));
    gl.UniformMatrix4fv(shaders.default.u_view, 1, gl.FALSE, @ptrCast(&view));
    const si: Model.ShaderInfo = .{ .model_loc = shaders.default.u_model };

    for (tilemap, 0..) |row, y| {
        for (row, 0..) |tile, x| {
            if (tile.index > 0) {
                const model = muln(&.{
                    la.translation(f32_i(x) + 0.5, f32_i(y) + 0.5, 0),
                    la.rotation(f32_i(tile.rot) * 90, .{ 0, 0, 1 }),
                    la.scale(0.5, 0.5, 0.5),
                });
                assets.model_tiles[tile.index - 1].draw(si, model);
            }
        }
    }
}

fn draw_tilepicker(frame_arena: std.mem.Allocator, projection: mat4) !void {
    gfx.begin(&projection, &la.identity());

    var box_path = try gfx.Path.init(frame_arena, 100);
    box_path.rect_rounded(box_x, box_y, box_w, box_h, 4);
    gfx.set_color(.{ 0.93, 0.91, 0.9, 1 });
    try gfx.fill_path(&box_path);
    gfx.set_color(.{ 0.3, 0.3, 0.3, 1 });
    gfx.set_stroke_width(2);
    try gfx.stroke_path(&box_path);

    gfx.transform(&la.mul(la.translation(box_x + 7, box_y, 0), la.scale(2, 2, 1)));
    gfx.set_color(.{ 0.3, 0.3, 0.3, 1 });
    var text_rot: [6]u8 = "rot: 0".*;
    text_rot[5] += current_tile.rot;
    gfx.draw_text(&text_rot, 8, 20);

    gfx.draw_text("TILE PICKER", 7, 7);
    gfx.draw_text("TILE PICKER", 7, 8);
    gfx.draw_text("TILE PICKER", 7, 9);
    gfx.draw_text("TILE PICKER", 9, 7);
    gfx.draw_text("TILE PICKER", 9, 8);
    gfx.draw_text("TILE PICKER", 9, 9);
    gfx.set_color(.{ 1, 1, 1, 1 });
    gfx.draw_text("TILE PICKER", 8, 8);
    gfx.transform(&la.identity());

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
            const x: f32 = box_x + f32_i(i % ncols) * (tile_width) + pad;
            var y: f32 = box_y + 64 + f32_i(i / ncols) * (tile_height + pad) + pad;
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

fn f32_i(int: anytype) f32 {
    return @floatFromInt(int);
}
