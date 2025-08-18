const std = @import("std");
const gl = @import("gl");
const shaders = @import("shaders.zig");
const la = @import("linear_algebra.zig");
const vec4 = la.vec4;
const mat4 = la.mat4;

var vertex_data: std.ArrayList(f32) = undefined;
var vbo: gl.uint = undefined;
var font_texture: gl.uint = undefined;
var arena_frame: std.mem.Allocator = undefined;
var path_cache: PathCache = undefined;

var device_pixel_ratio: f32 = undefined;
var tesselation_tolerance: f32 = undefined;
var distance_tolerance: f32 = undefined;

pub const Path = struct {
    commands: std.ArrayListUnmanaged(Command),

    const Command = union {
        verb: Verb,
        data: f32,

        const Verb = enum(u32) {
            move,
            line,
            bezier,
            close,
        };
    };

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Path {
        return .{ .commands = try .initCapacity(allocator, capacity) };
    }

    pub fn move_to(path: *Path, x: f32, y: f32) void {
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .move },
            .{ .data = x },
            .{ .data = y },
        });
    }

    pub fn line_to(path: *Path, x: f32, y: f32) void {
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .line },
            .{ .data = x },
            .{ .data = y },
        });
    }

    pub fn bezier_to(path: *Path, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void {
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .bezier },
            .{ .data = c1x },
            .{ .data = c1y },
            .{ .data = c2x },
            .{ .data = c2y },
            .{ .data = x },
            .{ .data = y },
        });
    }

    pub fn close(path: *Path) void {
        path.commands.appendAssumeCapacity(.{ .verb = .close });
    }
};

pub fn init(allocator: std.mem.Allocator) void {
    vertex_data = std.ArrayList(f32).init(allocator);

    gl.GenTextures(1, @ptrCast(&font_texture));
    gl.BindTexture(gl.TEXTURE_2D, font_texture);
    const pixels = @embedFile("fonts/font.raw");
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 128, 64, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    gl.GenBuffers(1, @ptrCast(&vbo));

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform4f(shaders.gfx_shader.color_loc, 1, 1, 1, 1);
}

pub fn begin_frame(arena: std.mem.Allocator, pixel_ratio: f32) void {
    arena_frame = arena;

    device_pixel_ratio = pixel_ratio;
    tesselation_tolerance = 0.25 / device_pixel_ratio;
    distance_tolerance = 0.01 / device_pixel_ratio;
}

pub fn begin(projection: *const mat4, view: *const mat4) void {
    gl.UseProgram(shaders.gfx_shader.program);
    gl.UniformMatrix4fv(shaders.gfx_shader.projection_loc, 1, gl.FALSE, @ptrCast(projection));
    gl.UniformMatrix4fv(shaders.gfx_shader.view_loc, 1, gl.FALSE, @ptrCast(view));
}

pub fn transform(model: *const mat4) void {
    gl.UseProgram(shaders.gfx_shader.program);
    gl.UniformMatrix4fv(shaders.gfx_shader.model_loc, 1, gl.FALSE, @ptrCast(model));
}

pub fn set_color(color: vec4) void {
    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform4fv(shaders.gfx_shader.color_loc, 1, @ptrCast(&color));
}

pub fn fill_path(path: *const Path) !void {
    var cache = PathCache.init();
    try cache.flatten_paths(path);

    for (cache.paths.items) |sub_path| {
        vertex_data.clearRetainingCapacity();
        try vertex_data.ensureTotalCapacity(2 * sub_path.points.items.len);
        for (sub_path.points.items) |point| {
            vertex_data.appendSliceAssumeCapacity(&.{ point.x, point.y });
        }

        gl.EnableVertexAttribArray(0);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertex_data.items.len * @sizeOf(f32)),
            vertex_data.items.ptr,
            gl.STREAM_DRAW,
        );
        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), 0);

        gl.UseProgram(shaders.gfx_shader.program);
        gl.Uniform1i(shaders.gfx_shader.colormap_enabled_loc, 0);
        gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
    }
}

pub fn stroke_path(path: *const Path) void {
    _ = path;
}

pub fn fill_rect(x: f32, y: f32, w: f32, h: f32) void {
    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(4 * 4 * @sizeOf(f32)) catch return; // OOM

    vertex_data.appendSliceAssumeCapacity(&.{
        x,     y,
        x + w, y,
        x + w, y + h,
        x,     y + h,
    });

    gl.EnableVertexAttribArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(
        gl.ARRAY_BUFFER,
        @intCast(vertex_data.items.len * @sizeOf(f32)),
        vertex_data.items.ptr,
        gl.STREAM_DRAW,
    );
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), 0);

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform1i(shaders.gfx_shader.colormap_enabled_loc, 0);
    gl.DrawArrays(gl.TRIANGLE_FAN, 0, 4);
}

