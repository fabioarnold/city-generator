const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.gfx);
const gl = @import("gl");
const shaders = @import("shaders.zig");
const la = @import("linear_algebra.zig");
const vec2 = la.vec2;
const vec4 = la.vec4;
const mat3 = la.mat3;
const mat4 = la.mat4;
pub const Color = vec4;
const TrueType = @import("truetype.zig");
const FontAtlas = @import("font_atlas.zig");

var vertex_data: std.ArrayList(f32) = undefined;
var vbo: gl.uint = undefined;
var arena_frame: std.mem.Allocator = undefined;
var path_cache: PathCache = undefined;

var device_pixel_ratio: f32 = undefined;
var tesselation_tolerance: f32 = undefined;
var distance_tolerance: f32 = undefined;

var state_index: usize = 0;
var state_stack: [16]State = undefined;
const State = struct {
    model: mat4 = la.identity(),
    color: vec4 = @splat(1),
    font_id: u32 = 0,
    font_size: f32 = 16,
    texture: gl.uint = 0,
    src_rect: vec4 = .{ 0, 0, 1, 1 }, // From texture.
    gradient: Gradient = .{},

    const Gradient = struct {
        const count_max = 4;
        colors: [count_max]vec4 = undefined,
        stops: [count_max]f32 = undefined,
        count: u32 = 0,
        xform: mat3 = la.identity3(),
        extents: vec2 = @splat(0),
        radius: f32 = 0,
        feather: f32 = 0,
        smooth: bool = false,
    };

    fn set_uniforms(state: *const State) void {
        gl.UseProgram(shaders.gfx_shader.program);
        gl.UniformMatrix4fv(shaders.gfx_shader.u_model, 1, gl.FALSE, @ptrCast(&state.model));
        gl.Uniform4fv(shaders.gfx_shader.u_color, 1, &state.color[0]);
        if (state.gradient.count > 0) {
            const count: i32 = @intCast(state.gradient.count);
            gl.Uniform1i(shaders.gfx_shader.u_gradient_count, count);
            gl.Uniform4fv(shaders.gfx_shader.u_gradient_colors, count, &state.gradient.colors[0][0]);
            gl.Uniform1fv(shaders.gfx_shader.u_gradient_stops, count, &state.gradient.stops[0]);
            gl.UniformMatrix3fv(shaders.gfx_shader.u_gradient_xform, 1, gl.FALSE, &state.gradient.xform[0][0]);
            gl.Uniform2fv(shaders.gfx_shader.u_gradient_extents, 1, &state.gradient.extents[0]);
            gl.Uniform1f(shaders.gfx_shader.u_gradient_radius, state.gradient.radius);
            gl.Uniform1f(shaders.gfx_shader.u_gradient_feather, state.gradient.feather);
            gl.Uniform1i(shaders.gfx_shader.u_gradient_smooth, @intFromBool(state.gradient.smooth));
        } else {
            gl.Uniform1i(shaders.gfx_shader.u_gradient_count, 0);
        }
    }
};

// TODO: move to State
var stroke_width: f32 = 1;
var line_cap: LineCap = .butt;
var line_join: LineJoin = .miter;
var miter_limit: f32 = 10;

var current_path: Path = undefined;

var fonts: std.ArrayList(FontAtlas) = .empty;

const colormap_type_none = 0;
const colormap_type_rgba = 1;
const colormap_type_alpha = 2;

// Length proportional to radius of a cubic bezier handle for 90deg arcs.
const kappa90 = 4.0 * (@sqrt(2.0) - 1.0) / 3.0; // 0.5522847493

