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

var stroke_width: f32 = 1;
var line_cap: LineCap = .butt;
var line_join: LineJoin = .miter;
var miter_limit: f32 = 10;

// Length proportional to radius of a cubic bezier handle for 90deg arcs.
const kappa90 = 4.0 * (@sqrt(2.0) - 1.0) / 3.0; // 0.5522847493

pub const LineCap = enum(u2) {
    butt,
    round,
    square,
};

pub const LineJoin = enum(u2) {
    miter,
    round,
    bevel,
};

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

    pub fn rect(path: *Path, x: f32, y: f32, w: f32, h: f32) void {
        path.move_to(x, y);
        path.line_to(x, y + h);
        path.line_to(x + w, y + h);
        path.line_to(x + w, y);
        path.close();
    }

    pub fn rect_rounded(path: *Path, x: f32, y: f32, w: f32, h: f32, r: f32) void {
        path.rect_rounded_varying(x, y, w, h, r, r, r, r);
    }

    pub fn rect_rounded_varying(
        path: *Path,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r_topleft: f32,
        r_topright: f32,
        r_bottomleft: f32,
        r_bottomright: f32,
    ) void {
        const rx_bl = @min(r_bottomleft, 0.5 * @abs(w)) * std.math.sign(w);
        const ry_bl = @min(r_bottomleft, 0.5 * @abs(h)) * std.math.sign(h);
        const rx_br = @min(r_bottomright, 0.5 * @abs(w)) * std.math.sign(w);
        const ry_br = @min(r_bottomright, 0.5 * @abs(h)) * std.math.sign(h);
        const rx_tr = @min(r_topright, 0.5 * @abs(w)) * std.math.sign(w);
        const ry_tr = @min(r_topright, 0.5 * @abs(h)) * std.math.sign(h);
        const rx_tl = @min(r_topleft, 0.5 * @abs(w)) * std.math.sign(w);
        const ry_tl = @min(r_topleft, 0.5 * @abs(h)) * std.math.sign(h);
        path.move_to(x, y + ry_tl);
        path.line_to(x, y + h - ry_bl);
        path.bezier_to(x, y + h - ry_bl * (1 - kappa90), x + rx_bl * (1 - kappa90), y + h, x + rx_bl, y + h);
        path.line_to(x + w - rx_br, y + h);
        path.bezier_to(x + w - rx_br * (1 - kappa90), y + h, x + w, y + h - ry_br * (1 - kappa90), x + w, y + h - ry_br);
        path.line_to(x + w, y + ry_tr);
        path.bezier_to(x + w, y + ry_tr * (1 - kappa90), x + w - rx_tr * (1 - kappa90), y, x + w - rx_tr, y);
        path.line_to(x + rx_tl, y);
        path.bezier_to(x + rx_tl * (1 - kappa90), y, x, y + ry_tl * (1 - kappa90), x, y + ry_tl);
        path.close();
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

    reset();
}

