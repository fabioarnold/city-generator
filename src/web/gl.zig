const std = @import("std");

//
// Datatypes
//

pub const GLenum = c_uint;
pub const GLboolean = u8;
pub const GLbitfield = c_uint;
pub const GLvoid = anyopaque;
pub const GLbyte = i8; // 1-byte signed
pub const GLshort = c_short; // 2-byte signed
pub const GLint = c_int; // 4-byte signed
pub const GLubyte = u8; // 1-byte unsigned
pub const GLushort = c_ushort; // 2-byte unsigned
pub const GLuint = c_uint; // 4-byte unsigned
pub const GLsizei = c_int; // 4-byte signed
pub const GLfloat = f32; // single precision float
pub const GLclampf = f32; // single precision float in [0,1]
pub const GLdouble = f64; // double precision float
pub const GLclampd = f64; // double precision float in [0,1]
pub const GLchar = u8;
pub const GLsizeiptr = c_long;
pub const GLintptr = c_long;

//
// Constants
//

// Boolean values
pub const GL_FALSE = 0;
pub const GL_TRUE = 1;

// Data types
pub const GL_UNSIGNED_BYTE = 0x1401;
pub const GL_UNSIGNED_SHORT = 0x1403;
pub const GL_UNSIGNED_INT = 0x1405;
pub const GL_FLOAT = 0x1406;
pub const GL_HALF_FLOAT = 0x140B;

// Primitives
pub const GL_POINTS = 0x0000;
pub const GL_LINES = 0x0001;
pub const GL_TRIANGLES = 0x0004;
pub const GL_TRIANGLE_STRIP = 0x0005;
pub const GL_TRIANGLE_FAN = 0x0006;

// Polygons
pub const GL_CW = 0x0900;
pub const GL_CCW = 0x0901;
pub const GL_FRONT = 0x0404;
pub const GL_BACK = 0x0405;
pub const GL_FRONT_AND_BACK = 0x0408;
pub const GL_CULL_FACE = 0x0B44;

// Depth buffer
pub const GL_LESS = 0x0201;
pub const GL_EQUAL = 0x0202;
pub const GL_LEQUAL = 0x0203;
pub const GL_GREATER = 0x0204;
pub const GL_NOTEQUAL = 0x0205;
pub const GL_GEQUAL = 0x0206;
pub const GL_ALWAYS = 0x0207;
pub const GL_DEPTH_TEST = 0x0B71;

pub const GL_VIEWPORT = 0x0BA2;

// Blending
pub const GL_BLEND = 0x0BE2;
pub const GL_BLEND_SRC = 0x0BE1;
pub const GL_BLEND_DST = 0x0BE0;
pub const GL_ZERO = 0;
pub const GL_ONE = 1;
pub const GL_SRC_COLOR = 0x0300;
pub const GL_ONE_MINUS_SRC_COLOR = 0x0301;
pub const GL_SRC_ALPHA = 0x0302;
pub const GL_ONE_MINUS_SRC_ALPHA = 0x0303;
pub const GL_DST_ALPHA = 0x0304;
pub const GL_ONE_MINUS_DST_ALPHA = 0x0305;
pub const GL_DST_COLOR = 0x0306;
pub const GL_ONE_MINUS_DST_COLOR = 0x0307;
pub const GL_SRC_ALPHA_SATURATE = 0x0308;

// Texture mapping
pub const GL_TEXTURE_2D = 0x0DE1;
pub const GL_TEXTURE_WRAP_S = 0x2802;
pub const GL_TEXTURE_WRAP_T = 0x2803;
pub const GL_TEXTURE_MAG_FILTER = 0x2800;
pub const GL_TEXTURE_MIN_FILTER = 0x2801;

// Errors
pub const GL_NO_ERROR = 0;
pub const GL_INVALID_ENUM = 0x0500;
pub const GL_INVALID_VALUE = 0x0501;
pub const GL_INVALID_OPERATION = 0x0502;
pub const GL_STACK_OVERFLOW = 0x0503;
pub const GL_STACK_UNDERFLOW = 0x0504;
pub const GL_OUT_OF_MEMORY = 0x0505;

