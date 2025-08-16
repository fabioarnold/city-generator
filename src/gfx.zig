const std = @import("std");
const gl = @import("gl");
const shaders = @import("shaders.zig");
const la = @import("linear_algebra.zig");
const vec4 = la.vec4;
const mat4 = la.mat4;

var vertex_data: std.ArrayList(f32) = undefined;
var vbo: gl.uint = undefined;
var font_texture: gl.uint = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    vertex_data = std.ArrayList(f32).init(allocator);

    gl.GenTextures(1, @ptrCast(&font_texture));
    gl.BindTexture(gl.TEXTURE_2D, font_texture);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 128, 64, 0, gl.RGBA, gl.UNSIGNED_BYTE, @embedFile("fonts/font.raw"));
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    gl.GenBuffers(1, @ptrCast(&vbo));

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform4f(shaders.gfx_shader.color_loc, 1, 1, 1, 1);
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

pub fn draw_rect(x: f32, y: f32, w: f32, h: f32) void {
    vertex_data.clearRetainingCapacity();
    vertex_data.ensureTotalCapacity(6 * 4 * @sizeOf(f32)) catch return; // OOM

    vertex_data.appendSliceAssumeCapacity(&.{
        x,     y,
        x + w, y,
        x + w, y + h,
        x,     y,
        x + w, y + h,
        x,     y + h,
    });

    gl.EnableVertexAttribArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(vertex_data.items.len * @sizeOf(f32)), vertex_data.items.ptr, gl.STREAM_DRAW);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), 0);

    gl.UseProgram(shaders.gfx_shader.program);
    gl.Uniform1i(shaders.gfx_shader.colormap_enabled_loc, 0);
    gl.DrawArrays(gl.TRIANGLES, 0, 6);
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