pub fn rgb(c: u32) Color {
    return .{
        @as(f32, @floatFromInt((c >> 16) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((c >> 8) & 0xff)) / 255.0,
        @as(f32, @floatFromInt(c & 0xFF)) / 255.0,
        1,
    };
}

pub fn rgba(c: u32) Color {
    return .{
        @as(f32, @floatFromInt((c >> 24) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((c >> 16) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((c >> 8) & 0xff)) / 255.0,
        @as(f32, @floatFromInt(c & 0xFF)) / 255.0,
    };
}

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub const zero: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub fn offset(rect: Rect, x: f32, y: f32) Rect {
        return .{ .x = rect.x + x, .y = rect.y + y, .w = rect.w, .h = rect.h };
    }

    pub fn inset(rect: Rect, value: f32) Rect {
        return .{
            .x = rect.x + value,
            .y = rect.y + value,
            .w = rect.w - 2 * value,
            .h = rect.h - 2 * value,
        };
    }
};

/// Takes a point in the current model space and transforms into screen space.
pub fn point_to_screen(point_model: vec2) vec2 {
    const point_screen = la.mul_vector(get_state().model, .{ point_model[0], point_model[1], 0, 1 });
    return .{ point_screen[0], point_screen[1] };
}

/// Takes a point in screen space and transforms into the current model space.
pub fn point_from_screen(point_screen: vec2) vec2 {
    const inv_model = la.invert_affine(get_state().model);
    const point_model = la.mul_vector(inv_model, .{ point_screen[0], point_screen[1], 0, 1 });
    return .{ point_model[0], point_model[1] };
}

pub fn point_in_rect(point: vec2, rect: Rect) bool {
    return point[0] >= rect.x and
        point[1] >= rect.y and
        point[0] <= rect.x + rect.w and
        point[1] <= rect.y + rect.h;
}

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
    x: f32 = 0,
    y: f32 = 0,
    commands: std.ArrayList(Command),

    const Command = union {
        verb: Verb,
        data: f32,

        const Verb = enum(u32) {
            move,
            line,
            bezier,
            hole,
            close,
        };
    };

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Path {
        return .{ .commands = try .initCapacity(allocator, capacity) };
    }

    pub fn clear(path: *Path) void {
        path.commands.clearRetainingCapacity();
    }

    /// 3 commands.
    pub fn move_to(path: *Path, x: f32, y: f32) void {
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .move },
            .{ .data = x },
            .{ .data = y },
        });
        path.x = x;
        path.y = y;
    }

    /// 3 commands.
    pub fn line_to(path: *Path, x: f32, y: f32) void {
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .line },
            .{ .data = x },
            .{ .data = y },
        });
        path.x = x;
        path.y = y;
    }

    /// 7 commands.
    pub fn quad_to(path: *Path, cx: f32, cy: f32, x: f32, y: f32) void {
        const x0 = path.x;
        const y0 = path.y;
        path.commands.appendSliceAssumeCapacity(&.{
            .{ .verb = .bezier },
            .{ .data = x0 + 2.0 / 3.0 * (cx - x0) },
            .{ .data = y0 + 2.0 / 3.0 * (cy - y0) },
            .{ .data = x + 2.0 / 3.0 * (cx - x) },
            .{ .data = y + 2.0 / 3.0 * (cy - y) },
            .{ .data = x },
            .{ .data = y },
        });
        path.x = x;
        path.y = y;
    }

    /// 7 commands.
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
        path.x = x;
        path.y = y;
    }

    /// 1 command.
    pub fn hole(path: *Path) void {
        path.commands.appendAssumeCapacity(.{ .verb = .hole });
    }

    /// 1 command.
    pub fn close(path: *Path) void {
        path.commands.appendAssumeCapacity(.{ .verb = .close });
    }

    /// 13 commands.
    pub fn rect(path: *Path, r: Rect) void {
        path.move_to(r.x, r.y);
        path.line_to(r.x, r.y + r.h);
        path.line_to(r.x + r.w, r.y + r.h);
        path.line_to(r.x + r.w, r.y);
        path.close();
    }

    /// 44 commands.
    pub fn rect_rounded(path: *Path, r: Rect, radius: f32) void {
        path.rect_rounded_varying(r, radius, radius, radius, radius);
    }

    /// 44 commands.
    pub fn rect_rounded_varying(
        path: *Path,
        r: Rect,
        r_topleft: f32,
        r_topright: f32,
        r_bottomleft: f32,
        r_bottomright: f32,
    ) void {
        const rx_bl = @min(r_bottomleft, 0.5 * @abs(r.w)) * std.math.sign(r.w);
        const ry_bl = @min(r_bottomleft, 0.5 * @abs(r.h)) * std.math.sign(r.h);
        const rx_br = @min(r_bottomright, 0.5 * @abs(r.w)) * std.math.sign(r.w);
        const ry_br = @min(r_bottomright, 0.5 * @abs(r.h)) * std.math.sign(r.h);
        const rx_tr = @min(r_topright, 0.5 * @abs(r.w)) * std.math.sign(r.w);
        const ry_tr = @min(r_topright, 0.5 * @abs(r.h)) * std.math.sign(r.h);
        const rx_tl = @min(r_topleft, 0.5 * @abs(r.w)) * std.math.sign(r.w);
        const ry_tl = @min(r_topleft, 0.5 * @abs(r.h)) * std.math.sign(r.h);
        const k = 1 - kappa90;
        const x1 = r.x + r.w;
        const y1 = r.y + r.h;
        path.move_to(r.x, r.y + ry_tl);
        path.line_to(r.x, y1 - ry_bl);
        path.bezier_to(r.x, y1 - ry_bl * k, r.x + rx_bl * k, y1, r.x + rx_bl, y1);
        path.line_to(x1 - rx_br, y1);
        path.bezier_to(x1 - rx_br * k, y1, x1, y1 - ry_br * k, x1, y1 - ry_br);
        path.line_to(x1, r.y + ry_tr);
        path.bezier_to(x1, r.y + ry_tr * k, x1 - rx_tr * k, r.y, x1 - rx_tr, r.y);
        path.line_to(r.x + rx_tl, r.y);
        path.bezier_to(r.x + rx_tl * k, r.y, r.x, r.y + ry_tl * k, r.x, r.y + ry_tl);
        path.close();
    }

    /// 32 commands.
    pub fn circle(path: *Path, x: f32, y: f32, r: f32) void {
        path.ellipse(x, y, r, r);
    }

    /// 32 commands.
    pub fn ellipse(path: *Path, cx: f32, cy: f32, rx: f32, ry: f32) void {
        path.move_to(cx - rx, cy);
        path.bezier_to(cx - rx, cy + ry * kappa90, cx - rx * kappa90, cy + ry, cx, cy + ry);
        path.bezier_to(cx + rx * kappa90, cy + ry, cx + rx, cy + ry * kappa90, cx + rx, cy);
        path.bezier_to(cx + rx, cy - ry * kappa90, cx + rx * kappa90, cy - ry, cx, cy - ry);
        path.bezier_to(cx - rx * kappa90, cy - ry, cx - rx, cy - ry * kappa90, cx - rx, cy);
        path.close();
    }
};

