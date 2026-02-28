const std = @import("std");
const gl = @import("gl");
const builtin = @import("builtin");
const Model = @import("engine/model.zig");

const model_citykit_glb align(4) = @embedFile("models/citykit.glb").*;
const icon_bulldozer_png = @embedFile("img/icons/bulldozer.png").*;
const icon_buildings_png = @embedFile("img/icons/building.png").*;
const icon_streets_png = @embedFile("img/icons/road.png").*;
const icon_park_png = @embedFile("img/icons/park.png").*;
const grass_webp = @embedFile("img/grass.webp").*;

pub const tile_building_a: u6 = 1;
pub const tile_building_b: u6 = 2;
pub const tile_building_c: u6 = 3;
pub const tile_building_d: u6 = 4;
pub const tile_building_e: u6 = 5;
pub const tile_building_f: u6 = 6;
pub const tile_building_g: u6 = 7;
pub const tile_building_h: u6 = 8;
pub const tile_road_straight: u6 = 9;
pub const tile_road_corner: u6 = 10;
pub const tile_road_crossing: u6 = 11;
pub const tile_road_tsplit: u6 = 12;
pub const tile_road_junction: u6 = 13;
pub const tile_park: u6 = 14;

pub var citykit_model: Model = undefined;
pub var tile_node_indices: [14]usize = undefined;
pub var car_small_node_index: usize = undefined;

pub var tex_bulldozer: gl.uint = undefined;
pub var tex_buildings: gl.uint = undefined;
pub var tex_streets: gl.uint = undefined;
pub var tex_park: gl.uint = undefined;
pub var tex_grass: gl.uint = undefined;

pub fn load(allocator: std.mem.Allocator) !void {
    try citykit_model.load(allocator, &model_citykit_glb);

    const names = [_][]const u8{
        "building_A",
        "building_B",
        "building_C",
        "building_D",
        "building_E",
        "building_F",
        "building_G",
        "building_H",
        "road_straight",
        "road_corner",
        "road_straight_crossing",
        "road_tsplit",
        "road_junction",
        "park_base",
    };

    for (names, 0..) |expected_name, i| {
        tile_node_indices[i] = citykit_model.findNodeByName(expected_name) orelse std.debug.panic("Missing node: {s}", .{expected_name});
    }

    car_small_node_index = citykit_model.findNodeByName("car_hatchback") orelse std.debug.panic("Missing node: car_hatchback", .{});

    if (builtin.cpu.arch.isWasm()) {
        const web_gl = @import("engine/web/gl.zig");
        tex_bulldozer = web_gl.loadTextureIMG(&icon_bulldozer_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_buildings = web_gl.loadTextureIMG(&icon_buildings_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_streets = web_gl.loadTextureIMG(&icon_streets_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_park = web_gl.loadTextureIMG(&icon_park_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_grass = web_gl.loadTextureIMG(&grass_webp, "image/webp", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.REPEAT, gl.REPEAT);
    }
}
