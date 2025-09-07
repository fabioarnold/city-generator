const std = @import("std");
const gl = @import("gl");
const shaders = @import("shaders.zig");
const gfx = @import("gfx.zig");
const input = @import("input.zig");
const time = @import("time.zig");
const math = @import("math.zig");
const debug_draw = @import("debug_draw.zig");
const la = @import("linear_algebra.zig");
const tiles = @import("tiles/tiles.zig");
const tile_data = @import("tiles/tile_data.zig");
const vec3 = la.vec3;
const vec4 = la.vec4;
const mat4 = la.mat4;
const mul = la.mul;
const muln = la.muln;

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

const GLBuilding = struct {
    vbo: gl.uint,
    ebo: gl.uint,
    ibo: gl.uint,
    index_count: gl.sizei,
    instance_count: gl.sizei,
};
const building_array = tile_data.buildings;
var gl_buildings: [building_array.len]GLBuilding = undefined;
var building_instance_data: [building_array.len]std.array_list.Managed(vec4) = undefined;

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
var tile_texture: gl.uint = undefined;
var gl_tiles: [tile_array.len]GLTile = undefined;
var tile_instance_data: [tile_array.len]std.array_list.Managed(vec4) = undefined;

const box_x = 16;
const box_y = 16;
const box_w = 168;
const box_h = 688;

var current_tile: Tile = .{ .index = 0, .rot = 0 };

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

    for (&gl_buildings, &building_instance_data) |*gl_building, *instance_data| {
        gl.BindBuffer(gl.ARRAY_BUFFER, gl_building.ibo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.DYNAMIC_DRAW);
        gl_building.instance_count = @intCast(instance_data.items.len);
    }
}

pub fn init(arena: std.mem.Allocator) !void {
    // Set up reverse Z: https://tomhultonharrop.com/mathematics/graphics/2023/08/06/reverse-z.html
    gl.Enable(gl.DEPTH_TEST);
    gl.DepthFunc(gl.GREATER);
    if (std.meta.hasFn(gl, "ClearDepth")) {
        gl.ClearDepth(0); // GL
    } else {
        gl.ClearDepthf(0); // GL ES
    }

    // Blending
    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // Culling
    // gl.Enable(gl.CULL_FACE);
    // gl.CullFace(gl.BACK);
    // gl.FrontFace(gl.CCW);

    try shaders.load();
    debug_draw.init();
    gfx.init(arena);

    camera.position = .{ 32 - 12, 32 - 12, 12 };
    camera.phi = 45;
    camera.theta = -30;

    tilemap = @splat(@splat(.{ .index = 1, .rot = 0 }));
    // do city block
    {
        const w = 9;
        const h = 9;
        const street_side = 2;
        const street_zebra = 3;
        const curb = 5;
        const curb_center = 6;
        const curb_corner = 7;
        for (0..h) |y| {
            for (0..w) |x| {
                tilemap[28 + y][28 + x].index = curb_center;
            }
        }
        for (0..w) |x| {
            const street_tile: u6 = if (x == 0 or x == w - 1) street_zebra else street_side;
            tilemap[25][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[26][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[27][28 + x] = .{ .index = curb, .rot = 3 };
            tilemap[28 + h][28 + x] = .{ .index = curb, .rot = 1 };
            tilemap[29 + h][28 + x] = .{ .index = street_tile, .rot = 1 };
            tilemap[30 + h][28 + x] = .{ .index = street_tile, .rot = 1 };
        }
        for (0..h) |y| {
            const street_tile: u6 = if (y == 0 or y == h - 1) street_zebra else street_side;
            tilemap[28 + y][25] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][26] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][27] = .{ .index = curb, .rot = 0 };
            tilemap[28 + y][28 + w] = .{ .index = curb, .rot = 2 };
            tilemap[28 + y][29 + w] = .{ .index = street_tile, .rot = 0 };
            tilemap[28 + y][30 + w] = .{ .index = street_tile, .rot = 0 };
        }
        tilemap[27][27] = .{ .index = curb_corner, .rot = 3 };
        tilemap[27][28 + w] = .{ .index = curb_corner, .rot = 2 };
        tilemap[28 + h][28 + w] = .{ .index = curb_corner, .rot = 1 };
        tilemap[28 + h][27] = .{ .index = curb_corner, .rot = 0 };
    }

    {
        // per tile instance data
        for (&tile_instance_data) |*i| i.* = .init(arena);
        for (0..tilemap.len) |row| {
            for (0..tilemap[row].len) |col| {
                const tile = tilemap[row][col];
                if (tile.index == 0) continue;
                tile_instance_data[tile.index - 1].append(.{ @floatFromInt(col), @floatFromInt(row), 0, @floatFromInt(tile.rot) }) catch @panic("oom");
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
            if (instance_data.items.len > 0) {
                gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
                gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.STATIC_DRAW);
            }
            gl_tile.* = .{
                .vbo = vbo,
                .ebo = ebo,
                .ibo = ibo,
                .index_count = @intCast(tile.index_data.len),
                .instance_count = @intCast(instance_data.items.len),
            };
        }
    }

    {
        for (&building_instance_data) |*i| i.* = .init(arena);
        try building_instance_data[0].append(.{ 28, 28, 0, 0 });
        try building_instance_data[0].append(.{ 28, 28 + 8, 0, 1 });
        try building_instance_data[0].append(.{ 28 + 8, 28 + 8, 0, 2 });
        try building_instance_data[0].append(.{ 28 + 8, 28, 0, 3 });

        var vbos: [gl_buildings.len]gl.uint = undefined;
        var ebos: [gl_buildings.len]gl.uint = undefined;
        var ibos: [gl_buildings.len]gl.uint = undefined;
        gl.GenBuffers(vbos.len, &vbos);
        gl.GenBuffers(ebos.len, &ebos);
        gl.GenBuffers(ibos.len, &ibos);
        for (&gl_buildings, building_array, building_instance_data, vbos, ebos, ibos) |*gl_building, building, instance_data, vbo, ebo, ibo| {
            gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
            gl.BufferData(gl.ARRAY_BUFFER, @intCast(building.vertex_data.len * @sizeOf(f32)), building.vertex_data.ptr, gl.STATIC_DRAW);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
            gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(building.index_data.len * @sizeOf(u16)), building.index_data.ptr, gl.STATIC_DRAW);
            if (instance_data.items.len > 0) {
                gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
                gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.STATIC_DRAW);
            }
            gl_building.* = .{
                .vbo = vbo,
                .ebo = ebo,
                .ibo = ibo,
                .index_count = @intCast(building.index_data.len),
                .instance_count = @intCast(instance_data.items.len),
            };
        }
    }

    gl.GenTextures(1, @ptrCast(&tile_texture));
    gl.BindTexture(gl.TEXTURE_2D, tile_texture);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, tiles.image.width, tiles.image.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, tiles.image.pixels);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
}