pub fn init(arena: std.mem.Allocator) !void {
    vertex_data = .empty;

    current_path = Path.init(arena, 100_000) catch unreachable;

    fonts = std.ArrayList(FontAtlas).empty;

    gl.GenBuffers(1, @ptrCast(&vbo));

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform4f(shaders.gfx_shader.u_color, 1, 1, 1, 1);

    reset();
}

pub fn add_font(gpa: std.mem.Allocator, font_data: []const u8) !usize {
    try fonts.append(gpa, try FontAtlas.init(gpa, font_data));
    const font_id = fonts.items.len - 1;
    return font_id;
}

pub fn reset() void {
    state_index = 0;
    state_stack[0] = .{};

    stroke_width = 1;
    line_cap = .butt;
    line_join = .miter;
    miter_limit = 10;

    current_path.clear();

    gl.UseProgram(shaders.gfx_shader.program);
    gl.UniformMatrix4fv(shaders.gfx_shader.u_model, 1, gl.FALSE, @ptrCast(&la.identity()));
}

pub fn begin_frame(arena: std.mem.Allocator, pixel_ratio: f32) void {
    vertex_data = .empty;
    arena_frame = arena;

    device_pixel_ratio = pixel_ratio;
    tesselation_tolerance = 0.25 / device_pixel_ratio;
    distance_tolerance = 0.01 / device_pixel_ratio;

    reset();
}

pub fn save() void {
    assert(state_index + 1 < state_stack.len);
    state_index += 1;
    state_stack[state_index] = state_stack[state_index - 1];
}

pub fn restore() void {
    assert(state_index > 0);
    state_index -= 1;

    gl.UseProgram(shaders.gfx_shader.program);
    gl.UniformMatrix4fv(shaders.gfx_shader.u_model, 1, gl.FALSE, @ptrCast(&get_state().model));
}

fn get_state() *State {
    return &state_stack[state_index];
}