pub fn draw_text(text: []const u8, x: f32, y: f32) void {
    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(text.len * 6 * 4 * @sizeOf(f32)) catch return; // OOM
    var px0 = x;
    var py0 = y;
    for (text) |c| {
        if (c == '\n') {
            py0 += 8;
            continue;
        }

        const px1 = px0 + 8;
        const py1 = py0 + 8;
        const tcx0 = @as(f32, @floatFromInt(c % 16)) / 16.0;
        const tcx1 = tcx0 + 1.0 / 16.0;
        const tcy0 = @as(f32, @floatFromInt(c / 16)) / 8.0;
        const tcy1 = tcy0 + 1.0 / 8.0;

        vertex_data.appendSliceAssumeCapacity(&.{
            px0, py0, tcx0, tcy0,
            px1, py0, tcx1, tcy0,
            px1, py1, tcx1, tcy1,
            px0, py0, tcx0, tcy0,
            px1, py1, tcx1, tcy1,
            px0, py1, tcx0, tcy1,
        });

        px0 += 8;
    }

    gl.EnableVertexAttribArray(0);
    gl.EnableVertexAttribArray(1);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(vertex_data.items.len * @sizeOf(f32)), vertex_data.items.ptr, gl.STREAM_DRAW);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 2 * @sizeOf(f32));

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform1i(shaders.gfx_shader.colormap_enabled_loc, 1);
    gl.BindTexture(gl.TEXTURE_2D, font_texture);
    gl.DrawArrays(gl.TRIANGLES, 0, @intCast(6 * text.len));
}

const Point = struct {
    x: f32,
    y: f32,
    flags: Flags,

    const Flags = struct {
        corner: bool = false,
    };

    fn eql(self: Point, other: Point) bool {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return dx * dx + dy + dy < distance_tolerance * distance_tolerance;
    }
};

const PathCache = struct {
    paths: std.ArrayListUnmanaged(FlattenedPath),

    const FlattenedPath = struct {
        points: std.ArrayListUnmanaged(Point),
        closed: bool,

        fn init() FlattenedPath {
            return .{
                .points = .initBuffer(&.{}),
                .closed = false,
            };
        }

        fn add_point(path: *FlattenedPath, point: Point) !void {
            return try path.points.append(arena_frame, point);
        }
    };

    fn init() PathCache {
        return .{ .paths = .initBuffer(&.{}) };
    }

    fn add_path(cache: *PathCache) !void {
        const path = try cache.paths.addOne(arena_frame);
        path.* = FlattenedPath.init();
    }

    fn add_point(cache: *PathCache, point: Point) !void {
        const path = &cache.paths.items[cache.paths.items.len - 1];

        if (path.points.items.len > 0) {
            const last = &path.points.items[path.points.items.len - 1];
            if (last.eql(point)) {
                if (point.flags.corner) last.flags.corner = true;
                return;
            }
        }

        return path.points.append(arena_frame, point);
    }

    fn last_point(cache: *const PathCache) Point {
        return cache.paths.getLast().points.getLast();
    }

    fn close_path(cache: *const PathCache) void {
        cache.paths.items[cache.paths.items.len - 1].closed = true;
    }

    fn flatten_paths(cache: *PathCache, source_path: *const Path) !void {
        var i: usize = 0;
        while (i < source_path.commands.items.len) {
            switch (source_path.commands.items[i].verb) {
                .move => {
                    try cache.add_path();
                    try cache.add_point(.{
                        .x = source_path.commands.items[i + 1].data,
                        .y = source_path.commands.items[i + 2].data,
                        .flags = .{ .corner = true },
                    });
                    i += 3;
                },
                .line => {
                    try cache.add_point(.{
                        .x = source_path.commands.items[i + 1].data,
                        .y = source_path.commands.items[i + 2].data,
                        .flags = .{ .corner = true },
                    });
                    i += 3;
                },
                .bezier => {
                    const last = cache.last_point();
                    try cache.tesselate_bezier(
                        last.x,
                        last.y,
                        source_path.commands.items[i + 1].data,
                        source_path.commands.items[i + 2].data,
                        source_path.commands.items[i + 3].data,
                        source_path.commands.items[i + 4].data,
                        source_path.commands.items[i + 5].data,
                        source_path.commands.items[i + 6].data,
                        0,
                        .{ .corner = true },
                    );
                    i += 7;
                },
                .close => {
                    cache.close_path();
                    i += 1;
                },
            }
        }

        // Calculate the direction and length of line segments.
    }

    fn tesselate_bezier(
        cache: *PathCache,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        x3: f32,
        y3: f32,
        x4: f32,
        y4: f32,
        level: u8,
        flags: Point.Flags,
    ) !void {
        if (level > 10) return;

        const x12 = (x1 + x2) * 0.5;
        const y12 = (y1 + y2) * 0.5;
        const x23 = (x2 + x3) * 0.5;
        const y23 = (y2 + y3) * 0.5;
        const x34 = (x3 + x4) * 0.5;
        const y34 = (y3 + y4) * 0.5;
        const x123 = (x12 + x23) * 0.5;
        const y123 = (y12 + y23) * 0.5;

        const dx = x4 - x1;
        const dy = y4 - y1;

        const d2 = @abs(((x2 - x4) * dy - (y2 - y4) * dx));
        const d3 = @abs(((x3 - x4) * dy - (y3 - y4) * dx));

        if ((d2 + d3) * (d2 + d3) < tesselation_tolerance * (dx * dx + dy * dy)) {
            try cache.add_point(.{ .x = x4, .y = y4, .flags = flags });
            return;
        }

        const x234 = (x23 + x34) * 0.5;
        const y234 = (y23 + y34) * 0.5;
        const x1234 = (x123 + x234) * 0.5;
        const y1234 = (y123 + y234) * 0.5;

        try cache.tesselate_bezier(x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1, .{});
        try cache.tesselate_bezier(x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1, flags);
    }
};
