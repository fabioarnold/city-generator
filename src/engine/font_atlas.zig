const std = @import("std");
const gl = @import("gl");
const gfx = @import("gfx.zig");
const Rect = gfx.Rect;
const TrueType = @import("truetype.zig");

pub const FontAtlas = @This();

pub const width = 1024;
pub const height = 1024;
allocator: std.mem.Allocator,
pixels: []u8,
x: u32 = 0,
y: u32 = 0,
row_h: u32 = 0,

ttf: TrueType = undefined,

texture: gl.uint = 0,
texture_needs_update: bool = false,

character_map: std.AutoArrayHashMapUnmanaged(LookupKey, Character) = .empty,

pub const LookupKey = packed struct(u32) {
    font_size: u11,
    codepoint: u21,
};
pub const Character = struct {
    box: Rect = .zero,
    left_side_bearing: f32 = 0,
    offset_y: f32 = 0,
    advance_width: f32 = 0,
};

pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !FontAtlas {
    var atlas: FontAtlas = .{
        .allocator = allocator,
        .pixels = undefined,
        .ttf = try TrueType.load(font_data),
    };
    atlas.pixels = try allocator.alloc(u8, width * height);
    @memset(atlas.pixels, 0);

    gl.GenTextures(1, @ptrCast(&atlas.texture));
    gl.BindTexture(gl.TEXTURE_2D, atlas.texture);
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.R8,
        width,
        height,
        0,
        gl.RED,
        gl.UNSIGNED_BYTE,
        @ptrCast(atlas.pixels.ptr),
    );
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    return atlas;
}

pub fn render_glyph_bitmap(
    atlas: *FontAtlas,
    glyph_pixels: *std.ArrayList(u8),
    glyph_index: TrueType.GlyphIndex,
    font_scale: f32,
) !?TrueType.GlyphBitmap {
    return atlas.ttf.glyphBitmap(
        atlas.allocator,
        glyph_pixels,
        glyph_index,
        font_scale,
        font_scale,
    ) catch |err| {
        switch (err) {
            error.GlyphNotFound => return null, // TODO: use fallback character
            else => return err,
        }
    };
}

pub fn get_character(atlas: *FontAtlas, font_size: u11, codepoint: u21) !Character {
    const key: LookupKey = .{ .font_size = font_size, .codepoint = codepoint };
    const result = try atlas.character_map.getOrPut(atlas.allocator, key);
    if (!result.found_existing) {
        const character = result.value_ptr;
        character.* = .{};

        const glyph_index = atlas.ttf.codepointGlyphIndex(@intCast(codepoint)) orelse .notdef;
        const ttf_scale = atlas.ttf.scaleForPixelHeight(@floatFromInt(font_size));
        const metrics = atlas.ttf.glyphHMetrics(glyph_index);
        character.left_side_bearing = ttf_scale * @as(f32, @floatFromInt(metrics.left_side_bearing));
        character.advance_width = ttf_scale * @as(f32, @floatFromInt(metrics.advance_width));
        var glyph_pixels = std.ArrayList(u8).empty;
        // TODO: use scratch allocator ? from stack?
        if (try atlas.render_glyph_bitmap(&glyph_pixels, glyph_index, ttf_scale)) |glyph_bitmap| {
            character.box = try atlas.pack_glyph(&glyph_pixels, glyph_bitmap.width, glyph_bitmap.height);
            character.offset_y = @floatFromInt(glyph_bitmap.off_y);
        }
    }

    return result.value_ptr.*;
}

fn pack_glyph(atlas: *FontAtlas, glyph_pixels: *const std.ArrayList(u8), w: u16, h: u16) !Rect {
    const pad = 1;

    if (atlas.x + w + 2 * pad > FontAtlas.width) {
        atlas.x = 0;
        atlas.y += atlas.row_h + 2 * pad;
    }
    if (atlas.y + h + 2 * pad > FontAtlas.height) return error.OutOfSpace;

    // blit
    var dst: usize = (atlas.y + pad) * FontAtlas.width + atlas.x + pad;
    var src: usize = 0;
    for (0..h) |_| {
        @memcpy(atlas.pixels[dst..][0..w], glyph_pixels.items[src..][0..w]);
        dst += FontAtlas.width;
        src += w;
    }
    atlas.texture_needs_update = true;
    const box: Rect = .{
        .x = @floatFromInt(atlas.x + pad),
        .y = @floatFromInt(atlas.y + pad),
        .w = @floatFromInt(w),
        .h = @floatFromInt(h),
    };

    atlas.x += w + 2 * pad;
    atlas.row_h = @max(atlas.row_h, h);

    return box;
}

pub fn bind_texture(atlas: *FontAtlas) void {
    gl.BindTexture(gl.TEXTURE_2D, atlas.texture);
    if (atlas.texture_needs_update) {
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.R8,
            FontAtlas.width,
            FontAtlas.height,
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            @ptrCast(atlas.pixels.ptr),
        );
        atlas.texture_needs_update = false;
    }
}