pub fn begin(projection: *const mat4, view: *const mat4) void {
    gl.UseProgram(shaders.gfx_shader.program);
    gl.UniformMatrix4fv(shaders.gfx_shader.u_projection, 1, gl.FALSE, @ptrCast(projection));
    gl.UniformMatrix4fv(shaders.gfx_shader.u_view, 1, gl.FALSE, @ptrCast(view));
}

pub fn transform(model: *const mat4) void {
    state_stack[state_index].model = la.mul(state_stack[state_index].model, model.*);
}

pub fn reset_transform() void {
    state_stack[state_index].model = la.identity();
}

pub fn begin_path() void {
    current_path.clear();
}

pub fn hole() void {
    current_path.hole();
}

pub fn close() void {
    current_path.close();
}

pub fn circle(x: f32, y: f32, r: f32) void {
    current_path.circle(x, y, r);
}

pub fn ellipse(cx: f32, cy: f32, rx: f32, ry: f32) void {
    current_path.ellipse(cx, cy, rx, ry);
}

pub fn set_color(color: Color) void {
    const state = &state_stack[state_index];
    state.color = color;
}

pub fn set_texture(id: gl.uint, src_rect: Rect) void {
    const state = get_state();
    state.texture = id;
    state.src_rect = .{ src_rect.x, src_rect.y, src_rect.w, src_rect.h };
}

pub fn set_gradient_linear(
    from: vec2,
    to: vec2,
    colors: []const Color,
    stops: []const f32,
    smooth: bool,
) void {
    assert(colors.len <= State.Gradient.count_max);
    assert(colors.len == stops.len);

    const large = 1e5;
    const state = get_state();

    state.gradient.count = @intCast(colors.len);
    for (colors, stops, 0..) |color, stop, i| {
        state.gradient.colors[i] = color;
        state.gradient.stops[i] = stop;
    }

    var dx = to[0] - from[0];
    var dy = to[1] - from[1];
    const d = @sqrt(dx * dx + dy * dy);
    if (d > 0.0001) {
        dx /= d;
        dy /= d;
    } else {
        dx = 0;
        dy = 1;
    }

    state.gradient.xform = la.identity3();
    // inverted
    state.gradient.xform[0][0] = dy;
    state.gradient.xform[0][1] = dx;
    state.gradient.xform[1][0] = -dx;
    state.gradient.xform[1][1] = dy;
    const t = .{
        from[0] - dx * large,
        from[1] - dy * large,
    };
    state.gradient.xform[2][0] = -(state.gradient.xform[0][0] * t[0] - state.gradient.xform[1][0] * t[1]);
    state.gradient.xform[2][1] = -(state.gradient.xform[0][1] * t[0] + state.gradient.xform[1][1] * t[1]);
    state.gradient.extents = .{
        large,
        large + d * 0.5,
    };
    state.gradient.radius = 0;
    state.gradient.feather = d;
    state.gradient.smooth = smooth;
}

pub fn set_gradient_radial(
    origin: vec2,
    radius_inner: f32,
    radius_outer: f32,
    colors: []const Color,
    stops: []const f32,
    smooth: bool,
) void {
    assert(colors.len <= State.Gradient.count_max);
    assert(colors.len == stops.len);

    const state = get_state();

    state.gradient.count = @intCast(colors.len);
    for (colors, stops, 0..) |color, stop, i| {
        state.gradient.colors[i] = color;
        state.gradient.stops[i] = stop;
    }

    const r = (radius_inner + radius_outer) * 0.5;
    state.gradient.xform = la.identity3();
    state.gradient.xform[2] = .{ -origin[0], -origin[1], 1 };
    state.gradient.extents = .{ r, r };
    state.gradient.radius = r;
    state.gradient.feather = radius_outer - radius_inner;
    state.gradient.smooth = smooth;
}

pub fn set_gradient_box(
    rect: Rect,
    radius: f32,
    feather: f32,
    colors: []const Color,
    stops: []const f32,
    smooth: bool,
) void {
    assert(colors.len <= State.Gradient.count_max);
    assert(colors.len == stops.len);

    const state = get_state();

    state.gradient.count = @intCast(colors.len);
    for (colors, stops, 0..) |color, stop, i| {
        state.gradient.colors[i] = color;
        state.gradient.stops[i] = stop;
    }

    state.gradient.xform = la.identity3();
    state.gradient.xform[2][0] = -(rect.x + 0.5 * rect.w);
    state.gradient.xform[2][1] = -(rect.y + 0.5 * rect.h);
    state.gradient.extents = .{ 0.5 * rect.w, 0.5 * rect.h };
    state.gradient.radius = radius;
    state.gradient.feather = feather; //@max(1, feather);
    state.gradient.smooth = smooth;
}

