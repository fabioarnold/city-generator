const std = @import("std");
const sdl = @import("sdl3");
const gl = @import("gl");

pub fn main() !void {
    try sdl.init(.{ .video = true });
    defer sdl.shutdown();

    const window = try sdl.video.Window.init("City", 1280, 720, .{ .open_gl = true, .resizable = true });
    defer window.deinit();

    try sdl.video.gl.setAttribute(.context_minor_version, 1);
    try sdl.video.gl.setAttribute(.context_profile_mask, @intFromEnum(sdl.video.gl.Profile.core));
    const context = try sdl.video.gl.Context.init(window);
    defer context.deinit() catch {};

    var procs: gl.ProcTable = undefined;
    _ = procs.init(struct {
        fn address(proc: [*:0]const u8) ?*align(4) const anyopaque {
            return @alignCast(@ptrCast(sdl.video.gl.getProcAddress(std.mem.sliceTo(proc, 0))));
        }
    }.address);
    gl.makeProcTableCurrent(&procs);

    // VAO is required for OpenGL core profile.
    var vao_dummy: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao_dummy));
    gl.BindVertexArray(vao_dummy);

    const vertex_data = [9]f32{
        -0.5, -0.5, 0,
        0.5,  -0.5, 0,
        0,    0.5,  0,
    };
    var vbo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, vertex_data.len * @sizeOf(f32), @ptrCast(&vertex_data), gl.STATIC_DRAW);

    const shader = gl.CreateProgram();
    const shader_vs = gl.CreateShader(gl.VERTEX_SHADER);
    const shader_vs_src =
        \\#version 410
        \\in vec3 a_position;
        \\void main() {
        \\  gl_Position = vec4(a_position, 1.0);
        \\}
    ;
    gl.ShaderSource(shader_vs, 1, &.{shader_vs_src}, null);
    const shader_fs = gl.CreateShader(gl.FRAGMENT_SHADER);
    const shader_fs_src =
        \\#version 410
        \\out vec4 out_color;
        \\void main() {
        \\  out_color = vec4(1.0);
        \\}
    ;
    gl.CompileShader(shader_vs);
    var info_buffer: [10_000]u8 = undefined;
    var info_len: gl.int = undefined;
    gl.GetShaderInfoLog(shader_vs, info_buffer.len, &info_len, &info_buffer);
    std.debug.print("compile log:\n{s}\n", .{info_buffer[0..@intCast(info_len)]});
    gl.AttachShader(shader, shader_vs);
    gl.ShaderSource(shader_fs, 1, &.{shader_fs_src}, null);
    gl.CompileShader(shader_fs);
    gl.GetShaderInfoLog(shader_fs, info_buffer.len, &info_len, &info_buffer);
    std.debug.print("compile log:\n{s}\n", .{info_buffer[0..@intCast(info_len)]});
    gl.AttachShader(shader, shader_fs);
    gl.LinkProgram(shader);
    gl.UseProgram(shader);

    mainloop: while (true) {
        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit => break :mainloop,
                .key_down => |key| if (key.key == .escape) break :mainloop,
                else => {},
            }
        }

        gl.ClearColor(0.2, 0.4, 0.6, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        gl.UseProgram(shader);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), 0);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);

        try sdl.video.gl.swapWindow(window);
    }
}
