const std = @import("std");
const sdl = @import("sdl3");
const gl = @import("gl");
const la = @import("linear_algebra.zig");
const tiles = @import("tiles/tiles.zig");
const vec4 = la.vec4;

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
    var vertex_data_offsets: std.ArrayList(u32) = try .initCapacity(arena, tile_array.len);
    var index_data_offsets: std.ArrayList(u32) = try .initCapacity(arena, tile_array.len);
    const vertex_data_total, const index_data_total = blk: {
        var vertex_data_count: u32 = 0;
        var index_data_count: u32 = 0;
        for (&tile_array) |tile| {
            vertex_data_offsets.appendAssumeCapacity(vertex_data_count);
            index_data_offsets.appendAssumeCapacity(index_data_count);
            vertex_data_count += @intCast(tile.vertex_data.len);
            index_data_count += @intCast(tile.index_data.len);
        }
        break :blk .{ vertex_data_count, index_data_count };
    };
    var vertex_data: std.ArrayList(f32) = try .initCapacity(arena, vertex_data_total);
    var index_data: std.ArrayList(u16) = try .initCapacity(arena, index_data_total);
    inline for (&tile_array) |tile| {
        vertex_data.appendSliceAssumeCapacity(tile.vertex_data);
        index_data.appendSliceAssumeCapacity(tile.index_data);
    }

    const tilemap: [4][4]u8 = .{
        .{ 0, 0, 2, 0 },
        .{ 0, 1, 2, 0 },
        .{ 0, 1, 2, 1 },
        .{ 0, 1, 2, 0 },
    };

    // per tile instance data
    var instance_data: [tile_array.len]std.ArrayList(vec4) = undefined;
    for (&instance_data) |*i| i.* = .init(arena);
    for (0..tilemap.len) |row| {
        for (0..tilemap[row].len) |col| {
            const i = tilemap[row][col];
            if (i == 0) continue;
            try instance_data[i - 1].append(.{ @floatFromInt(col), @floatFromInt(row), 0, 0 });
        }
    }

    var vbo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(vertex_data.items.len * @sizeOf(f32)), vertex_data.items.ptr, gl.STATIC_DRAW);
    var ebo: gl.uint = undefined;
    gl.GenBuffers(1, @ptrCast(&ebo));
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(index_data.items.len * @sizeOf(u16)), index_data.items.ptr, gl.STATIC_DRAW);
    var ibos: [instance_data.len]gl.uint = undefined;
    gl.GenBuffers(ibos.len, &ibos);
    for (&instance_data, ibos) |id, ibo| {
        gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(id.items.len * @sizeOf(vec4)), id.items.ptr, gl.STATIC_DRAW);
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
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 0);
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), 3 * @sizeOf(f32));
        for (0.., ibos, &instance_data) |i, ibo, id| {
            _ = i;
            gl.BindBuffer(gl.ARRAY_BUFFER, ibo);
            gl.EnableVertexAttribArray(2);
            gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
            gl.VertexAttribDivisor(2, 1);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
            gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, null, @intCast(id.items.len));
        }

        try sdl.video.gl.swapWindow(window);
    }
}