pub fn set_gradient_none() void {
    const state = get_state();
    state.gradient.count = 0;
}

pub fn set_font_id(id: u32) void {
    state_stack[state_index].font_id = id;
}

pub fn set_font_size(size: f32) void {
    state_stack[state_index].font_size = size;
}

pub fn set_stroke_width(width: f32) void {
    stroke_width = width;
}

pub fn stroke() void {
    stroke_path(&current_path);
}

pub fn stroke_path(path: *const Path) void {
    var cache = PathCache.init();

    cache.flatten_paths(path) catch unreachable;

    cache.expand_stroke(0.5 * stroke_width) catch unreachable;

    const state = get_state();
    state.set_uniforms();
    if (state.texture > 0) {
        gl.BindTexture(gl.TEXTURE_2D, state.texture);
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_rgba);
        gl.Uniform4fv(shaders.gfx_shader.u_src_rect, 1, &state.src_rect[0]);
    } else {
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_none);
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

    gl.Disable(gl.CULL_FACE);
    defer gl.Enable(gl.CULL_FACE);

    for (cache.paths.items) |sub_path| {
        gl.DrawArrays(gl.TRIANGLE_STRIP, @intCast(sub_path.vertex_offset), @intCast(sub_path.vertex_count));
    }
    gl.DisableVertexAttribArray(0);
}

pub fn stroke_rect(rect: Rect) !void {
    var rect_path: Path = try Path.init(arena_frame, 16);
    rect_path.rect(rect);
    stroke_path(&rect_path);
}

pub fn fill() void {
    fill_path(&current_path);
}

pub fn fill_path(path: *const Path) void {
    var cache = PathCache.init();
    cache.flatten_paths(path) catch unreachable;
    if (cache.paths.items.len == 0) return;

    cache.calculate_joins() catch unreachable;

    const state = get_state();
    state.set_uniforms();
    if (state.texture > 0) {
        gl.BindTexture(gl.TEXTURE_2D, state.texture);
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_rgba);
        gl.Uniform4fv(shaders.gfx_shader.u_src_rect, 1, &state.src_rect[0]);
    } else {
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_none);
    }

    // potential optimization
    // if (cache.paths.items.len == 1 and sub_path.convex) {
    //     gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
    // }

    gl.EnableVertexAttribArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);

    gl.Disable(gl.CULL_FACE);
    defer gl.Enable(gl.CULL_FACE);
    gl.Enable(gl.STENCIL_TEST);
    defer gl.Disable(gl.STENCIL_TEST);
    gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
    gl.StencilMask(0xFF);
    gl.StencilFunc(gl.ALWAYS, 0x00, 0xFF);
    gl.StencilOpSeparate(gl.FRONT, gl.KEEP, gl.KEEP, gl.INCR_WRAP);
    gl.StencilOpSeparate(gl.BACK, gl.KEEP, gl.KEEP, gl.DECR_WRAP);

    for (cache.paths.items) |sub_path| {
        vertex_data.clearRetainingCapacity();
        vertex_data.ensureTotalCapacity(arena_frame, 2 * sub_path.points.items.len) catch unreachable;
        for (sub_path.points.items) |point| {
            add_vertex(point.x, point.y);
        }

        gl.BufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertex_data.items.len * @sizeOf(f32)),
            vertex_data.items.ptr,
            gl.STREAM_DRAW,
        );
        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), 0);

        gl.DrawArrays(gl.TRIANGLE_FAN, 0, @intCast(sub_path.points.items.len));
    }

    // Draw fill
    gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);
    gl.StencilFunc(gl.NOTEQUAL, 0x00, 0x7F);
    gl.StencilOp(gl.ZERO, gl.ZERO, gl.ZERO);
    vertex_data.clearRetainingCapacity();
    add_vertex(cache.bounds[0], cache.bounds[1]);
    add_vertex(cache.bounds[0], cache.bounds[3]);
    add_vertex(cache.bounds[2], cache.bounds[3]);
    add_vertex(cache.bounds[2], cache.bounds[1]);
    gl.BufferData(
        gl.ARRAY_BUFFER,
        @intCast(vertex_data.items.len * @sizeOf(f32)),
        vertex_data.items.ptr,
        gl.STREAM_DRAW,
    );
    gl.DrawArrays(gl.TRIANGLE_FAN, 0, 4);

    gl.DisableVertexAttribArray(0);
}