pub fn reset() void {
    stroke_width = 1;
    line_cap = .butt;
    line_join = .miter;
    miter_limit = 10;
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

pub fn set_stroke_width(width: f32) void {
    stroke_width = width;
}

pub fn fill_path(path: *const Path) !void {
    var cache = PathCache.init();
    try cache.flatten_paths(path);

    try cache.calculate_joins();

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform1i(shaders.gfx_shader.colormap_enabled_loc, 0);

    for (cache.paths.items) |sub_path| {
        vertex_data.clearRetainingCapacity();
        try vertex_data.ensureTotalCapacity(2 * sub_path.points.items.len);
        for (sub_path.points.items) |point| {
            add_vertex(point.x, point.y);
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

        if (sub_path.convex) {
            gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
        } else {
            gl.Enable(gl.STENCIL_TEST);
            defer gl.Disable(gl.STENCIL_TEST);
            gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
            gl.StencilMask(0xFF);
            gl.StencilFunc(gl.ALWAYS, 0x00, 0xFF);
            gl.StencilOpSeparate(gl.FRONT, gl.KEEP, gl.KEEP, gl.INCR_WRAP);
            gl.StencilOpSeparate(gl.BACK, gl.KEEP, gl.KEEP, gl.DECR_WRAP);
            gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
            // Draw fill
            gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);
            gl.StencilFunc(gl.NOTEQUAL, 0x00, 0x7F);
            gl.StencilOp(gl.ZERO, gl.ZERO, gl.ZERO);
            gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
        }
    }
}

pub fn stroke_path(path: *const Path) !void {
    var cache = PathCache.init();

    try cache.flatten_paths(path);

    try cache.expand_stroke(0.5 * stroke_width);

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

    for (cache.paths.items) |sub_path| {
        gl.DrawArrays(gl.TRIANGLE_STRIP, @intCast(sub_path.vertex_offset), @intCast(sub_path.vertex_count));
    }
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
    dx: f32,
    dy: f32,
    len: f32,
    dmx: f32,
    dmy: f32,
    flags: Flags,

    const Flags = struct {
        corner: bool = false,
        left: bool = false,
        bevel: bool = false,
        innerbevel: bool = false,
    };

    fn eql(self: Point, other: Point) bool {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return dx * dx + dy * dy < distance_tolerance * distance_tolerance;
    }
};

const PathCache = struct {
    paths: std.ArrayListUnmanaged(FlattenedPath),

    const FlattenedPath = struct {
        points: std.ArrayListUnmanaged(Point),
        closed: bool,
        convex: bool,
        nbevel: usize,
        vertex_offset: usize,
        vertex_count: usize,

        fn init() FlattenedPath {
            return .{
                .points = .initBuffer(&.{}),
                .closed = false,
                .convex = false,
                .nbevel = 0,
                .vertex_offset = 0,
                .vertex_count = 0,
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

    fn add_point(cache: *PathCache, x: f32, y: f32, flags: Point.Flags) !void {
        const path = &cache.paths.items[cache.paths.items.len - 1];

        var point = std.mem.zeroes(Point);
        point.x = x;
        point.y = y;
        point.flags = flags;

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
                    try cache.add_point(
                        source_path.commands.items[i + 1].data,
                        source_path.commands.items[i + 2].data,
                        .{ .corner = true },
                    );
                    i += 3;
                },
                .line => {
                    try cache.add_point(
                        source_path.commands.items[i + 1].data,
                        source_path.commands.items[i + 2].data,
                        .{ .corner = true },
                    );
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
            try cache.add_point(x4, y4, flags);
            return;
        }

        const x234 = (x23 + x34) * 0.5;
        const y234 = (y23 + y34) * 0.5;
        const x1234 = (x123 + x234) * 0.5;
        const y1234 = (y123 + y234) * 0.5;

        try cache.tesselate_bezier(x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1, .{});
        try cache.tesselate_bezier(x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1, flags);
    }

    fn expand_stroke(cache: *PathCache, width: f32) !void {
        const w = width;
        const ncap = curve_divisions(w, std.math.pi); // Calculate divisions per half circle.

        try cache.calculate_joins();

        // Calculate max vertex usage.
        var cverts: usize = 0;
        for (cache.paths.items) |path| {
            if (line_join == .round) {
                cverts += (path.points.items.len + path.nbevel * (ncap + 2) + 1) * 2; // plus one for loop
            } else {
                cverts += (path.points.items.len + path.nbevel * 5 + 1) * 2; // plus one for loop
            }
            if (!path.closed) {
                // space for caps
                if (line_cap == .round) {
                    cverts += (ncap * 2 + 2) * 2;
                } else {
                    cverts += (3 + 3) * 2;
                }
            }
        }

        // Calculate vertex data.
        try vertex_data.ensureUnusedCapacity(2 * cverts);

        for (cache.paths.items) |*path| {
            const pts = path.points.items;
            if (pts.len == 0) continue;
            path.vertex_offset = vertex_data.items.len / 2;

            var p0 = &pts[pts.len - 1];
            var p1 = &pts[0];
            var s: u32 = 0;
            var e = pts.len;
            if (!path.closed) {
                p0 = &pts[0];
                p1 = &pts[1];
                s = 1;
                e = pts.len - 1;

                // Add cap.
                var dx = p1.x - p0.x;
                var dy = p1.y - p0.y;
                _ = normalize(&dx, &dy);
                switch (line_cap) {
                    .butt => butt_cap_start(p0.*, dx, dy, w, 0),
                    .square => butt_cap_start(p0.*, dx, dy, w, w),
                    .round => round_cap_start(p0.*, dx, dy, w, ncap),
                }
            }

            var j: u32 = s;
            while (j < e) : (j += 1) {
                p1 = &pts[j];
                defer p0 = p1;
                if (p1.flags.bevel or p1.flags.innerbevel) {
                    if (line_join == .round) {
                        // round_join(&dst, p0.*, p1.*, w, w, ncap);
                        unreachable;
                    } else {
                        bevel_join(p0.*, p1.*, w, w);
                    }
                } else {
                    add_vertex(p1.x + (p1.dmx * w), p1.y + (p1.dmy * w));
                    add_vertex(p1.x - (p1.dmx * w), p1.y - (p1.dmy * w));
                }
            }

            if (path.closed) {
                // Copy first two vertices to loop the stroke.
                const vertex_start = vertex_data.items[2 * path.vertex_offset ..];
                add_vertex(vertex_start[0], vertex_start[1]);
                add_vertex(vertex_start[2], vertex_start[3]);
            } else {
                p1 = &pts[j];
                // Add cap.
                var dx = p1.x - p0.x;
                var dy = p1.y - p0.y;
                _ = normalize(&dx, &dy);

                switch (line_cap) {
                    .butt => butt_cap_end(p1.*, dx, dy, w, 0),
                    .square => butt_cap_end(p1.*, dx, dy, w, w),
                    .round => round_cap_end(p1.*, dx, dy, w, ncap),
                }
            }

            path.vertex_count = vertex_data.items.len / 2 - path.vertex_offset;
        }
    }

    fn bevel_join(p0: Point, p1: Point, lw: f32, rw: f32) void {
        const dlx0 = p0.dy;
        const dly0 = -p0.dx;
        const dlx1 = p1.dy;
        const dly1 = -p1.dx;

        if (p1.flags.left) {
            var lx0: f32 = undefined;
            var ly0: f32 = undefined;
            var lx1: f32 = undefined;
            var ly1: f32 = undefined;
            choose_bevel(p1.flags.innerbevel, p0, p1, lw, &lx0, &ly0, &lx1, &ly1);

            add_vertex(lx0, ly0);
            add_vertex(p1.x - dlx0 * rw, p1.y - dly0 * rw);

            if (p1.flags.bevel) {
                add_vertex(lx0, ly0);
                add_vertex(p1.x - dlx0 * rw, p1.y - dly0 * rw);

                add_vertex(lx1, ly1);
                add_vertex(p1.x - dlx1 * rw, p1.y - dly1 * rw);
            } else {
                const rx0 = p1.x - p1.dmx * rw;
                const ry0 = p1.y - p1.dmy * rw;

                add_vertex(p1.x, p1.y);
                add_vertex(p1.x - dlx0 * rw, p1.y - dly0 * rw);

                add_vertex(rx0, ry0);
                add_vertex(rx0, ry0);

                add_vertex(p1.x, p1.y);
                add_vertex(p1.x - dlx1 * rw, p1.y - dly1 * rw);
            }

            add_vertex(lx1, ly1);
            add_vertex(p1.x - dlx1 * rw, p1.y - dly1 * rw);
        } else {
            var rx0: f32 = undefined;
            var ry0: f32 = undefined;
            var rx1: f32 = undefined;
            var ry1: f32 = undefined;
            choose_bevel(p1.flags.innerbevel, p0, p1, -rw, &rx0, &ry0, &rx1, &ry1);

            add_vertex(p1.x + dlx0 * lw, p1.y + dly0 * lw);
            add_vertex(rx0, ry0);

            if (p1.flags.bevel) {
                add_vertex(p1.x + dlx0 * lw, p1.y + dly0 * lw);
                add_vertex(rx0, ry0);

                add_vertex(p1.x + dlx1 * lw, p1.y + dly1 * lw);
                add_vertex(rx1, ry1);
            } else {
                const lx0 = p1.x + p1.dmx * lw;
                const ly0 = p1.y + p1.dmy * lw;

                add_vertex(p1.x + dlx0 * lw, p1.y + dly0 * lw);
                add_vertex(p1.x, p1.y);

                add_vertex(lx0, ly0);
                add_vertex(lx0, ly0);

                add_vertex(p1.x + dlx1 * lw, p1.y + dly1 * lw);
                add_vertex(p1.x, p1.y);
            }

            add_vertex(p1.x + dlx1 * lw, p1.y + dly1 * lw);
            add_vertex(rx1, ry1);
        }
    }

    fn butt_cap_start(p: Point, dx: f32, dy: f32, w: f32, d: f32) void {
        const px = p.x - dx * d;
        const py = p.y - dy * d;
        const dlx = dy;
        const dly = -dx;
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
    }

    fn butt_cap_end(p: Point, dx: f32, dy: f32, w: f32, d: f32) void {
        const px = p.x + dx * d;
        const py = p.y + dy * d;
        const dlx = dy;
        const dly = -dx;
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
    }

    fn round_cap_start(p: Point, dx: f32, dy: f32, w: f32, ncap: u32) void {
        const px = p.x;
        const py = p.y;
        const dlx = dy;
        const dly = -dx;
        var i: u32 = 0;
        while (i < ncap) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ncap - 1)) * std.math.pi;
            const ax = @cos(a) * w;
            const ay = @sin(a) * w;
            add_vertex(px - dlx * ax - dx * ay, py - dly * ax - dy * ay);
            add_vertex(px, py);
        }
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
    }

    fn round_cap_end(p: Point, dx: f32, dy: f32, w: f32, ncap: u32) void {
        const px = p.x;
        const py = p.y;
        const dlx = dy;
        const dly = -dx;
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
        var i: u32 = 0;
        while (i < ncap) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ncap - 1)) * std.math.pi;
            const ax = @cos(a) * w;
            const ay = @sin(a) * w;
            add_vertex(px, py);
            add_vertex(px - dlx * ax + dx * ay, py - dly * ax + dy * ay);
        }
    }

    fn calculate_joins(cache: *PathCache) !void {
        // Calculate the direction and length of line segments.
        for (cache.paths.items) |*path| {
            // If the first and last points are the same, remove the last, mark as closed path.
            if (path.points.items[0].eql(path.points.getLast())) {
                path.points.items.len -= 1;
                if (path.points.items.len == 0) continue;
                path.closed = true;
            }

            // // Enforce winding.
            // if (path.points.items.len > 2) {
            //     if (path.winding == .cw) polyReverse(pts);
            // }

            var p0 = &path.points.items[path.points.items.len - 1];
            for (path.points.items) |*p1| {
                defer p0 = p1;
                // Calculate segment direction and length
                p0.dx = p1.x - p0.x;
                p0.dy = p1.y - p0.y;
                p0.len = normalize(&p0.dx, &p0.dy);
            }
        }

        // Calculate which joins needs extra vertices to append, and gather vertex count.
        for (cache.paths.items) |*path| {
            if (path.points.items.len == 0) continue;
            const pts = path.points.items;
            var nleft: u32 = 0;
            path.nbevel = 0;

            var p0 = &pts[pts.len - 1];
            for (pts) |*p1| {
                defer p0 = p1;

                const dlx0 = p0.dy;
                const dly0 = -p0.dx;
                const dlx1 = p1.dy;
                const dly1 = -p1.dx;
                // Calculate extrusions
                p1.dmx = (dlx0 + dlx1) * 0.5;
                p1.dmy = (dly0 + dly1) * 0.5;
                const dmr2 = p1.dmx * p1.dmx + p1.dmy * p1.dmy;
                if (dmr2 > 0.000001) {
                    var s = 1.0 / dmr2;
                    if (s > 600) s = 600;
                    p1.dmx *= s;
                    p1.dmy *= s;
                }

                // Clear flags, but keep the corner.
                p1.flags = .{ .corner = p1.flags.corner };

                // Keep track of left turns.
                if (cross(p0.dx, p0.dy, p1.dx, p1.dy) > 0.0) {
                    nleft += 1;
                    p1.flags.left = true;
                }

                // Calculate if we should use bevel or miter for inner join.
                const limit = 1.01;
                if ((dmr2 * limit * limit) < 1.0)
                    p1.flags.innerbevel = true;

                // Check to see if the corner needs to be beveled.
                if (p1.flags.corner) {
                    if ((dmr2 * miter_limit * miter_limit) < 1.0 or
                        line_join == .bevel or line_join == .round)
                    {
                        p1.flags.bevel = true;
                    }
                }

                if (p1.flags.bevel or p1.flags.innerbevel) {
                    path.nbevel += 1;
                }
            }

            path.convex = (nleft == path.points.items.len);
        }
    }
};

