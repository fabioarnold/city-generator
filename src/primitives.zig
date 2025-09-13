const gl = @import("gl");
const shaders = @import("shaders.zig");
const la = @import("linear_algebra.zig");
const mat4 = la.mat4;

var quad_vbo: gl.uint = undefined;

pub fn init() void {
    gl.GenBuffers(1, @ptrCast(&quad_vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, quad_vbo);
    const quad_data = [_]f32{ -1, -1, 1, -1, -1, 1, 1, 1 };
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(quad_data)), &quad_data, gl.STATIC_DRAW);
}

pub fn quad() void {
    gl.EnableVertexAttribArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, quad_vbo);
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 0, 0);
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4);
}