pub fn fill_rect(rect: Rect) void {
    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(arena_frame, 4 * 4) catch return; // OOM

    vertex_data.appendSliceAssumeCapacity(&.{
        rect.x,          rect.y,
        rect.x,          rect.y + rect.h,
        rect.x + rect.w, rect.y + rect.h,
        rect.x + rect.w, rect.y,
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
    const state = get_state();
    state.set_uniforms();
    if (state.texture > 0) {
        gl.BindTexture(gl.TEXTURE_2D, state.texture);
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_rgba);
        gl.Uniform4fv(shaders.gfx_shader.u_src_rect, 1, &state.src_rect[0]);
    } else {
        gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_none);
    }
    gl.DrawArrays(gl.TRIANGLE_FAN, 0, 4);
    gl.DisableVertexAttribArray(0);
}

pub fn draw_texture(texture: gl.uint, rect: Rect) void {
    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(arena_frame, 6 * 4) catch return; // OOM

    const px0 = rect.x;
    const py0 = rect.y;
    const px1 = px0 + rect.w;
    const py1 = py0 + rect.h;
    const tcx0 = 0;
    const tcx1 = 1;
    const tcy0 = 0;
    const tcy1 = 1;
    vertex_data.appendSliceAssumeCapacity(&.{
        px0, py0, tcx0, tcy0,
        px1, py1, tcx1, tcy1,
        px1, py0, tcx1, tcy0,
        px0, py0, tcx0, tcy0,
        px0, py1, tcx0, tcy1,
        px1, py1, tcx1, tcy1,
    });

    gl.EnableVertexAttribArray(0);
    gl.EnableVertexAttribArray(1);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(vertex_data.items.len * @sizeOf(f32)), vertex_data.items.ptr, gl.STREAM_DRAW);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 2 * @sizeOf(f32));

    gl.UseProgram(shaders.gfx_shader.program);
    get_state().set_uniforms();
    gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_alpha);
    gl.BindTexture(gl.TEXTURE_2D, texture);
    gl.DrawArrays(gl.TRIANGLES, 0, 6);
    gl.DisableVertexAttribArray(1);
    gl.DisableVertexAttribArray(0);
}

// font stuff

pub fn draw_atlas(x: f32, y: f32) void {
    const font = &fonts.items[get_state().font_id];
    draw_texture(font.texture, .{ .x = x, .y = y, .w = FontAtlas.width / 2, .h = FontAtlas.height / 2 });
}

pub fn get_text_width(text: []const u8) f32 {
    const font = &fonts.items[get_state().font_id];
    const pixel_size = device_pixel_ratio * get_state().font_size;
    const ttf_scale = font.ttf.scaleForPixelHeight(pixel_size);

    var text_width: f32 = 0;

    var glyph_prev: ?TrueType.GlyphIndex = null;
    var it = std.unicode.Utf8View.initUnchecked(text).iterator();
    while (it.nextCodepoint()) |codepoint| {
        const glyph = font.ttf.codepointGlyphIndex(codepoint) orelse .notdef;
        defer glyph_prev = glyph;

        if (glyph_prev) |prev| {
            const advance: f32 = @floatFromInt(font.ttf.glyphKernAdvance(prev, glyph));
            text_width += ttf_scale * advance;
        }

        const metrics = font.ttf.glyphHMetrics(glyph);
        const advance: f32 = @floatFromInt(metrics.advance_width);
        text_width += ttf_scale * advance;
    }

    return text_width / device_pixel_ratio;
}

