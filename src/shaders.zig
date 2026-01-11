const std = @import("std");
const log = std.log.scoped(.shaders);
const gl = @import("gl");
const la = @import("linear_algebra.zig");

pub const debug_shader = struct {
    pub var program: gl.uint = undefined;
    pub var u_projection: gl.int = undefined;
    pub var u_view: gl.int = undefined;
    pub var u_model: gl.int = undefined;
};

pub const blit_shader = struct {
    pub var program: gl.uint = undefined;
    pub var u_texture: gl.int = undefined;
};

pub const gfx_shader = struct {
    pub var program: gl.uint = undefined;
    pub var u_projection: gl.int = undefined;
    pub var u_view: gl.int = undefined;
    pub var u_model: gl.int = undefined;
    pub var u_color: gl.int = undefined;
    pub var u_colormap_type: gl.int = undefined;
    pub var u_src_rect: gl.int = undefined;
    pub var u_gradient_colors: gl.int = undefined;
    pub var u_gradient_stops: gl.int = undefined;
    pub var u_gradient_count: gl.int = undefined;
    pub var u_gradient_xform: gl.int = undefined;
    pub var u_gradient_extents: gl.int = undefined;
    pub var u_gradient_radius: gl.int = undefined;
    pub var u_gradient_feather: gl.int = undefined;
    pub var u_gradient_smooth: gl.int = undefined;
};

pub const tile_shader = struct {
    pub var program: gl.uint = undefined;
    pub var u_projection: gl.int = undefined;
    pub var u_view: gl.int = undefined;
    pub var u_light_dir: gl.int = undefined;
};

pub const default = struct {
    pub var program: gl.uint = undefined;
    pub var u_projection: gl.int = undefined;
    pub var u_view: gl.int = undefined;
    pub var u_model: gl.int = undefined;
};

pub const cavity = struct {
    pub var program: gl.uint = undefined;
    pub var u_pixel: gl.int = undefined;
};

