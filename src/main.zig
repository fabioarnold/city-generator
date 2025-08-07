const std = @import("std");
const sdl = @import("sdl3");
const gl = @import("gl");
const la = @import("linear_algebra.zig");
const tiles = @import("tiles/tiles.zig");
const vec4 = la.vec4;

const GLTile = struct {
    vbo: gl.uint,
    ebo: gl.uint,
    ibo: gl.uint,
    index_count: gl.sizei,
    instance_count: gl.sizei,
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    var arena_instance: std.heap.ArenaAllocator = .init(gpa.allocator());
    const arena = arena_instance.allocator();

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

    const tile_array = [_]tiles.Tile{ tiles.street, tiles.curb };
    var gl_tiles: [tile_array.len]GLTile = undefined;

    const tilemap: [4][4]u8 = .{
        .{ 0, 0, 2, 0 },
        .{ 0, 1, 2, 0 },
        .{ 0, 1, 2, 1 },
        .{ 0, 1, 2, 0 },
    };

    // per tile instance data
    var tile_instance_data: [tile_array.len]std.ArrayList(vec4) = undefined;
    for (&tile_instance_data) |*i| i.* = .init(arena);
    for (0..tilemap.len) |row| {
        for (0..tilemap[row].len) |col| {
            const i = tilemap[row][col];
            if (i == 0) continue;
            try tile_instance_data[i - 1].append(.{ @floatFromInt(col), @floatFromInt(row), 0, 0 });
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
        gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(instance_data.items.len * @sizeOf(vec4)), instance_data.items.ptr, gl.STATIC_DRAW);
        gl_tile.* = .{
            .vbo = vbo,
            .ebo = ebo,
            .ibo = ibo,
            .index_count = @intCast(tile.index_data.len),
            .instance_count = @intCast(instance_data.items.len),
        };
    }

    var texture: gl.uint = undefined;
    gl.GenTextures(1, @ptrCast(&texture));
    gl.BindTexture(gl.TEXTURE_2D, texture);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, tiles.image.width, tiles.image.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, tiles.image.pixels);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    const shader = gl.CreateProgram();
    const shader_vs = gl.CreateShader(gl.VERTEX_SHADER);
    const shader_vs_src =
        \\#version 410
        \\layout(location = 0) in vec3 a_position;
        \\layout(location = 1) in vec2 a_texcoord;
        \\layout(location = 2) in vec4 a_transform;
        \\out vec2 v_texcoord;
        \\void main() {
        \\  v_texcoord = a_texcoord / vec2(64.0, 168.0);
        \\  gl_Position = vec4((a_position/8.0 + a_transform.xyz - vec3(2.0,2.0,0.0)) * vec3(0.2, 0.4, 1.0), 1.0);
        \\}
    ;
    gl.ShaderSource(shader_vs, 1, &.{shader_vs_src}, null);
    const shader_fs = gl.CreateShader(gl.FRAGMENT_SHADER);
    const shader_fs_src =
        \\#version 410
        \\uniform sampler2D colormap;
        \\in vec2 v_texcoord;
        \\out vec4 out_color;
        \\void main() {
        \\  out_color = texture(colormap, v_texcoord);
        \\  if (out_color.a == 0) discard;
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

    // const projection = la.ortho();

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
        gl.EnableVertexAttribArray(0);
        gl.EnableVertexAttribArray(1);
        gl.EnableVertexAttribArray(2);
        gl.VertexAttribDivisor(2, 1);
        for (gl_tiles) |gl_tile| {
            gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.vbo);
            gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 0);
            gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 3 * @sizeOf(f32));
            gl.BindBuffer(gl.ARRAY_BUFFER, gl_tile.ibo);
            gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_tile.ebo);
            gl.DrawElementsInstanced(gl.TRIANGLES, gl_tile.index_count, gl.UNSIGNED_SHORT, null, gl_tile.instance_count);
        }

        try sdl.video.gl.swapWindow(window);
    }
}