/// Find the character index that is closest to the x coordinate.
pub fn get_text_closest_index(text: []const u8, x: f32) usize {
    const font = &fonts.items[get_state().font_id];
    const pixel_size = device_pixel_ratio * get_state().font_size;
    const ttf_scale = font.ttf.scaleForPixelHeight(pixel_size);

    const device_x = x * device_pixel_ratio;
    var text_x: f32 = 0;
    var closest_distance: f32 = 1e6;
    var closest_index: usize = 0;

    var glyph_prev: ?TrueType.GlyphIndex = null;
    var it = std.unicode.Utf8View.initUnchecked(text).iterator();
    var index: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        const glyph = font.ttf.codepointGlyphIndex(codepoint) orelse .notdef;
        defer glyph_prev = glyph;

        const metrics = font.ttf.glyphHMetrics(glyph);
        const left_side_bearing: f32 = @floatFromInt(metrics.left_side_bearing);
        const character_x = text_x + ttf_scale * left_side_bearing;

        const distance = @abs(character_x - device_x);
        if (distance < closest_distance) {
            closest_distance = distance;
            closest_index = index;
        }

        if (glyph_prev) |prev| {
            const advance: f32 = @floatFromInt(font.ttf.glyphKernAdvance(prev, glyph));
            text_x += ttf_scale * advance;
        }

        const advance: f32 = @floatFromInt(metrics.advance_width);
        text_x += ttf_scale * advance;
        index += 1;
    }

    const distance = @abs(text_x - device_x);
    if (distance < closest_distance) {
        closest_distance = distance;
        closest_index = index;
    }

    return closest_index;
}

pub fn get_text_height() f32 {
    const font = &fonts.items[get_state().font_id];
    const ttf_scale = font.ttf.scaleForPixelHeight(get_state().font_size);
    const vmetrics = font.ttf.verticalMetrics();
    const ascent: f32 = @floatFromInt(vmetrics.ascent);
    const descent: f32 = @floatFromInt(vmetrics.descent);
    const line_gap: f32 = @floatFromInt(vmetrics.line_gap);
    return ttf_scale * (ascent - descent + line_gap);
}

pub fn draw_text(text: []const u8, x: f32, y: f32) void {
    const snap_pixels = true;
    const kerning = true;

    const font = &fonts.items[get_state().font_id];
    const pixel_size = device_pixel_ratio * get_state().font_size;
    const pixel_size_i: u11 = @intFromFloat(@round(pixel_size));
    const ttf_scale = font.ttf.scaleForPixelHeight(pixel_size);
    const font_scale = 1.0 / device_pixel_ratio;

    const vmetrics = font.ttf.verticalMetrics();
    const ascent: f32 = font_scale * ttf_scale * @as(f32, @floatFromInt(vmetrics.ascent));
    // const descent: f32 = font_scale * ttf_scale * @as(f32, @floatFromInt(vmetrics.descent));
    var x0 = x;
    var y0 = y + ascent;

    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(arena_frame, text.len * 6 * 4) catch unreachable;

    var it = std.unicode.Utf8View.initUnchecked(text).iterator();

    var glyph_prev: ?TrueType.GlyphIndex = null;
    while (it.nextCodepoint()) |codepoint| {
        if (codepoint == '\n') {
            y0 += font_scale * pixel_size; // TODO: + line_gap
            continue;
        }

        const glyph = font.ttf.codepointGlyphIndex(codepoint) orelse .notdef;
        defer glyph_prev = glyph;

        const character = font.get_character(pixel_size_i, codepoint) catch @panic("char");

        if (kerning) {
            if (glyph_prev) |prev| {
                const advance: f32 = @floatFromInt(font.ttf.glyphKernAdvance(prev, glyph));
                x0 += font_scale * ttf_scale * advance;
            }
        }

        var px0 = x0 + font_scale * character.left_side_bearing;
        var py0 = y0 + font_scale * character.offset_y;
        if (snap_pixels) {
            px0 = @round(px0 / font_scale) * font_scale;
            py0 = @round(py0 / font_scale) * font_scale;
        }
        const px1 = px0 + font_scale * character.box.w;
        const py1 = py0 + font_scale * character.box.h;
        const tcx0 = character.box.x / FontAtlas.width;
        const tcx1 = tcx0 + character.box.w / FontAtlas.width;
        const tcy0 = character.box.y / FontAtlas.height;
        const tcy1 = tcy0 + character.box.h / FontAtlas.height;

        vertex_data.appendSliceAssumeCapacity(&.{
            px0, py0, tcx0, tcy0,
            px1, py1, tcx1, tcy1,
            px1, py0, tcx1, tcy0,
            px0, py0, tcx0, tcy0,
            px0, py1, tcx0, tcy1,
            px1, py1, tcx1, tcy1,
        });

        x0 += font_scale * character.advance_width;
    }

    gl.EnableVertexAttribArray(0);
    gl.EnableVertexAttribArray(1);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(vertex_data.items.len * @sizeOf(f32)), vertex_data.items.ptr, gl.STREAM_DRAW);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 2 * @sizeOf(f32));

    get_state().set_uniforms();
    gl.Uniform1i(shaders.gfx_shader.u_colormap_type, colormap_type_alpha);
    font.bind_texture();
    gl.DrawArrays(gl.TRIANGLES, 0, @intCast(vertex_data.items.len / 4));
    gl.DisableVertexAttribArray(1);
    gl.DisableVertexAttribArray(0);
}