pub fn draw(frame_arena: std.mem.Allocator) void {
    const move_speed = 25;
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
    camera.position += la.vec3_from_vec4(la.mul_vector(la.rotation(-camera.phi, .{ 0, 0, 1 }), move));

    const tilepicker_hover = math.point_in_rect(input.mx, input.my, box_x, box_y, box_w, box_h);

    // const projection = la.ortho(-6.4, 6.4, -3.6, 3.6, -100, 100);
    const aspect_ratio = video_width / video_height;
    const projection = la.perspective(45, aspect_ratio, 0.1);
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

    if (input.down and !tilepicker_hover) {
        const x: i32 = @intFromFloat(@round(cursor_pos[0] - 0.5));
        const y: i32 = @intFromFloat(@round(cursor_pos[1] - 0.5));
        if (x >= 0 and x < 64 and y >= 0 and y < 64) {
            const row: usize = @intCast(y);
            const col: usize = @intCast(x);
            tilemap[row][col] = current_tile;
            update_instance_data() catch @panic("oom");
        }
    }

    gfx.begin_frame(frame_arena, video_scale);

    gl.Enable(gl.DEPTH_TEST);
    draw_map(projection, view);
    gl.Disable(gl.DEPTH_TEST);

    {
        // draw cursor highlight quad
        debug_draw.begin(&projection, &view);
        const tile_x = @round(cursor_pos[0] - 0.5);
        const tile_y = @round(cursor_pos[1] - 0.5);
        const model = la.mul(la.translation(tile_x, tile_y, 0), la.scale(1, 1, 1));
        debug_draw.quad(&model);
    }

    const ortho = la.ortho(0, video_width, video_height, 0, -1000, 1000);
    // const ortho = la.ortho(0, video_width, 0, video_height, -1, 1);
    draw_tilepicker(frame_arena, ortho) catch @panic("oom");
}