// glPush/PopAttrib bits
pub const GL_DEPTH_BUFFER_BIT = 0x00000100;
pub const GL_STENCIL_BUFFER_BIT = 0x00000400;
pub const GL_COLOR_BUFFER_BIT = 0x00004000;

// Stencil
pub const GL_STENCIL_TEST = 0x0B90;
pub const GL_KEEP = 0x1E00;
pub const GL_REPLACE = 0x1E01;
pub const GL_INCR = 0x1E02;
pub const GL_DECR = 0x1E03;

// Buffers, Pixel Drawing/Reading
pub const GL_RED = 0x1903;
pub const GL_ALPHA = 0x1906;
pub const GL_RGB = 0x1907;
pub const GL_RGBA = 0x1908;
pub const GL_LUMINANCE = 0x1909;
pub const GL_R16F = 0x822D;
pub const GL_R32F = 0x822E;

// Scissor box
pub const GL_SCISSOR_TEST = 0x0C11;

// Texture mapping
pub const GL_NEAREST_MIPMAP_NEAREST = 0x2700;
pub const GL_NEAREST_MIPMAP_LINEAR = 0x2702;
pub const GL_LINEAR_MIPMAP_NEAREST = 0x2701;
pub const GL_LINEAR_MIPMAP_LINEAR = 0x2703;
pub const GL_NEAREST = 0x2600;
pub const GL_LINEAR = 0x2601;
pub const GL_REPEAT = 0x2901;

// OpenGL 1.2
pub const GL_CLAMP_TO_EDGE = 0x812F;

// OpenGL 1.3
pub const GL_TEXTURE0 = 0x84C0;

// OpenGL 1.4
pub const GL_ARRAY_BUFFER = 0x8892;
pub const GL_ELEMENT_ARRAY_BUFFER = 0x8893;
pub const GL_STREAM_DRAW = 0x88E0;
pub const GL_STATIC_DRAW = 0x88E4;
pub const GL_INCR_WRAP = 0x8507;
pub const GL_DECR_WRAP = 0x8508;

// OpenGL 2.0
pub const GL_FRAGMENT_SHADER = 0x8B30;
pub const GL_VERTEX_SHADER = 0x8B31;
pub const GL_COMPILE_STATUS = 0x8B81;
pub const GL_LINK_STATUS = 0x8B82;
pub const GL_UNPACK_ALIGNMENT = 0x0CF5;

pub const GL_FRAMEBUFFER_COMPLETE = 0x8CD5;
pub const GL_COLOR_ATTACHMENT0 = 0x8CE0;
pub const GL_STENCIL_ATTACHMENT = 0x8D20;
pub const GL_FRAMEBUFFER = 0x8D40;
pub const GL_RENDERBUFFER = 0x8D41;
pub const GL_FRAMEBUFFER_BINDING = 0x8CA6;
pub const GL_RENDERBUFFER_BINDING = 0x8CA7;
pub const GL_STENCIL_INDEX8 = 0x8D48;

//
// Miscellaneous
//

pub extern fn glClearColor(red: GLclampf, green: GLclampf, blue: GLclampf, alpha: GLclampf) callconv(.c) void;
pub extern fn glClearDepthf(d: GLfloat) callconv(.c) void;
pub extern fn glClear(mask: GLbitfield) callconv(.c) void;
pub extern fn glColorMask(red: GLboolean, green: GLboolean, blue: GLboolean, alpha: GLboolean) callconv(.c) void;
pub extern fn glDepthFunc(fung: GLenum) callconv(.c) void;
pub extern fn glDepthMask(flag: GLboolean) callconv(.c) void;
pub extern fn glCullFace(mode: GLenum) callconv(.c) void;
pub extern fn glFrontFace(mode: GLenum) callconv(.c) void;
pub extern fn glEnable(cap: GLenum) callconv(.c) void;
pub extern fn glDisable(cap: GLenum) callconv(.c) void;
pub extern fn glGetError() callconv(.c) GLenum;
pub extern fn glPixelStorei(pname: GLenum, param: GLint) callconv(.c) void;
pub extern fn glReadPixels(x: GLint, y: GLint, width: GLsizei, height: GLsizei, format: GLenum, type: GLenum, data: ?*anyopaque) callconv(.c) void;

//
// Transformation
//

pub extern fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) callconv(.c) void;

//
// Stenciling
//

