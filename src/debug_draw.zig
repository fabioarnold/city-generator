const gl = @import("gl");
const shaders = @import("shaders.zig");
const la = @import("linear_algebra.zig");
const mat4 = la.mat4;

var quad_vbo: gl.uint = undefined;

pub fn init() void {
    gl.GenBuffers(1, @ptrCast(&quad_vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, quad_vbo);
    const quad_data = [_]f32{ 0, 0, 1, 0, 0, 1, 1, 1 };
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(quad_data)), &quad_data, gl.STATIC_DRAW);
}

pub fn begin(projection: *const mat4, view: *const mat4) void {
    gl.UseProgram(shaders.debug_shader.program);
    gl.UniformMatrix4fv(shaders.debug_shader.projection_loc, 1, gl.FALSE, @ptrCast(projection));
    gl.UniformMatrix4fv(shaders.debug_shader.view_loc, 1, gl.FALSE, @ptrCast(view));
}

pub fn quad(model: *const mat4) void {
    gl.UniformMatrix4fv(shaders.debug_shader.model_loc, 1, gl.FALSE, @ptrCast(model));
    gl.EnableVertexAttribArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, quad_vbo);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 0, 0);
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4);
}