fn draw_map(projection: mat4, view: mat4) void {
    gl.UseProgram(shaders.tile_shader.program);
    gl.BindTexture(gl.TEXTURE_2D, tile_texture);
    gl.UniformMatrix4fv(shaders.tile_shader.u_projection, 1, gl.FALSE, @ptrCast(&projection));
    gl.UniformMatrix4fv(shaders.tile_shader.u_view, 1, gl.FALSE, @ptrCast(&view));
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
        gl.DrawElementsInstanced(gl.TRIANGLES, gl_tile.index_count, gl.UNSIGNED_SHORT, 0, gl_tile.instance_count);
    }

    for (gl_buildings) |gl_building| {
        gl.BindBuffer(gl.ARRAY_BUFFER, gl_building.vbo);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 0);
        gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 3 * @sizeOf(f32));
        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 6 * @sizeOf(f32));
        gl.BindBuffer(gl.ARRAY_BUFFER, gl_building.ibo);
        gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_building.ebo);
        gl.DrawElementsInstanced(gl.TRIANGLES, gl_building.index_count, gl.UNSIGNED_SHORT, 0, gl_building.instance_count);
    }
    gl.DisableVertexAttribArray(0);
    gl.DisableVertexAttribArray(1);
    gl.DisableVertexAttribArray(2);
    gl.DisableVertexAttribArray(3);
    gl.VertexAttribDivisor(3, 0);
}

fn draw_tilepicker(frame_arena: std.mem.Allocator, projection: mat4) !void {
    gfx.begin(&projection, &la.identity());

    var box_path = try gfx.Path.init(frame_arena, 100);
    box_path.rect_rounded(16, 16, box_w, box_h, 8);
    gfx.set_color(.{ 0.95, 0.95, 0.95, 1 });
    try gfx.fill_path(&box_path);
    gfx.set_color(.{ 0, 0, 0, 1 });
    gfx.set_stroke_width(2);
    try gfx.stroke_path(&box_path);

    gfx.set_color(.{ 0, 0, 0, 1 });
    gfx.transform(&la.scale(2, 2, 1));
    gfx.draw_text("Toolbox", 16, 16);
    gfx.transform(&la.identity());

    if (true) {
        gl.Enable(gl.DEPTH_TEST);
        defer gl.Disable(gl.DEPTH_TEST);

        // draw tiles on buttons
        gl.UseProgram(shaders.tile_shader.program);
        gl.BindTexture(gl.TEXTURE_2D, tile_texture);
        gl.UniformMatrix4fv(shaders.tile_shader.u_projection, 1, gl.FALSE, @ptrCast(&projection));

        gl.EnableVertexAttribArray(0);
        gl.EnableVertexAttribArray(1);
        gl.EnableVertexAttribArray(2);
        gl.DisableVertexAttribArray(3);
        for (gl_tiles, 0..) |gl_tile, i| {
            const x: f32 = 16 + f32_i(i % 4) * (32 + 8) + 8;
            const y: f32 = 16 + 32 + f32_i(i / 4) * (32 + 8) + 8;
            const hover = math.point_in_rect(input.mx, input.my, x, y, 32, 32);
            const iso = muln(&.{
                la.translation(16, 16, 0),
                la.rotation(45, .{ 1, 0, 0 }),
                la.rotation(if (hover) time.seconds * 360 else 45, .{ 0, 0, 1 }),
                la.translation(-16, -16, 0),
            });
            const model = muln(&.{
                la.translation(x, y, -32),
                iso,
                la.scale(32, 32, 32),
            });
            gl.UniformMatrix4fv(shaders.tile_shader.u_view, 1, gl.FALSE, @ptrCast(&model));
            gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.vbo);
            gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 0);
            gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 3 * @sizeOf(f32));
            gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * @sizeOf(f32), 6 * @sizeOf(f32));
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_tile.ebo);
            gl.DrawElements(gl.TRIANGLES, gl_tile.index_count, gl.UNSIGNED_SHORT, 0);

            if (input.framedown and hover) {
                current_tile.index = @intCast(i + 1);
            }
        }
    }
}

fn f32_i(int: anytype) f32 {
    return @floatFromInt(int);
}