const PathPoint = struct {
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

    fn eql(self: PathPoint, other: PathPoint) bool {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return dx * dx + dy * dy < distance_tolerance * distance_tolerance;
    }
};

const PathCache = struct {
    paths: std.ArrayListUnmanaged(FlattenedPath),
    bounds: [4]f32 = .{ 1e6, 1e6, -1e6, -1e6 },

    const FlattenedPath = struct {
        points: std.ArrayListUnmanaged(PathPoint),
        closed: bool,
        nbevel: usize,
        winding: enum { ccw, cw },
        convex: bool,
        vertex_offset: usize,
        vertex_count: usize,

        fn init() FlattenedPath {
            return .{
                .points = .initBuffer(&.{}),
                .closed = false,
                .nbevel = 0,
                .winding = .ccw,
                .convex = false,
                .vertex_offset = 0,
                .vertex_count = 0,
            };
        }

        fn add_point(path: *FlattenedPath, point: PathPoint) !void {
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

    fn add_point(cache: *PathCache, x: f32, y: f32, flags: PathPoint.Flags) !void {
        const path = &cache.paths.items[cache.paths.items.len - 1];

        var point = std.mem.zeroes(PathPoint);
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

    fn last_point(cache: *const PathCache) PathPoint {
        return cache.paths.getLast().points.getLast();
    }

    fn reverse_path_winding(cache: *const PathCache) void {
        cache.paths.items[cache.paths.items.len - 1].winding = .cw;
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
                .hole => {
                    cache.reverse_path_winding();
                    i += 1;
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
        flags: PathPoint.Flags,
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
        try vertex_data.ensureUnusedCapacity(arena_frame, 2 * cverts);

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

    fn bevel_join(p0: PathPoint, p1: PathPoint, lw: f32, rw: f32) void {
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

    fn butt_cap_start(p: PathPoint, dx: f32, dy: f32, w: f32, d: f32) void {
        const px = p.x - dx * d;
        const py = p.y - dy * d;
        const dlx = dy;
        const dly = -dx;
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
    }

    fn butt_cap_end(p: PathPoint, dx: f32, dy: f32, w: f32, d: f32) void {
        const px = p.x + dx * d;
        const py = p.y + dy * d;
        const dlx = dy;
        const dly = -dx;
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
        add_vertex(px + dlx * w, py + dly * w);
        add_vertex(px - dlx * w, py - dly * w);
    }

    fn round_cap_start(p: PathPoint, dx: f32, dy: f32, w: f32, ncap: u32) void {
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

    fn round_cap_end(p: PathPoint, dx: f32, dy: f32, w: f32, ncap: u32) void {
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

            // Enforce winding.
            if (path.points.items.len > 2) {
                if (path.winding == .cw) {
                    std.mem.reverse(PathPoint, path.points.items);
                }
            }

            var p0 = &path.points.items[path.points.items.len - 1];
            for (path.points.items) |*p1| {
                defer p0 = p1;
                // Calculate segment direction and length
                p0.dx = p1.x - p0.x;
                p0.dy = p1.y - p0.y;
                p0.len = normalize(&p0.dx, &p0.dy);
                // Update bounds
                cache.bounds[0] = @min(cache.bounds[0], p0.x);
                cache.bounds[1] = @min(cache.bounds[1], p0.y);
                cache.bounds[2] = @max(cache.bounds[2], p0.x);
                cache.bounds[3] = @max(cache.bounds[3], p0.y);
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

fn choose_bevel(bevel: bool, p0: PathPoint, p1: PathPoint, w: f32, x0: *f32, y0: *f32, x1: *f32, y1: *f32) void {
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
