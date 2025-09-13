const gl = @import("gl");

const GBuffer = @This();

fbo: gl.uint,
tex_color: gl.uint,
rbo_depth: gl.uint,
width: u16,
height: u16,

pub fn init(width: u16, height: u16) GBuffer {
    return GBuffer{
        .fbo = 0,
        .tex_color = 0,
        .rbo_depth = 0,
        .width = width,
        .height = height,
    };
}

pub fn create(gbuffer: *GBuffer) !void {
    gl.GenFramebuffers(1, @ptrCast(&gbuffer.fbo));
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo);

    // // Position color buffer
    // var texPosition: u32 = undefined;
    // gl.GenTextures(1, &texPosition);
    // gl.BindTexture(gl.TEXTURE_2D, texPosition);
    // gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, null);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    // gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texPosition, 0);

    // // Normal color buffer
    // var texNormal: u32 = undefined;
    // gl.GenTextures(1, &texNormal);
    // gl.BindTexture(gl.TEXTURE_2D, texNormal);
    // gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB16F, width, height, 0, gl.RGB, gl.FLOAT, null);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    // gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, texNormal, 0);

    // Albedo color buffer
    gl.GenTextures(1, @ptrCast(&gbuffer.tex_color));
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_color);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gbuffer.width, gbuffer.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, gbuffer.tex_color, 0);

    // Tell OpenGL which color attachments we’ll draw into
    // gl.DrawBuffers(1, &.{gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1});

    // Depth renderbuffer
    gl.GenRenderbuffers(1, @ptrCast(&gbuffer.rbo_depth));
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_depth);
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, gbuffer.width, gbuffer.height);
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, gbuffer.rbo_depth);

    if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.FramebufferIncomplete;
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
}

pub fn resize(gbuffer: *GBuffer, width: u16, height: u16) void {
    if (width == gbuffer.width and height == gbuffer.height) return;
    gbuffer.width = width;
    gbuffer.height = height;

    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_color);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gbuffer.width, gbuffer.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);

    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_depth);
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, gbuffer.width, gbuffer.height);
}

pub fn begin(gbuffer: *GBuffer) void {
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo);
    gl.Viewport(0, 0, gbuffer.width, gbuffer.height);
}

pub fn end(gbuffer: *GBuffer) void {
    _ = gbuffer;
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
}