fn add_vertex(x: f32, y: f32) void {
    vertex_data.appendSliceAssumeCapacity(&.{ x, y });
}

fn curve_divisions(r: f32, arc: f32) u32 {
    const da = std.math.acos(r / (r + tesselation_tolerance)) * 2;
    return @max(2, @as(u32, @intFromFloat(@ceil(arc / da))));
}

fn choose_bevel(bevel: bool, p0: Point, p1: Point, w: f32, x0: *f32, y0: *f32, x1: *f32, y1: *f32) void {
    if (bevel) {
        x0.* = p1.x + p0.dy * w;
        y0.* = p1.y - p0.dx * w;
        x1.* = p1.x + p1.dy * w;
        y1.* = p1.y - p1.dx * w;
    } else {
        x0.* = p1.x + p1.dmx * w;
        y0.* = p1.y + p1.dmy * w;
        x1.* = p1.x + p1.dmx * w;
        y1.* = p1.y + p1.dmy * w;
    }
}

fn cross(dx0: f32, dy0: f32, dx1: f32, dy1: f32) f32 {
    return dx1 * dy0 - dx0 * dy1;
}

fn normalize(x: *f32, y: *f32) f32 {
    const d = @sqrt(x.* * x.* + y.* * y.*);
    if (d > 1e-6) {
        const id = 1.0 / d;
        x.* *= id;
        y.* *= id;
    }
    return d;
}