pub extern fn glStencilFunc(func: GLenum, ref: GLint, mask: GLuint) callconv(.c) void;
pub extern fn glStencilMask(mask: GLuint) callconv(.c) void;
pub extern fn glStencilOp(fail: GLenum, zfail: GLenum, zpass: GLenum) callconv(.c) void;

//
// Extensions
//

pub extern fn glDrawArrays(mode: GLenum, first: GLint, count: GLsizei) callconv(.c) void;
pub extern fn glDrawElements(mode: GLenum, count: GLsizei, typ: GLenum, indices: [*c]const c_uint) callconv(.c) void;
pub extern fn glDrawElementsInstanced(mode: GLenum, count: GLsizei, typ: GLenum, indices: [*c]const c_uint, instancecount: GLsizei) callconv(.c) void;

pub extern fn glTexImage2D(target: GLenum, level: GLint, internalFormat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, @"type": GLenum, pixels: ?*const GLvoid) callconv(.c) void;
pub extern fn glTexSubImage2D(target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, @"type": GLenum, pixels: ?*const GLvoid) callconv(.c) void;
pub extern fn glGenTextures(n: GLsizei, textures: [*c]GLuint) callconv(.c) void;
pub extern fn glDeleteTextures(n: GLsizei, textures: [*c]const GLuint) callconv(.c) void;
pub extern fn glBindTexture(target: GLenum, texture: GLuint) callconv(.c) void;
pub extern fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) callconv(.c) void;
pub extern fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) callconv(.c) void;
pub extern fn jsLoadTextureIMG(data_ptr: [*]const u8, data_len: usize, mime_ptr: [*]const u8, mime_len: usize, ?*u16, ?*u16, GLint, GLint, GLint, GLint) callconv(.c) GLuint;
pub extern fn glGenerateMipmap(target: GLenum) callconv(.c) void;

pub extern fn glActiveTexture(texture: GLenum) callconv(.c) void;

pub extern fn glStencilOpSeparate(face: GLenum, sfail: GLenum, dpfail: GLenum, dppass: GLenum) callconv(.c) void;
pub extern fn glBlendFuncSeparate(sfactorRGB: GLenum, dfactorRGB: GLenum, sfactorAlpha: GLenum, dfactorAlpha: GLenum) callconv(.c) void;

pub extern fn glBindBuffer(target: GLenum, buffer: GLuint) callconv(.c) void;
pub extern fn glDeleteBuffers(n: GLsizei, buffers: [*c]const GLuint) callconv(.c) void;
pub extern fn glGenBuffers(n: GLsizei, buffers: [*c]GLuint) callconv(.c) void;
pub extern fn glBufferData(target: GLenum, size: GLsizeiptr, data: ?*const anyopaque, usage: GLenum) callconv(.c) void;
pub extern fn glBufferSubData(target: GLenum, offset: GLintptr, size: GLsizeiptr, data: ?*const anyopaque) callconv(.c) void;

