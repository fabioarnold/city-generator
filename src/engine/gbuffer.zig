const gl = @import("gl");

const GBuffer = @This();

fbo: gl.uint,
tex_color: gl.uint,
tex_normal: gl.uint,
tex_depth: gl.uint,
fbo_msaa: gl.uint,
rbo_msaa: gl.uint,
rbo_depth: gl.uint,
rbo_normal: gl.uint,
width: u16,
height: u16,

pub fn init(width: u16, height: u16) GBuffer {
    return GBuffer{
        .fbo = 0,
        .tex_color = 0,
        .tex_normal = 0,
        .tex_depth = 0,
        .fbo_msaa = 0,
        .rbo_msaa = 0,
        .rbo_normal = 0,
        .rbo_depth = 0,
        .width = width,
        .height = height,
    };
}

pub fn create(gbuffer: *GBuffer) !void {
    const samples = 4;

    // Anti aliasing
    gl.GenFramebuffers(1, @ptrCast(&gbuffer.fbo_msaa));
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo_msaa);

    // Color
    gl.GenRenderbuffers(1, @ptrCast(&gbuffer.rbo_msaa));
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_msaa);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, 4, gl.RGBA8, gbuffer.width, gbuffer.height);
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, gbuffer.rbo_msaa);

    // Normal
    gl.GenRenderbuffers(1, @ptrCast(&gbuffer.rbo_normal));
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_normal);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA8, gbuffer.width, gbuffer.height);
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.RENDERBUFFER, gbuffer.rbo_normal);

    // Depth renderbuffer
    gl.GenRenderbuffers(1, @ptrCast(&gbuffer.rbo_depth));
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_depth);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, 4, gl.DEPTH_COMPONENT32F, gbuffer.width, gbuffer.height);
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, gbuffer.rbo_depth);

    gl.DrawBuffers(2, &.{ gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1 });

    if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.FramebufferIncomplete;
    }

    // Framebuffer for resolve.
    gl.GenFramebuffers(1, @ptrCast(&gbuffer.fbo));
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo);

    // Albedo color buffer
    gl.GenTextures(1, @ptrCast(&gbuffer.tex_color));
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_color);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gbuffer.width, gbuffer.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, gbuffer.tex_color, 0);

    gl.GenTextures(1, @ptrCast(&gbuffer.tex_normal));
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_normal);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gbuffer.width, gbuffer.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, gbuffer.tex_normal, 0);
    gl.DrawBuffers(2, &.{ gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1 });

    gl.GenTextures(1, @ptrCast(&gbuffer.tex_depth));
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_depth);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT32F, gbuffer.width, gbuffer.height, 0, gl.DEPTH_COMPONENT, gl.FLOAT, null);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, gbuffer.tex_depth, 0);

    // gl.DrawBuffers(2, &.{ gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1 });

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
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_normal);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gbuffer.width, gbuffer.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.BindTexture(gl.TEXTURE_2D, gbuffer.tex_depth);
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT32F, gbuffer.width, gbuffer.height, 0, gl.DEPTH_COMPONENT, gl.FLOAT, null);

    const samples = 4;
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_msaa);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA8, gbuffer.width, gbuffer.height);
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_normal);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA8, gbuffer.width, gbuffer.height);
    gl.BindRenderbuffer(gl.RENDERBUFFER, gbuffer.rbo_depth);
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.DEPTH_COMPONENT32F, gbuffer.width, gbuffer.height);
}

pub fn begin(gbuffer: *GBuffer) void {
    gl.BindFramebuffer(gl.FRAMEBUFFER, gbuffer.fbo_msaa);
    gl.Viewport(0, 0, gbuffer.width, gbuffer.height);
}

pub fn end(gbuffer: *GBuffer) void {
    gl.BindFramebuffer(gl.READ_FRAMEBUFFER, gbuffer.fbo_msaa);
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, gbuffer.fbo);
    gl.FramebufferRenderbuffer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, gbuffer.rbo_msaa);
    gl.DrawBuffers(1, &.{gl.COLOR_ATTACHMENT0});
    gl.BlitFramebuffer(0, 0, gbuffer.width, gbuffer.height, 0, 0, gbuffer.width, gbuffer.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
    gl.FramebufferRenderbuffer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, gbuffer.rbo_normal);
    gl.FramebufferRenderbuffer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.RENDERBUFFER, 0);
    gl.DrawBuffers(2, &.{ gl.NONE, gl.COLOR_ATTACHMENT1 });
    gl.BlitFramebuffer(0, 0, gbuffer.width, gbuffer.height, 0, 0, gbuffer.width, gbuffer.height, gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT, gl.NEAREST);
    gl.FramebufferRenderbuffer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, gbuffer.rbo_msaa);
    gl.FramebufferRenderbuffer(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.RENDERBUFFER, gbuffer.rbo_normal);
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
}
