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
pub const car_node_names = [_][]const u8{
    "car_hatchback",
    "car_police",
    "car_sedan",
    "car_stationwagon",
    "car_taxi",
};

pub const CarRig = struct {
    root_node_index: usize,
    wheel_front_left_node_index: usize,
    wheel_front_right_node_index: usize,
    wheel_rear_left_node_index: usize,
    wheel_rear_right_node_index: usize,
    front_axle_y_model: f32,
    rear_axle_y_model: f32,
    bbox_min_x_model: f32,
    bbox_max_x_model: f32,
    bbox_min_y_model: f32,
    bbox_max_y_model: f32,
};

pub var car_node_indices: [car_node_names.len]usize = undefined;
pub var car_rigs: [car_node_names.len]CarRig = undefined;
pub var car_small_node_index: usize = undefined;
pub var trafficlight_c_node_index: usize = undefined;

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

    for (car_node_names, 0..) |expected_name, i| {
        const root_node_index = citykit_model.findNodeByName(expected_name) orelse
            std.debug.panic("Missing node: {s}", .{expected_name});
        car_node_indices[i] = root_node_index;
        car_rigs[i] = load_car_rig(root_node_index);
    }
    car_small_node_index = car_node_indices[0];
    trafficlight_c_node_index = citykit_model.findNodeByName("trafficlight_C") orelse
        std.debug.panic("Missing node: trafficlight_C", .{});

    if (builtin.cpu.arch.isWasm()) {
        const web_gl = @import("engine/web/gl.zig");
        tex_bulldozer = web_gl.loadTextureIMG(&icon_bulldozer_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_buildings = web_gl.loadTextureIMG(&icon_buildings_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_streets = web_gl.loadTextureIMG(&icon_streets_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_park = web_gl.loadTextureIMG(&icon_park_png, "image/png", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        tex_grass = web_gl.loadTextureIMG(&grass_webp, "image/webp", null, null, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR, gl.REPEAT, gl.REPEAT);
    }
}

fn load_car_rig(root_node_index: usize) CarRig {
    const missing_index = std.math.maxInt(usize);
    var wheel_front_left_node_index: usize = missing_index;
    var wheel_front_right_node_index: usize = missing_index;
    var wheel_rear_left_node_index: usize = missing_index;
    var wheel_rear_right_node_index: usize = missing_index;
    var front_axle_y_sum: f32 = 0;
    var rear_axle_y_sum: f32 = 0;
    var front_wheel_count: u32 = 0;
    var rear_wheel_count: u32 = 0;

    const nodes = citykit_model.gltf.data.nodes;
    const root = nodes[root_node_index];

    for (root.children) |child_node_index| {
        const child = nodes[child_node_index];
        const child_name = child.name orelse continue;

        if (std.mem.indexOf(u8, child_name, "wheel_front_left") != null) {
            wheel_front_left_node_index = child_node_index;
            front_axle_y_sum += child.translation[1];
            front_wheel_count += 1;
        } else if (std.mem.indexOf(u8, child_name, "wheel_front_right") != null) {
            wheel_front_right_node_index = child_node_index;
            front_axle_y_sum += child.translation[1];
            front_wheel_count += 1;
        } else if (std.mem.indexOf(u8, child_name, "wheel_rear_left") != null) {
            wheel_rear_left_node_index = child_node_index;
            rear_axle_y_sum += child.translation[1];
            rear_wheel_count += 1;
        } else if (std.mem.indexOf(u8, child_name, "wheel_rear_right") != null) {
            wheel_rear_right_node_index = child_node_index;
            rear_axle_y_sum += child.translation[1];
            rear_wheel_count += 1;
        }
    }

    std.debug.assert(wheel_front_left_node_index != missing_index);
    std.debug.assert(wheel_front_right_node_index != missing_index);
    std.debug.assert(wheel_rear_left_node_index != missing_index);
    std.debug.assert(wheel_rear_right_node_index != missing_index);
    std.debug.assert(front_wheel_count == 2);
    std.debug.assert(rear_wheel_count == 2);
    const mesh_bounds = mesh_bounds_xy_model(root.mesh orelse std.debug.panic("Missing car mesh.", .{}));

    return .{
        .root_node_index = root_node_index,
        .wheel_front_left_node_index = wheel_front_left_node_index,
        .wheel_front_right_node_index = wheel_front_right_node_index,
        .wheel_rear_left_node_index = wheel_rear_left_node_index,
        .wheel_rear_right_node_index = wheel_rear_right_node_index,
        .front_axle_y_model = front_axle_y_sum / 2.0,
        .rear_axle_y_model = rear_axle_y_sum / 2.0,
        .bbox_min_x_model = mesh_bounds.min_x,
        .bbox_max_x_model = mesh_bounds.max_x,
        .bbox_min_y_model = mesh_bounds.min_y,
        .bbox_max_y_model = mesh_bounds.max_y,
    };
}

const MeshBoundsXY = struct {
    min_x: f32,
    max_x: f32,
    min_y: f32,
    max_y: f32,
};

fn mesh_bounds_xy_model(mesh_index: usize) MeshBoundsXY {
    const mesh = citykit_model.gltf.data.meshes[mesh_index];
    var min_x = std.math.inf(f32);
    var max_x = -std.math.inf(f32);
    var min_y = std.math.inf(f32);
    var max_y = -std.math.inf(f32);
    var has_positions = false;

    for (mesh.primitives) |*primitive| {
        for (primitive.attributes) |attribute| {
            switch (attribute) {
                .position => |accessor_index| {
                    const accessor = citykit_model.gltf.data.accessors[accessor_index];
                    const positions = citykit_model.getFloatBuffer(accessor);
                    std.debug.assert(positions.len % 3 == 0);
                    var vertex_index: usize = 0;
                    while (vertex_index < positions.len / 3) : (vertex_index += 1) {
                        const base = vertex_index * 3;
                        min_x = @min(min_x, positions[base + 0]);
                        max_x = @max(max_x, positions[base + 0]);
                        min_y = @min(min_y, positions[base + 1]);
                        max_y = @max(max_y, positions[base + 1]);
                    }
                    has_positions = true;
                },
                else => {},
            }
        }
    }

    std.debug.assert(has_positions);
    return .{
        .min_x = min_x,
        .max_x = max_x,
        .min_y = min_y,
        .max_y = max_y,
    };
}
