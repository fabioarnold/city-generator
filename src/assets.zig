const std = @import("std");
const Model = @import("model.zig");

const model_building_a_glb align(4) = @embedFile("models/building_a.glb").*;
const model_building_b_glb align(4) = @embedFile("models/building_b.glb").*;
const model_building_c_glb align(4) = @embedFile("models/building_c.glb").*;
const model_building_d_glb align(4) = @embedFile("models/building_d.glb").*;
const model_building_e_glb align(4) = @embedFile("models/building_e.glb").*;
const model_building_f_glb align(4) = @embedFile("models/building_f.glb").*;
const model_building_g_glb align(4) = @embedFile("models/building_g.glb").*;
const model_building_h_glb align(4) = @embedFile("models/building_h.glb").*;
const model_road_straight_glb align(4) = @embedFile("models/road_straight.glb").*;
const model_road_corner_glb align(4) = @embedFile("models/road_corner.glb").*;
const model_road_crossing_glb align(4) = @embedFile("models/road_crossing.glb").*;
const model_road_tsplit_glb align(4) = @embedFile("models/road_tsplit.glb").*;
const model_road_junction_glb align(4) = @embedFile("models/road_junction.glb").*;
const model_car_small_glb align(4) = @embedFile("models/car_small.glb").*;

pub var model_tiles: [13]Model = undefined;
pub var model_car_small:Model = undefined;

pub fn load(allocator: std.mem.Allocator) !void {
    try model_tiles[0].load(allocator, &model_building_a_glb);
    try model_tiles[1].load(allocator, &model_building_b_glb);
    try model_tiles[2].load(allocator, &model_building_c_glb);
    try model_tiles[3].load(allocator, &model_building_d_glb);
    try model_tiles[4].load(allocator, &model_building_e_glb);
    try model_tiles[5].load(allocator, &model_building_f_glb);
    try model_tiles[6].load(allocator, &model_building_g_glb);
    try model_tiles[7].load(allocator, &model_building_h_glb);
    try model_tiles[8].load(allocator, &model_road_straight_glb);
    try model_tiles[9].load(allocator, &model_road_corner_glb);
    try model_tiles[10].load(allocator, &model_road_crossing_glb);
    try model_tiles[11].load(allocator, &model_road_tsplit_glb);
    try model_tiles[12].load(allocator, &model_road_junction_glb);
    try model_car_small.load(allocator, &model_car_small_glb);
}