pub fn load() !void {
    {
        debug_shader.program = try load_shader(@embedFile("shaders/position.vert"), @embedFile("shaders/debug.frag"));
        gl.UseProgram(debug_shader.program);
        debug_shader.u_projection = gl.GetUniformLocation(debug_shader.program, "u_projection");
        debug_shader.u_view = gl.GetUniformLocation(debug_shader.program, "u_view");
        debug_shader.u_model = gl.GetUniformLocation(debug_shader.program, "u_model");
    }
    {
        blit_shader.program = try load_shader(@embedFile("shaders/blit.vert"), @embedFile("shaders/blit.frag"));
        gl.UseProgram(blit_shader.program);
        blit_shader.u_texture = gl.GetUniformLocation(blit_shader.program, "u_texture");
        gl.Uniform1i(blit_shader.u_texture, 0);
    }
    {
        gfx_shader.program = try load_shader(@embedFile("shaders/gfx.vert"), @embedFile("shaders/gfx.frag"));
        gl.UseProgram(gfx_shader.program);
        gfx_shader.u_projection = gl.GetUniformLocation(gfx_shader.program, "u_projection");
        gfx_shader.u_view = gl.GetUniformLocation(gfx_shader.program, "u_view");
        gfx_shader.u_model = gl.GetUniformLocation(gfx_shader.program, "u_model");
        gfx_shader.u_color = gl.GetUniformLocation(gfx_shader.program, "u_color");
        gfx_shader.u_colormap_type = gl.GetUniformLocation(gfx_shader.program, "u_colormap_type");
        const u_colormap = gl.GetUniformLocation(gfx_shader.program, "u_colormap");
        gl.Uniform1i(u_colormap, 0);
        gfx_shader.u_src_rect = gl.GetUniformLocation(gfx_shader.program, "u_src_rect");

        gfx_shader.u_gradient_colors = gl.GetUniformLocation(gfx_shader.program, "u_gradient_colors");
        gfx_shader.u_gradient_stops = gl.GetUniformLocation(gfx_shader.program, "u_gradient_stops");
        gfx_shader.u_gradient_count = gl.GetUniformLocation(gfx_shader.program, "u_gradient_count");
        gfx_shader.u_gradient_xform = gl.GetUniformLocation(gfx_shader.program, "u_gradient_xform");
        gfx_shader.u_gradient_extents = gl.GetUniformLocation(gfx_shader.program, "u_gradient_extents");
        gfx_shader.u_gradient_radius = gl.GetUniformLocation(gfx_shader.program, "u_gradient_radius");
        gfx_shader.u_gradient_feather = gl.GetUniformLocation(gfx_shader.program, "u_gradient_feather");
        gfx_shader.u_gradient_smooth = gl.GetUniformLocation(gfx_shader.program, "u_gradient_smooth");
    }
    {
        default.program = try load_shader(@embedFile("shaders/default.vert"), @embedFile("shaders/default.frag"));
        gl.UseProgram(default.program);
        default.u_projection = gl.GetUniformLocation(default.program, "u_projection");
        default.u_view = gl.GetUniformLocation(default.program, "u_view");
        default.u_model = gl.GetUniformLocation(default.program, "u_model");
        gl.Uniform1i(gl.GetUniformLocation(default.program, "u_colormap"), 0);
    }
    {
        cavity.program = try load_shader(@embedFile("shaders/blit.vert"), @embedFile("shaders/cavity.frag"));
        gl.UseProgram(cavity.program);
        gl.Uniform1i(gl.GetUniformLocation(cavity.program, "u_colormap"), 0);
        gl.Uniform1i(gl.GetUniformLocation(cavity.program, "u_normalmap"), 1);
        gl.Uniform1i(gl.GetUniformLocation(cavity.program, "u_depthmap"), 2);
        cavity.u_pixel = gl.GetUniformLocation(cavity.program, "u_pixel");
    }
    {
        tile_shader.program = try load_shader(@embedFile("shaders/tile.vert"), @embedFile("shaders/tile.frag"));
        gl.UseProgram(tile_shader.program);
        tile_shader.u_projection = gl.GetUniformLocation(tile_shader.program, "u_projection");
        tile_shader.u_view = gl.GetUniformLocation(tile_shader.program, "u_view");
        tile_shader.u_light_dir = gl.GetUniformLocation(tile_shader.program, "u_light_dir");
        gl.Uniform3f(tile_shader.u_light_dir, 0.2, 0.5, -1);
    }
}

fn load_shader(vertex_shader_source: []const u8, fragment_shader_source: []const u8) !gl.uint {
    var success: gl.int = undefined;
    var info_buffer: [512]u8 = undefined;
    var info_length: gl.int = 0;

    const preamble = if (gl.info.api == .gles)
        \\#version 300 es
        \\precision highp int;
        \\precision highp float;
        \\
    else
        \\#version 410
        \\
    ;

    const program = gl.CreateProgram();
    const types: []const gl.uint = &.{ gl.VERTEX_SHADER, gl.FRAGMENT_SHADER };
    const sources: []const []const u8 = &.{ vertex_shader_source, fragment_shader_source };
    for (types, sources) |@"type", source| {
        const shader = gl.CreateShader(@"type");
        gl.ShaderSource(
            shader,
            2,
            &.{ preamble, source.ptr },
            &.{ @intCast(preamble.len), @intCast(source.len) },
        );
        gl.CompileShader(shader);
        gl.GetShaderiv(shader, gl.COMPILE_STATUS, @ptrCast(&success));
        if (success == 0) {
            gl.GetShaderInfoLog(shader, info_buffer.len, &info_length, &info_buffer);
            if (info_length > 0) {
                const info_log = info_buffer[0..@intCast(info_length)];
                log.err("shader compilation failed:\n{s}", .{info_log});
                return error.ShaderCompileFailed;
            }
        }
        gl.AttachShader(program, shader);
    }
    gl.LinkProgram(program);
    gl.GetProgramiv(program, gl.LINK_STATUS, @ptrCast(&success));
    if (success == 0) {
        gl.GetProgramInfoLog(program, info_buffer.len, &info_length, &info_buffer);
        if (info_length > 0) {
            const info_log = info_buffer[0..@intCast(info_length)];
            log.err("program linking failed:\n{s}", .{info_log});
            return error.ProgramLinkFailed;
        }
    }

    return program;
}