pub extern fn glAttachShader(program: GLuint, shader: GLuint) callconv(.c) void;
pub extern fn glBindAttribLocation(program: GLuint, index: GLuint, name: [*c]const GLchar) callconv(.c) void;
pub extern fn glCompileShader(shader: GLuint) callconv(.c) void;
pub extern fn glCreateProgram() callconv(.c) GLuint;
pub extern fn glCreateShader(@"type": GLenum) callconv(.c) GLuint;
pub extern fn glDeleteProgram(program: GLuint) callconv(.c) void;
pub extern fn glDeleteShader(shader: GLuint) callconv(.c) void;
pub extern fn glDisableVertexAttribArray(index: GLuint) callconv(.c) void;
pub extern fn glEnableVertexAttribArray(index: GLuint) callconv(.c) void;
pub extern fn glGetProgramiv(program: GLuint, pname: GLenum, params: [*c]GLint) callconv(.c) void;
pub extern fn glGetProgramInfoLog(program: GLuint, bufSize: GLsizei, length: [*c]GLsizei, infoLog: [*c]GLchar) callconv(.c) void;
pub extern fn glGetShaderiv(shader: GLuint, pname: GLenum, params: [*c]GLint) callconv(.c) void;
pub extern fn glGetShaderInfoLog(shader: GLuint, bufSize: GLsizei, length: [*c]GLsizei, infoLog: [*c]GLchar) callconv(.c) void;
pub extern fn glLinkProgram(program: GLuint) callconv(.c) void;
pub extern fn glShaderSource(shader: GLuint, count: GLsizei, [*c]const [*c]const GLchar, length: [*c]const GLint) callconv(.c) void;
pub extern fn glGetUniformLocation(program: GLuint, name: [*c]const GLchar) callconv(.c) GLint;
pub extern fn glUseProgram(program: GLuint) callconv(.c) void;
pub extern fn glUniform1i(location: GLint, v0: GLint) callconv(.c) void;
pub extern fn glUniform1f(location: GLint, v0: GLfloat) callconv(.c) void;
pub extern fn glUniform2f(location: GLint, v0: GLfloat, v1: GLfloat) callconv(.c) void;
pub extern fn glUniform3f(location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat) callconv(.c) void;
pub extern fn glUniform4f(location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat, v3: GLfloat) callconv(.c) void;
pub extern fn glUniform1fv(location: GLint, count: GLsizei, value: [*c]const GLfloat) callconv(.c) void;
pub extern fn glUniform2fv(location: GLint, count: GLsizei, value: [*c]const GLfloat) callconv(.c) void;
pub extern fn glUniform3fv(location: GLint, count: GLsizei, value: [*c]const GLfloat) callconv(.c) void;
pub extern fn glUniform4fv(location: GLint, count: GLsizei, value: [*c]const GLfloat) callconv(.c) void;
pub extern fn glUniformMatrix3fv(location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(.c) void;
pub extern fn glUniformMatrix4fv(location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(.c) void;
pub extern fn glVertexAttribPointer(index: GLuint, size: GLint, @"type": GLenum, normalized: GLboolean, stride: GLsizei, pointer: ?*const anyopaque) callconv(.c) void;
pub extern fn glVertexAttribDivisor(index: GLuint, divisor: GLuint) callconv(.c) void;

pub extern fn glGetIntegerv(pname: GLenum, params: [*c]GLint) callconv(.c) void;

pub extern fn glGenFramebuffers(n: GLsizei, framebuffers: [*c]GLuint) callconv(.c) void;
pub extern fn glBindFramebuffer(target: GLenum, id: GLuint) callconv(.c) void;
pub extern fn glDeleteFramebuffers(n: GLsizei, framebuffers: [*c]const GLuint) callconv(.c) void;
pub extern fn glCheckFramebufferStatus(target: GLenum) callconv(.c) GLenum;
pub extern fn glGenRenderbuffers(n: GLsizei, renderbuffers: [*c]GLuint) callconv(.c) void;
pub extern fn glBindRenderbuffer(target: GLenum, renderbuffer: GLuint) callconv(.c) void;
pub extern fn glDeleteRenderbuffers(n: GLsizei, renderbuffers: [*c]const GLuint) callconv(.c) void;
pub extern fn glRenderbufferStorage(target: GLenum, internalformat: GLenum, width: GLsizei, height: GLsizei) callconv(.c) void;
pub extern fn glRenderbufferStorageMultisample(target: GLenum, samples: GLsizei, internalformat: GLenum, width: GLsizei, height: GLsizei) callconv(.c) void;
pub extern fn glFramebufferTexture2D(target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint) callconv(.c) void;
pub extern fn glFramebufferRenderbuffer(target: GLenum, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint) callconv(.c) void;
pub extern fn glBlitFramebuffer(srcX0: GLint, srcY0: GLint, srcX1: GLint, srcY1: GLint, dstX0: GLint, dstY0: GLint, dstX1: GLint, dstY1: GLint, mask: GLbitfield, filter: GLenum) callconv(.c) void;
pub extern fn glDrawBuffers(n: GLsizei, bufs: [*]const GLenum) callconv(.c) void;

// Convenience

pub fn loadTextureIMG(
    data: []const u8,
    mime: []const u8,
    width: ?*u16,
    height: ?*u16,
    min_filter: GLint,
    mag_filter: GLint,
    wrap_s: GLint,
    wrap_t: GLint,
) GLuint {
    return jsLoadTextureIMG(data.ptr, data.len, mime.ptr, mime.len, width, height, min_filter, mag_filter, wrap_s, wrap_t);
}
