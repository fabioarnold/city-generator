const std = @import("std");
const gl = @import("gl");
const assets = @import("assets.zig");
const tilemap_pkg = @import("tilemap.zig");
const shaders = @import("shaders.zig");
const la = @import("engine/linear_algebra.zig");
const debug_draw = @import("engine/debug_draw.zig");
const Model = @import("engine/model.zig");
const vec2 = la.vec2;
const mat4 = la.mat4;

const lane_center_offset: f32 = 0.15;
const connector_inset: f32 = 0.48;
const car_model_scale: f32 = 0.35;
const traffic_light_green_duration_s: f32 = 5.5;
const traffic_light_stop_margin: f32 = 0.06;
const intersection_clearance_margin: f32 = 0.2;
const follow_headway_s: f32 = 1.1;
const follow_base_gap_factor: f32 = 1.1;
const follow_prediction_horizon_s: f32 = 2.0;
const follow_prediction_margin: f32 = 0.05;
const future_collision_horizon_s: f32 = 2.0;
const future_collision_sample_count: u32 = 4;
const future_collision_margin: f32 = 0.015;
const future_collision_binary_search_steps: u32 = 9;
const follow_scan_distance_max: f32 = 4.0;
const follow_scan_edge_count_max: u32 = 10;
const max_spawn_attempts: u32 = 48;
const max_path_attempts: u32 = 64;
const max_car_count: u32 = 18;
const turn_radius_target: f32 = 0.2;
const debug_path_z: f32 = 0.12;
const debug_path_width: f32 = 0.035;
const debug_box_width: f32 = 0.02;
const car_acceleration_default: f32 = 0.9;
const car_deceleration_default: f32 = 2.2;
const debug_axle_point_z: f32 = 0.16;
const debug_front_axle_point_size: f32 = 0.05;
const debug_rear_axle_point_size: f32 = 0.04;
const collision_substep_distance: f32 = 0.025;
const small_distance_epsilon: f32 = 0.001;
const small_length_epsilon: f32 = 0.0001;
const small_angle_epsilon: f32 = 0.001;
const debug_arc_segment_angle_step_rad: f32 = std.math.pi / 16.0;

const Direction = enum(u2) {
    north = 0,
    east = 1,
    south = 2,
    west = 3,
};

const NodeKey = struct {
    tile_x: i32,
    tile_y: i32,
    side: u2,
    outbound: bool,
};

const Node = struct {
    position: vec2,
    tile_x: i32,
    tile_y: i32,
    side: Direction,
    outbound: bool,
};

const EdgeType = enum {
    in_tile,
    transition,
};

const LineGeometry = struct {
    start: vec2,
    end: vec2,
};

const ArcGeometry = struct {
    center: vec2,
    radius: f32,
    start_angle: f32,
    angle_delta: f32,
};

const TurnGeometry = struct {
    start: vec2,
    entry: vec2,
    exit: vec2,
    end: vec2,
    arc_center: vec2,
    arc_radius: f32,
    arc_start_angle: f32,
    arc_angle_delta: f32,
    len_entry: f32,
    len_arc: f32,
    len_exit: f32,
};

const EdgeGeometry = union(enum) {
    line: LineGeometry,
    arc: ArcGeometry,
    turn: TurnGeometry,
};

const Edge = struct {
    from: u32,
    to: u32,
    length: f32,
    edge_type: EdgeType,
    geometry: EdgeGeometry,

    tile_x: i32 = 0,
    tile_y: i32 = 0,
    in_side: u2 = 0,
    out_side: u2 = 0,

    from_tile_x: i32 = 0,
    from_tile_y: i32 = 0,
    to_tile_x: i32 = 0,
    to_tile_y: i32 = 0,
    to_side: u2 = 0,
};

const TrafficLight = struct {
    tile_x: i32,
    tile_y: i32,
    timer_s: f32,
    ns_green: bool,
};

const Car = struct {
    route_edges: std.ArrayListUnmanaged(u32) = .empty,
    route_edge_index: u32 = 0,
    edge_t: f32 = 0,

    rear_axle: vec2 = @splat(0),
    front_axle: vec2 = @splat(0),
    heading_rad: f32 = 0,
    steering_angle_rad: f32 = 0,

    velocity_units_s: f32 = 0,
    speed_units_s: f32 = 0.55,
    acceleration_units_s2: f32 = car_acceleration_default,
    deceleration_units_s2: f32 = car_deceleration_default,
    model_kind: usize = 0,
    wait_timer_s: f32 = 0,
    destination_node: u32 = 0,
    at_node: ?u32 = null,
    initialized: bool = false,
};

const Sample = struct {
    position: vec2,
    tangent: vec2,
    curvature: f32,
};

const OBB = struct {
    center: vec2,
    axis_forward: vec2,
    axis_right: vec2,
    half_length: f32,
    half_width: f32,
};

const AheadInfo = struct {
    distance: f32,
    other_index: usize,
};

const EdgeRef = struct {
    edge: *const Edge,
};

const CarAdvanceState = struct {
    route_edge_index: u32,
    edge_t: f32,
    rear_axle: vec2,
    front_axle: vec2,
    heading_rad: f32,
    steering_angle_rad: f32,
    initialized: bool,
};

pub const Simulation = struct {
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    nodes: std.ArrayList(Node),
    edges: std.ArrayList(Edge),
    lights: std.ArrayList(TrafficLight),
    cars: std.ArrayList(Car),
    node_lookup: std.AutoHashMap(NodeKey, u32),

    pub fn init(allocator: std.mem.Allocator) Simulation {
        return .{
            .allocator = allocator,
            .prng = std.Random.DefaultPrng.init(0x5452414646494355),
            .nodes = std.ArrayList(Node).empty,
            .edges = std.ArrayList(Edge).empty,
            .lights = std.ArrayList(TrafficLight).empty,
            .cars = std.ArrayList(Car).empty,
            .node_lookup = std.AutoHashMap(NodeKey, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Simulation) void {
        self.clear_cars();
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.lights.deinit(self.allocator);
        self.cars.deinit(self.allocator);
        self.node_lookup.deinit();
    }

    pub fn rebuild_from_tilemap(self: *Simulation, tilemap: *const tilemap_pkg.TileMap) !void {
        self.clear_cars();
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
        self.lights.clearRetainingCapacity();
        self.node_lookup.clearRetainingCapacity();

        var chunk_iter = tilemap.chunks.iterator();
        while (chunk_iter.next()) |chunk_entry| {
            const key = chunk_entry.key_ptr.*;
            const chunk = chunk_entry.value_ptr.*;

            for (chunk.tiles, 0..) |row, ly| {
                for (row, 0..) |tile, lx| {
                    if (!tilemap_pkg.is_street(tile.index)) continue;

                    const tile_x = @as(i32, key.x) * tilemap_pkg.chunk_size + @as(i32, @intCast(lx));
                    const tile_y = @as(i32, key.y) * tilemap_pkg.chunk_size + @as(i32, @intCast(ly));
                    try self.build_tile_edges(tilemap, tile_x, tile_y, tile);
                }
            }
        }

        try self.spawn_initial_cars();
    }

    pub fn update(self: *Simulation, dt_s: f32) void {
        if (dt_s <= 0) return;

        for (self.lights.items) |*light| {
            light.timer_s += dt_s;
            while (light.timer_s >= traffic_light_green_duration_s) {
                light.timer_s -= traffic_light_green_duration_s;
                light.ns_green = !light.ns_green;
            }
        }

        var car_index: usize = 0;
        while (car_index < self.cars.items.len) : (car_index += 1) {
            self.update_car(@intCast(car_index), dt_s);
        }
    }

    pub fn draw(self: *const Simulation, projection: mat4, view: mat4) void {
        gl.UseProgram(shaders.default.program);
        gl.UniformMatrix4fv(shaders.default.u_projection, 1, gl.FALSE, @ptrCast(&projection));
        gl.UniformMatrix4fv(shaders.default.u_view, 1, gl.FALSE, @ptrCast(&view));
        const shader_info: Model.ShaderInfo = .{ .model_loc = shaders.default.u_model };

        for (self.cars.items) |car| {
            const rig = assets.car_rigs[car.model_kind];
            const forward = vec2{ @cos(car.heading_rad), @sin(car.heading_rad) };
            const rear_axle_offset_world = rig.rear_axle_y_model * car_model_scale;
            const model_origin = car.rear_axle + forward * @as(vec2, @splat(rear_axle_offset_world));
            const yaw_deg = std.math.radiansToDegrees(car.heading_rad) + 90.0;
            const model = la.muln(&.{
                la.translation(model_origin[0], model_origin[1], 0.0723),
                la.rotation(yaw_deg, .{ 0, 0, 1 }),
                la.scale(car_model_scale, car_model_scale, car_model_scale),
            });

            const steer_deg = std.math.radiansToDegrees(car.steering_angle_rad);
            const front_delta = la.rotation(steer_deg, .{ 0, 0, 1 });
            const rear_delta = la.identity();

            const overrides = [_]Model.LocalMatrixOverride{
                .{ .node_index = rig.wheel_front_left_node_index, .delta = front_delta },
                .{ .node_index = rig.wheel_front_right_node_index, .delta = front_delta },
                .{ .node_index = rig.wheel_rear_left_node_index, .delta = rear_delta },
                .{ .node_index = rig.wheel_rear_right_node_index, .delta = rear_delta },
            };
            assets.citykit_model.drawNodeWithLocalOverrides(
                shader_info,
                model,
                rig.root_node_index,
                &overrides,
            );
        }
    }

    pub fn draw_debug_paths(self: *const Simulation, projection: mat4, view: mat4) void {
        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        debug_draw.begin(&projection, &view);
        for (self.edges.items) |edge| {
            switch (edge.geometry) {
                .line => |line| self.draw_debug_line(line.start, line.end),
                .arc => |arc| self.draw_debug_arc(arc.center, arc.radius, arc.start_angle, arc.angle_delta),
                .turn => |turn| {
                    self.draw_debug_line(turn.start, turn.entry);
                    self.draw_debug_arc(turn.arc_center, turn.arc_radius, turn.arc_start_angle, turn.arc_angle_delta);
                    self.draw_debug_line(turn.exit, turn.end);
                },
            }
        }

        for (self.cars.items) |car| {
            const obb = self.car_to_obb(&car);
            self.draw_debug_obb(obb);
            self.draw_debug_point(car.front_axle, debug_front_axle_point_size);
            self.draw_debug_point(car.rear_axle, debug_rear_axle_point_size);
        }
    }

    fn draw_debug_line(self: *const Simulation, start: vec2, end: vec2) void {
        self.draw_debug_line_width(start, end, debug_path_width);
    }

    fn draw_debug_arc(
        self: *const Simulation,
        center: vec2,
        radius: f32,
        start_angle: f32,
        angle_delta: f32,
    ) void {
        const step_count = arc_polyline_step_count(angle_delta);
        var step: u32 = 0;
        while (step < step_count) : (step += 1) {
            const t0 = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(step_count));
            const t1 = @as(f32, @floatFromInt(step + 1)) / @as(f32, @floatFromInt(step_count));
            const a0 = start_angle + angle_delta * t0;
            const a1 = start_angle + angle_delta * t1;
            const p0 = center + vec2{ @cos(a0), @sin(a0) } * @as(vec2, @splat(radius));
            const p1 = center + vec2{ @cos(a1), @sin(a1) } * @as(vec2, @splat(radius));
            self.draw_debug_line(p0, p1);
        }
    }

    fn draw_debug_line_width(self: *const Simulation, start: vec2, end: vec2, width: f32) void {
        _ = self;
        const delta = end - start;
        const length = vector_length(delta);
        if (length < small_distance_epsilon) return;

        const yaw_deg = std.math.radiansToDegrees(std.math.atan2(delta[1], delta[0]));
        const model = la.muln(&.{
            la.translation(start[0], start[1], debug_path_z),
            la.rotation(yaw_deg, .{ 0, 0, 1 }),
            la.translation(0, -0.5 * width, 0),
            la.scale(length, width, 1),
        });
        debug_draw.quad(&model);
    }

    fn draw_debug_obb(self: *const Simulation, obb: OBB) void {
        const p0 = obb.center + obb.axis_forward * @as(vec2, @splat(obb.half_length)) + obb.axis_right * @as(vec2, @splat(obb.half_width));
        const p1 = obb.center + obb.axis_forward * @as(vec2, @splat(obb.half_length)) - obb.axis_right * @as(vec2, @splat(obb.half_width));
        const p2 = obb.center - obb.axis_forward * @as(vec2, @splat(obb.half_length)) - obb.axis_right * @as(vec2, @splat(obb.half_width));
        const p3 = obb.center - obb.axis_forward * @as(vec2, @splat(obb.half_length)) + obb.axis_right * @as(vec2, @splat(obb.half_width));

        self.draw_debug_line_width(p0, p1, debug_box_width);
        self.draw_debug_line_width(p1, p2, debug_box_width);
        self.draw_debug_line_width(p2, p3, debug_box_width);
        self.draw_debug_line_width(p3, p0, debug_box_width);
    }

    fn draw_debug_point(self: *const Simulation, point: vec2, size: f32) void {
        _ = self;
        const model = la.muln(&.{
            la.translation(point[0] - 0.5 * size, point[1] - 0.5 * size, debug_axle_point_z),
            la.scale(size, size, 1),
        });
        debug_draw.quad(&model);
    }

    fn car_wheelbase_world(self: *const Simulation, model_kind: usize) f32 {
        _ = self;
        const rig = assets.car_rigs[model_kind];
        const wheelbase = (rig.rear_axle_y_model - rig.front_axle_y_model) * car_model_scale;
        std.debug.assert(wheelbase > 0);
        return wheelbase;
    }

    fn car_half_length_world(self: *const Simulation, model_kind: usize) f32 {
        _ = self;
        const rig = assets.car_rigs[model_kind];
        return 0.5 * (rig.bbox_max_y_model - rig.bbox_min_y_model) * car_model_scale;
    }

    fn car_length_world(self: *const Simulation, model_kind: usize) f32 {
        return 2.0 * self.car_half_length_world(model_kind);
    }

    fn route_edge_ref(self: *const Simulation, car: *const Car, relative_index: usize) ?EdgeRef {
        const base_index: usize = @intCast(car.route_edge_index);
        const route_index = base_index + relative_index;
        if (route_index >= car.route_edges.items.len) return null;

        const edge_id = car.route_edges.items[route_index];
        return .{ .edge = &self.edges.items[@intCast(edge_id)] };
    }

    fn clear_cars(self: *Simulation) void {
        for (self.cars.items) |*car| {
            car.route_edges.deinit(self.allocator);
        }
        self.cars.clearRetainingCapacity();
    }

    fn build_tile_edges(
        self: *Simulation,
        tilemap: *const tilemap_pkg.TileMap,
        tile_x: i32,
        tile_y: i32,
        tile: tilemap_pkg.Tile,
    ) !void {
        const openings = tilemap_pkg.street_openings(tile);
        if (openings == 0) return;

        for (0..4) |side_u| {
            const side_bit: u4 = @as(u4, 1) << @as(u2, @intCast(side_u));
            if ((openings & side_bit) == 0) continue;
            const side = direction_from_index(@intCast(side_u));
            _ = try self.ensure_node(tile_x, tile_y, side, false);
            _ = try self.ensure_node(tile_x, tile_y, side, true);
        }

        for (0..4) |incoming_u| {
            const incoming_bit: u4 = @as(u4, 1) << @as(u2, @intCast(incoming_u));
            if ((openings & incoming_bit) == 0) continue;

            for (0..4) |outgoing_u| {
                const outgoing_bit: u4 = @as(u4, 1) << @as(u2, @intCast(outgoing_u));
                if ((openings & outgoing_bit) == 0) continue;
                if (incoming_u == outgoing_u) continue;

                const incoming_side = direction_from_index(@intCast(incoming_u));
                const outgoing_side = direction_from_index(@intCast(outgoing_u));
                try self.add_in_tile_edge(tile_x, tile_y, incoming_side, outgoing_side);
            }
        }

        for (0..4) |outgoing_u| {
            const outgoing_bit: u4 = @as(u4, 1) << @as(u2, @intCast(outgoing_u));
            if ((openings & outgoing_bit) == 0) continue;

            const outgoing_side = direction_from_index(@intCast(outgoing_u));
            const outgoing_vec = direction_vector(outgoing_side);
            const nx = tile_x + @as(i32, @intFromFloat(outgoing_vec[0]));
            const ny = tile_y + @as(i32, @intFromFloat(outgoing_vec[1]));
            const neighbor = tilemap.get_tile(nx, ny);
            if (!tilemap_pkg.is_street(neighbor.index)) continue;

            const neighbor_openings = tilemap_pkg.street_openings(neighbor);
            const incoming_side = opposite_direction(outgoing_side);
            const incoming_bit: u4 = @as(u4, 1) << @intFromEnum(incoming_side);
            if ((neighbor_openings & incoming_bit) == 0) continue;

            try self.add_transition_edge(tile_x, tile_y, outgoing_side, nx, ny, incoming_side);
        }

        if (@popCount(openings) >= 3) {
            try self.lights.append(self.allocator, .{
                .tile_x = tile_x,
                .tile_y = tile_y,
                .timer_s = 0,
                .ns_green = true,
            });
        }
    }

    fn ensure_node(
        self: *Simulation,
        tile_x: i32,
        tile_y: i32,
        side: Direction,
        outbound: bool,
    ) !u32 {
        const key = NodeKey{
            .tile_x = tile_x,
            .tile_y = tile_y,
            .side = @intFromEnum(side),
            .outbound = outbound,
        };
        if (self.node_lookup.get(key)) |id| return id;

        const id: u32 = @intCast(self.nodes.items.len);
        const position = lane_connector_position(tile_x, tile_y, side, outbound);
        try self.nodes.append(self.allocator, .{
            .position = position,
            .tile_x = tile_x,
            .tile_y = tile_y,
            .side = side,
            .outbound = outbound,
        });
        try self.node_lookup.put(key, id);
        return id;
    }

    fn add_in_tile_edge(
        self: *Simulation,
        tile_x: i32,
        tile_y: i32,
        incoming_side: Direction,
        outgoing_side: Direction,
    ) !void {
        const from_node = try self.ensure_node(tile_x, tile_y, incoming_side, false);
        const to_node = try self.ensure_node(tile_x, tile_y, outgoing_side, true);
        const start = self.nodes.items[from_node].position;
        const end = self.nodes.items[to_node].position;

        const incoming_heading = direction_vector(opposite_direction(incoming_side));
        const outgoing_heading = direction_vector(outgoing_side);

        var edge: Edge = .{
            .from = from_node,
            .to = to_node,
            .length = 0,
            .edge_type = .in_tile,
            .geometry = .{ .line = .{ .start = start, .end = end } },
            .tile_x = tile_x,
            .tile_y = tile_y,
            .in_side = @intFromEnum(incoming_side),
            .out_side = @intFromEnum(outgoing_side),
        };

        if (opposite_direction(incoming_side) == outgoing_side) {
            edge.length = vector_length(end - start);
        } else {
            if (build_turn_geometry(start, end, incoming_heading, outgoing_heading, turn_radius_target)) |turn| {
                edge.geometry = .{ .turn = turn };
                edge.length = turn.len_entry + turn.len_arc + turn.len_exit;
            } else if (build_turn_arc(start, end, incoming_heading, outgoing_heading)) |arc| {
                edge.geometry = .{ .arc = arc };
                edge.length = @abs(arc.angle_delta) * arc.radius;
            } else {
                edge.length = vector_length(end - start);
            }
        }

        if (edge.length < small_distance_epsilon) return;
        try self.edges.append(self.allocator, edge);
    }

    fn add_transition_edge(
        self: *Simulation,
        from_tile_x: i32,
        from_tile_y: i32,
        outgoing_side: Direction,
        to_tile_x: i32,
        to_tile_y: i32,
        incoming_side: Direction,
    ) !void {
        const from_node = try self.ensure_node(from_tile_x, from_tile_y, outgoing_side, true);
        const to_node = try self.ensure_node(to_tile_x, to_tile_y, incoming_side, false);
        const start = self.nodes.items[from_node].position;
        const end = self.nodes.items[to_node].position;
        const length = vector_length(end - start);
        if (length < small_distance_epsilon) return;

        try self.edges.append(self.allocator, .{
            .from = from_node,
            .to = to_node,
            .length = length,
            .edge_type = .transition,
            .geometry = .{
                .line = .{
                    .start = start,
                    .end = end,
                },
            },
            .from_tile_x = from_tile_x,
            .from_tile_y = from_tile_y,
            .to_tile_x = to_tile_x,
            .to_tile_y = to_tile_y,
            .to_side = @intFromEnum(incoming_side),
        });
    }

    fn spawn_initial_cars(self: *Simulation) !void {
        if (self.nodes.items.len < 2 or self.edges.items.len == 0) return;

        const desired_count = @min(max_car_count, @as(u32, @intCast(self.nodes.items.len / 8 + 1)));
        var spawned: u32 = 0;
        while (spawned < desired_count) : (spawned += 1) {
            var car: Car = .{};
            errdefer car.route_edges.deinit(self.allocator);

            if (!try self.assign_random_route(&car, null)) break;
            const random = self.prng.random();
            car.speed_units_s = random.float(f32) * 0.25 + 0.45;
            car.acceleration_units_s2 = random.float(f32) * 0.35 + 0.75;
            car.deceleration_units_s2 = random.float(f32) * 0.7 + 1.9;
            car.velocity_units_s = 0;
            car.model_kind = random.intRangeLessThan(usize, 0, assets.car_rigs.len);
            self.update_car_pose(&car);

            if (self.car_overlaps_existing(&car)) {
                car.route_edges.deinit(self.allocator);
                continue;
            }

            try self.cars.append(self.allocator, car);
        }
    }

    fn assign_random_route(self: *Simulation, car: *Car, start_node_override: ?u32) !bool {
        const start_node = if (start_node_override) |node| node else self.random_node_with_outgoing() orelse return false;

        var attempts: u32 = 0;
        while (attempts < max_path_attempts) : (attempts += 1) {
            const destination = self.random_node_with_outgoing() orelse return false;
            if (destination == start_node) continue;

            if (try self.find_path(start_node, destination, &car.route_edges)) {
                car.route_edge_index = 0;
                car.edge_t = 0;
                car.destination_node = destination;
                car.at_node = null;
                return true;
            }
        }
        return false;
    }

    fn random_node_with_outgoing(self: *Simulation) ?u32 {
        if (self.nodes.items.len == 0) return null;
        const random = self.prng.random();

        var attempts: u32 = 0;
        while (attempts < max_spawn_attempts) : (attempts += 1) {
            const node_index = random.intRangeLessThan(usize, 0, self.nodes.items.len);
            const node_id: u32 = @intCast(node_index);
            if (self.node_has_outgoing(node_id)) return node_id;
        }
        return null;
    }

    fn node_has_outgoing(self: *const Simulation, node_id: u32) bool {
        for (self.edges.items) |edge| {
            if (edge.from == node_id) return true;
        }
        return false;
    }

    fn find_path(
        self: *Simulation,
        start_node: u32,
        goal_node: u32,
        out_edges: *std.ArrayListUnmanaged(u32),
    ) !bool {
        out_edges.clearRetainingCapacity();
        if (self.nodes.items.len == 0) return false;
        if (start_node == goal_node) return false;

        const node_count = self.nodes.items.len;
        const g_score = try self.allocator.alloc(f32, node_count);
        defer self.allocator.free(g_score);
        const f_score = try self.allocator.alloc(f32, node_count);
        defer self.allocator.free(f_score);
        const parent_node = try self.allocator.alloc(u32, node_count);
        defer self.allocator.free(parent_node);
        const parent_edge = try self.allocator.alloc(u32, node_count);
        defer self.allocator.free(parent_edge);
        const state = try self.allocator.alloc(u8, node_count);
        defer self.allocator.free(state);

        const inf = std.math.inf(f32);
        for (0..node_count) |i| {
            g_score[i] = inf;
            f_score[i] = inf;
            parent_node[i] = std.math.maxInt(u32);
            parent_edge[i] = std.math.maxInt(u32);
            state[i] = 0;
        }

        var open: std.ArrayListUnmanaged(u32) = .empty;
        defer open.deinit(self.allocator);

        const start_index: usize = @intCast(start_node);
        g_score[start_index] = 0;
        f_score[start_index] = self.heuristic(start_node, goal_node);
        state[start_index] = 1;
        try open.append(self.allocator, start_node);

        var found = false;
        while (open.items.len > 0) {
            var best_open_index: usize = 0;
            var best_node = open.items[0];
            var best_f = f_score[@intCast(best_node)];

            for (open.items[1..], 1..) |node, open_index| {
                const node_f = f_score[@intCast(node)];
                if (node_f < best_f) {
                    best_f = node_f;
                    best_node = node;
                    best_open_index = open_index;
                }
            }

            _ = open.swapRemove(best_open_index);
            const best_node_index: usize = @intCast(best_node);
            state[best_node_index] = 2;

            if (best_node == goal_node) {
                found = true;
                break;
            }

            for (self.edges.items, 0..) |edge, edge_index| {
                if (edge.from != best_node) continue;
                const neighbor = edge.to;
                const neighbor_index: usize = @intCast(neighbor);
                if (state[neighbor_index] == 2) continue;

                const tentative_g = g_score[best_node_index] + edge.length;
                if (tentative_g >= g_score[neighbor_index]) continue;

                g_score[neighbor_index] = tentative_g;
                f_score[neighbor_index] = tentative_g + self.heuristic(neighbor, goal_node);
                parent_node[neighbor_index] = best_node;
                parent_edge[neighbor_index] = @intCast(edge_index);
                if (state[neighbor_index] != 1) {
                    state[neighbor_index] = 1;
                    try open.append(self.allocator, neighbor);
                }
            }
        }

        if (!found) return false;

        var reversed_edges: std.ArrayListUnmanaged(u32) = .empty;
        defer reversed_edges.deinit(self.allocator);

        var cursor = goal_node;
        while (cursor != start_node) {
            const cursor_index: usize = @intCast(cursor);
            const edge_id = parent_edge[cursor_index];
            if (edge_id == std.math.maxInt(u32)) return false;
            try reversed_edges.append(self.allocator, edge_id);

            const prev = parent_node[cursor_index];
            if (prev == std.math.maxInt(u32)) return false;
            cursor = prev;
        }

        for (0..reversed_edges.items.len) |i| {
            const rev_index = reversed_edges.items.len - 1 - i;
            try out_edges.append(self.allocator, reversed_edges.items[rev_index]);
        }

        return out_edges.items.len > 0;
    }

    fn heuristic(self: *const Simulation, from_node: u32, to_node: u32) f32 {
        const from = self.nodes.items[@intCast(from_node)].position;
        const to = self.nodes.items[@intCast(to_node)].position;
        return vector_length(to - from);
    }

    fn update_car(self: *Simulation, car_index: u32, dt_s: f32) void {
        var car = &self.cars.items[@intCast(car_index)];

        if (car.wait_timer_s > 0) {
            car.velocity_units_s = 0;
            car.wait_timer_s = @max(0, car.wait_timer_s - dt_s);
            if (car.wait_timer_s == 0 and car.at_node != null) {
                const start_node = car.at_node.?;
                if (self.assign_random_route(car, start_node)) |ok| {
                    if (ok) {
                        car.initialized = false;
                        car.velocity_units_s = 0;
                        self.update_car_pose(car);
                    }
                } else |_| {}
            }
            return;
        }

        if (car.route_edge_index >= car.route_edges.items.len) {
            self.car_arrive(car);
            return;
        }

        const velocity_previous = car.velocity_units_s;
        const velocity_free = @min(
            car.speed_units_s,
            velocity_previous + car.acceleration_units_s2 * dt_s,
        );
        const velocity_cap_route = self.predictive_speed_cap_for_car_ahead(car_index);
        const velocity_cap_obb = self.predictive_speed_cap_for_future_collisions(
            car_index,
            velocity_free,
        );
        const velocity_target_max = @min(velocity_free, @min(velocity_cap_route, velocity_cap_obb));
        const velocity_proposed = if (velocity_target_max < velocity_previous)
            @max(
                velocity_target_max,
                velocity_previous - car.deceleration_units_s2 * dt_s,
            )
        else
            velocity_target_max;
        const move_desired = 0.5 * (velocity_previous + velocity_proposed) * dt_s;
        var move_distance_allowed = self.limit_move_for_traffic_light(car, move_desired);
        move_distance_allowed = self.limit_move_for_car_ahead(car_index, move_distance_allowed);

        if (move_distance_allowed <= 0) {
            car.velocity_units_s = @max(0, velocity_previous - car.deceleration_units_s2 * dt_s);
            return;
        }

        const move_distance_planned = @min(move_desired, move_distance_allowed);
        const move_distance_actual = self.advance_car_with_collision(car_index, move_distance_planned);
        if (move_distance_actual <= 0) {
            car.velocity_units_s = @max(0, velocity_previous - car.deceleration_units_s2 * dt_s);
            return;
        }

        const velocity_required = @max(0, (2.0 * move_distance_actual / dt_s) - velocity_previous);
        const velocity_min_after_brake = @max(
            0,
            velocity_previous - car.deceleration_units_s2 * dt_s,
        );
        car.velocity_units_s = std.math.clamp(
            velocity_required,
            velocity_min_after_brake,
            velocity_proposed,
        );

        if (car.route_edge_index >= car.route_edges.items.len) {
            self.car_arrive(car);
        }
    }

    fn advance_car_with_collision(self: *Simulation, car_index: u32, move_distance: f32) f32 {
        var moved_total: f32 = 0;
        var remaining = move_distance;

        while (remaining > 0) {
            const step_distance = @min(remaining, collision_substep_distance);
            const car = &self.cars.items[@intCast(car_index)];

            const previous = snapshot_car_state(car);

            self.advance_car(car, step_distance);
            self.update_car_pose(car);

            if (self.car_overlaps_any(car_index)) {
                restore_car_state(car, previous);
                break;
            }

            moved_total += step_distance;
            remaining -= step_distance;
            if (car.route_edge_index >= car.route_edges.items.len) break;
        }

        return moved_total;
    }

    fn snapshot_car_state(car: *const Car) CarAdvanceState {
        return .{
            .route_edge_index = car.route_edge_index,
            .edge_t = car.edge_t,
            .rear_axle = car.rear_axle,
            .front_axle = car.front_axle,
            .heading_rad = car.heading_rad,
            .steering_angle_rad = car.steering_angle_rad,
            .initialized = car.initialized,
        };
    }

    fn restore_car_state(car: *Car, state: CarAdvanceState) void {
        car.route_edge_index = state.route_edge_index;
        car.edge_t = state.edge_t;
        car.rear_axle = state.rear_axle;
        car.front_axle = state.front_axle;
        car.heading_rad = state.heading_rad;
        car.steering_angle_rad = state.steering_angle_rad;
        car.initialized = state.initialized;
    }

    fn car_arrive(self: *Simulation, car: *Car) void {
        car.at_node = car.destination_node;
        car.velocity_units_s = 0;
        const random = self.prng.random();
        car.wait_timer_s = random.float(f32) * 2.0 + 1.0;
    }

    fn limit_move_for_traffic_light(self: *const Simulation, car: *const Car, move_distance: f32) f32 {
        const current = self.route_edge_ref(car, 0) orelse return 0;
        const next = self.route_edge_ref(car, 1) orelse return move_distance;
        const current_edge = current.edge.*;
        const next_edge = next.edge.*;

        if (next_edge.edge_type != .transition) return move_distance;
        if (!self.has_light_at(next_edge.to_tile_x, next_edge.to_tile_y)) return move_distance;
        const remaining = current_edge.length * (1.0 - car.edge_t);
        const stop_distance = @max(0, remaining - traffic_light_stop_margin);
        if (self.light_blocks(next_edge.to_tile_x, next_edge.to_tile_y, next_edge.to_side) or
            !self.intersection_entry_allowed(car))
        {
            if (remaining > move_distance + traffic_light_stop_margin) return move_distance;
            return stop_distance;
        }
        return move_distance;
    }

    fn limit_move_for_car_ahead(self: *const Simulation, car_index: u32, move_distance: f32) f32 {
        var allowed = move_distance;
        const car_index_usize: usize = @intCast(car_index);
        const car = self.cars.items[car_index_usize];
        if (self.route_edge_ref(&car, 0) == null) return allowed;

        for (self.cars.items, 0..) |other, other_index| {
            if (other_index == car_index_usize) continue;
            if (other.route_edge_index >= other.route_edges.items.len) continue;
            const distance_ahead = self.route_distance_to_other_ahead(&car, &other) orelse continue;
            const desired_gap = self.desired_follow_gap(&car, &other);
            if (distance_ahead < desired_gap + allowed) {
                allowed = @min(allowed, @max(0, distance_ahead - desired_gap));
            }
        }

        return allowed;
    }

    fn predictive_speed_cap_for_car_ahead(self: *const Simulation, car_index: u32) f32 {
        const car_index_usize: usize = @intCast(car_index);
        const car = self.cars.items[car_index_usize];
        if (self.route_edge_ref(&car, 0) == null) return car.speed_units_s;

        var speed_cap = car.speed_units_s;
        for (self.cars.items, 0..) |other, other_index| {
            if (other_index == car_index_usize) continue;
            if (other.route_edge_index >= other.route_edges.items.len) continue;

            const distance_ahead = self.route_distance_to_other_ahead(&car, &other) orelse continue;
            const desired_gap = self.desired_follow_gap(&car, &other) + follow_prediction_margin;
            const cap = other.velocity_units_s +
                (distance_ahead - desired_gap) / follow_prediction_horizon_s;
            speed_cap = @min(speed_cap, @max(0, cap));
        }

        return speed_cap;
    }

    fn desired_follow_gap(self: *const Simulation, car: *const Car, other: *const Car) f32 {
        const base_gap =
            (self.car_half_length_world(car.model_kind) + self.car_half_length_world(other.model_kind)) *
            follow_base_gap_factor;
        return base_gap + @max(car.velocity_units_s, other.velocity_units_s) * follow_headway_s;
    }

    fn has_light_at(self: *const Simulation, tile_x: i32, tile_y: i32) bool {
        for (self.lights.items) |light| {
            if (light.tile_x == tile_x and light.tile_y == tile_y) return true;
        }
        return false;
    }

    fn intersection_entry_allowed(self: *const Simulation, car: *const Car) bool {
        const current = self.route_edge_ref(car, 0) orelse return false;
        const next = self.route_edge_ref(car, 1) orelse return true;
        const current_edge = current.edge.*;
        const next_edge = next.edge.*;
        if (next_edge.edge_type != .transition) return true;
        if (!self.has_light_at(next_edge.to_tile_x, next_edge.to_tile_y)) return true;
        if (self.intersection_has_cars_inside(
            next_edge.to_tile_x,
            next_edge.to_tile_y,
            car,
        )) return false;

        var distance_to_clear = next_edge.length + self.car_length_world(car.model_kind) + intersection_clearance_margin;
        if (car.route_edge_index + 2 < car.route_edges.items.len) {
            const through_edge_id = car.route_edges.items[@intCast(car.route_edge_index + 2)];
            const through_edge = self.edges.items[@intCast(through_edge_id)];
            distance_to_clear += through_edge.length;
        }

        const remaining_to_stop = @max(
            0,
            current_edge.length * (1.0 - car.edge_t) - traffic_light_stop_margin,
        );
        const ahead = self.nearest_route_car_ahead(car) orelse return true;
        const other = self.cars.items[ahead.other_index];
        const gap_needed = self.desired_follow_gap(car, &other);
        return ahead.distance >= remaining_to_stop + distance_to_clear + gap_needed;
    }

    fn intersection_has_cars_inside(
        self: *const Simulation,
        tile_x: i32,
        tile_y: i32,
        requester: *const Car,
    ) bool {
        for (self.cars.items, 0..) |_, other_index| {
            const other_ptr = &self.cars.items[other_index];
            if (other_ptr == requester) continue;
            if (self.car_occupies_tile(other_ptr, tile_x, tile_y)) return true;
        }
        return false;
    }

    fn car_occupies_tile(
        self: *const Simulation,
        car: *const Car,
        tile_x: i32,
        tile_y: i32,
    ) bool {
        const edge_ref = self.route_edge_ref(car, 0) orelse return false;
        const edge = edge_ref.edge.*;
        return switch (edge.edge_type) {
            .in_tile => edge.tile_x == tile_x and edge.tile_y == tile_y,
            .transition => blk: {
                const in_from = edge.from_tile_x == tile_x and edge.from_tile_y == tile_y and car.edge_t < 0.95;
                const in_to = edge.to_tile_x == tile_x and edge.to_tile_y == tile_y and car.edge_t > 0.05;
                break :blk in_from or in_to;
            },
        };
    }

    fn nearest_route_car_ahead(self: *const Simulation, car: *const Car) ?AheadInfo {
        var nearest: ?AheadInfo = null;
        for (self.cars.items, 0..) |other, other_index| {
            if (&self.cars.items[other_index] == car) continue;
            if (other.route_edge_index >= other.route_edges.items.len) continue;

            const distance = self.route_distance_to_other_ahead(car, &other) orelse continue;
            if (nearest == null or distance < nearest.?.distance) {
                nearest = .{
                    .distance = distance,
                    .other_index = other_index,
                };
            }
        }
        return nearest;
    }

    fn predictive_speed_cap_for_future_collisions(
        self: *const Simulation,
        car_index: u32,
        velocity_limit: f32,
    ) f32 {
        const car_index_usize: usize = @intCast(car_index);
        const car = self.cars.items[car_index_usize];
        if (self.route_edge_ref(&car, 0) == null) return 0;

        var speed_cap = velocity_limit;
        for (self.cars.items, 0..) |other, other_index| {
            if (other_index == car_index_usize) continue;
            if (other.route_edge_index >= other.route_edges.items.len and other.wait_timer_s <= 0) continue;

            if (!self.future_obb_overlap_for_speed(&car, &other, speed_cap)) continue;

            var low: f32 = 0;
            var high = speed_cap;
            var step: u32 = 0;
            while (step < future_collision_binary_search_steps) : (step += 1) {
                const mid = 0.5 * (low + high);
                if (self.future_obb_overlap_for_speed(&car, &other, mid)) {
                    high = mid;
                } else {
                    low = mid;
                }
            }

            speed_cap = @min(speed_cap, low);
            if (speed_cap <= small_distance_epsilon) return 0;
        }

        return speed_cap;
    }

    fn future_obb_overlap_for_speed(
        self: *const Simulation,
        car: *const Car,
        other: *const Car,
        car_speed_units_s: f32,
    ) bool {
        var sample_index: u32 = 1;
        while (sample_index <= future_collision_sample_count) : (sample_index += 1) {
            const t = future_collision_horizon_s *
                (@as(f32, @floatFromInt(sample_index)) / @as(f32, @floatFromInt(future_collision_sample_count)));
            const car_obb = self.predicted_obb_at_time(car, t, car_speed_units_s);
            const other_speed = if (other.wait_timer_s > 0) 0 else other.velocity_units_s;
            const other_obb = self.predicted_obb_at_time(other, t, other_speed);
            if (obb_overlap(
                obb_with_margin(car_obb, future_collision_margin),
                obb_with_margin(other_obb, future_collision_margin),
            )) {
                return true;
            }
        }
        return false;
    }

    fn predicted_obb_at_time(
        self: *const Simulation,
        car: *const Car,
        time_s: f32,
        speed_units_s: f32,
    ) OBB {
        var predicted = car.*;
        if (speed_units_s > 0 and predicted.route_edge_index < predicted.route_edges.items.len) {
            self.advance_car(&predicted, speed_units_s * time_s);
            self.update_car_pose(&predicted);
        }
        return self.car_to_obb(&predicted);
    }

    fn route_distance_to_other_ahead(self: *const Simulation, car: *const Car, other: *const Car) ?f32 {
        if (car.route_edge_index >= car.route_edges.items.len) return null;
        if (other.route_edge_index >= other.route_edges.items.len) return null;

        const other_edge_id = other.route_edges.items[@intCast(other.route_edge_index)];
        var route_index = car.route_edge_index;
        var scanned_edges: u32 = 0;
        var distance_to_edge_start: f32 = 0;

        while (route_index < car.route_edges.items.len and scanned_edges < follow_scan_edge_count_max and distance_to_edge_start <= follow_scan_distance_max) {
            const edge_id = car.route_edges.items[@intCast(route_index)];
            const edge = self.edges.items[@intCast(edge_id)];

            if (edge_id == other_edge_id) {
                if (route_index == car.route_edge_index) {
                    if (other.edge_t > car.edge_t) {
                        return (other.edge_t - car.edge_t) * edge.length;
                    }
                } else {
                    return distance_to_edge_start + other.edge_t * edge.length;
                }
            }

            const edge_advance = if (route_index == car.route_edge_index)
                edge.length * (1.0 - car.edge_t)
            else
                edge.length;
            distance_to_edge_start += edge_advance;
            route_index += 1;
            scanned_edges += 1;
        }

        return null;
    }

    fn light_blocks(self: *const Simulation, tile_x: i32, tile_y: i32, incoming_side_raw: u2) bool {
        for (self.lights.items) |light| {
            if (light.tile_x != tile_x or light.tile_y != tile_y) continue;

            const incoming_side = direction_from_index(incoming_side_raw);
            const is_ns = incoming_side == .north or incoming_side == .south;
            if (is_ns) return !light.ns_green;
            return light.ns_green;
        }
        return false;
    }

    fn advance_car(self: *const Simulation, car: *Car, move_distance: f32) void {
        var remaining = move_distance;
        while (remaining > 0 and car.route_edge_index < car.route_edges.items.len) {
            const edge_id = car.route_edges.items[@intCast(car.route_edge_index)];
            const edge = self.edges.items[@intCast(edge_id)];
            if (edge.length < small_distance_epsilon) {
                car.route_edge_index += 1;
                car.edge_t = 0;
                continue;
            }

            const edge_remaining = edge.length * (1.0 - car.edge_t);
            if (remaining < edge_remaining) {
                car.edge_t += remaining / edge.length;
                remaining = 0;
            } else {
                remaining -= edge_remaining;
                car.route_edge_index += 1;
                car.edge_t = 0;
            }
        }
    }

    fn update_car_pose(self: *const Simulation, car: *Car) void {
        if (car.route_edges.items.len == 0) return;

        var sample: Sample = undefined;
        if (car.route_edge_index >= car.route_edges.items.len) {
            const final_edge_id = car.route_edges.items[car.route_edges.items.len - 1];
            const final_edge = self.edges.items[@intCast(final_edge_id)];
            sample = edge_sample(final_edge, 1.0);
        } else {
            const edge_id = car.route_edges.items[@intCast(car.route_edge_index)];
            const edge = self.edges.items[@intCast(edge_id)];
            sample = edge_sample(edge, car.edge_t);
        }

        const wheelbase = self.car_wheelbase_world(car.model_kind);
        car.front_axle = sample.position;
        if (!car.initialized) {
            car.rear_axle = car.front_axle - sample.tangent * @as(vec2, @splat(wheelbase));
            car.initialized = true;
        } else {
            const front_to_rear = car.front_axle - car.rear_axle;
            if (vector_length(front_to_rear) < small_length_epsilon) {
                car.rear_axle = car.front_axle - sample.tangent * @as(vec2, @splat(wheelbase));
            } else {
                const follow_direction = vector_normalize(front_to_rear);
                car.rear_axle = car.front_axle - follow_direction * @as(vec2, @splat(wheelbase));
            }
        }

        const heading = vector_normalize(car.front_axle - car.rear_axle);
        car.heading_rad = std.math.atan2(heading[1], heading[0]);
        const front_path_heading_rad = std.math.atan2(sample.tangent[1], sample.tangent[0]);
        const steer_delta = normalize_angle_pi(front_path_heading_rad - car.heading_rad);
        car.steering_angle_rad = std.math.clamp(steer_delta, -0.8, 0.8);
    }

    fn car_overlaps_existing(self: *const Simulation, car: *const Car) bool {
        const car_obb = self.car_to_obb(car);
        for (self.cars.items) |other| {
            const other_obb = self.car_to_obb(&other);
            if (obb_overlap(car_obb, other_obb)) return true;
        }
        return false;
    }

    fn car_overlaps_any(self: *const Simulation, car_index: u32) bool {
        const car = self.cars.items[@intCast(car_index)];
        const car_obb = self.car_to_obb(&car);
        for (self.cars.items, 0..) |other, other_index| {
            if (other_index == car_index) continue;
            const other_obb = self.car_to_obb(&other);
            if (obb_overlap(car_obb, other_obb)) return true;
        }
        return false;
    }

    fn car_to_obb(self: *const Simulation, car: *const Car) OBB {
        _ = self;
        const rig = assets.car_rigs[car.model_kind];
        const forward = vec2{ @cos(car.heading_rad), @sin(car.heading_rad) };
        const right = right_normal(forward);
        const bbox_center_x = 0.5 * (rig.bbox_min_x_model + rig.bbox_max_x_model) * car_model_scale;
        const bbox_center_y = 0.5 * (rig.bbox_min_y_model + rig.bbox_max_y_model) * car_model_scale;
        const rear_axle_y = rig.rear_axle_y_model * car_model_scale;
        const center = car.rear_axle +
            forward * @as(vec2, @splat(rear_axle_y - bbox_center_y)) -
            right * @as(vec2, @splat(bbox_center_x));
        return .{
            .center = center,
            .axis_forward = forward,
            .axis_right = right,
            .half_length = 0.5 * (rig.bbox_max_y_model - rig.bbox_min_y_model) * car_model_scale,
            .half_width = 0.5 * (rig.bbox_max_x_model - rig.bbox_min_x_model) * car_model_scale,
        };
    }
};

fn direction_from_index(index: u2) Direction {
    return @enumFromInt(index);
}

fn opposite_direction(direction: Direction) Direction {
    const direction_raw: u4 = @intFromEnum(direction);
    const opposite_raw: u2 = @intCast((direction_raw + 2) & 3);
    return @enumFromInt(opposite_raw);
}

fn direction_vector(direction: Direction) vec2 {
    return switch (direction) {
        .north => .{ 0, 1 },
        .east => .{ 1, 0 },
        .south => .{ 0, -1 },
        .west => .{ -1, 0 },
    };
}

fn right_normal(direction: vec2) vec2 {
    return .{ direction[1], -direction[0] };
}

fn left_normal(direction: vec2) vec2 {
    return .{ -direction[1], direction[0] };
}

fn lane_connector_position(tile_x: i32, tile_y: i32, side: Direction, outbound: bool) vec2 {
    const center = vec2{
        @as(f32, @floatFromInt(tile_x)) + 0.5,
        @as(f32, @floatFromInt(tile_y)) + 0.5,
    };
    const side_offset = direction_vector(side) * @as(vec2, @splat(connector_inset));
    const heading = if (outbound) side else opposite_direction(side);
    const lateral_offset = right_normal(direction_vector(heading)) * @as(vec2, @splat(lane_center_offset));
    return center + side_offset + lateral_offset;
}

fn build_turn_geometry(
    start: vec2,
    end: vec2,
    heading_start: vec2,
    heading_end: vec2,
    radius_target: f32,
) ?TurnGeometry {
    const cross_z = heading_start[0] * heading_end[1] - heading_start[1] * heading_end[0];
    if (@abs(cross_z) < 0.5) return null;

    const delta = end - start;
    const determinant = heading_start[0] * heading_end[1] - heading_start[1] * heading_end[0];
    if (@abs(determinant) < small_length_epsilon) return null;

    const t0 = (delta[0] * heading_end[1] - delta[1] * heading_end[0]) / determinant;
    const t1 = (heading_start[0] * delta[1] - heading_start[1] * delta[0]) / determinant;
    if (t0 <= 0.03 or t1 <= 0.03) return null;
    const intersection = start + heading_start * @as(vec2, @splat(t0));

    const turn_angle = std.math.acos(std.math.clamp(la.dot(vec2, heading_start, heading_end), -1, 1));
    if (turn_angle < small_angle_epsilon) return null;
    const tan_half = @tan(turn_angle * 0.5);
    if (@abs(tan_half) < small_length_epsilon) return null;

    const d_target = radius_target * tan_half;
    const d_max = @min(t0 * 0.92, t1 * 0.92);
    if (d_max < 0.01) return null;
    const d = @min(d_target, d_max);
    if (d <= 0.01) return null;

    const radius = d / tan_half;
    const entry = intersection - heading_start * @as(vec2, @splat(d));
    const exit = intersection + heading_end * @as(vec2, @splat(d));

    const normal = if (cross_z > 0) left_normal(heading_start) else right_normal(heading_start);
    const center = entry + normal * @as(vec2, @splat(radius));
    const start_angle = std.math.atan2(entry[1] - center[1], entry[0] - center[0]);
    const end_angle = std.math.atan2(exit[1] - center[1], exit[0] - center[0]);
    var angle_delta = normalize_angle_pi(end_angle - start_angle);
    if (cross_z > 0 and angle_delta < 0) angle_delta += 2.0 * std.math.pi;
    if (cross_z < 0 and angle_delta > 0) angle_delta -= 2.0 * std.math.pi;

    const len_entry = vector_length(entry - start);
    const len_arc = @abs(angle_delta) * radius;
    const len_exit = vector_length(end - exit);
    if (len_arc < small_distance_epsilon) return null;

    return .{
        .start = start,
        .entry = entry,
        .exit = exit,
        .end = end,
        .arc_center = center,
        .arc_radius = radius,
        .arc_start_angle = start_angle,
        .arc_angle_delta = angle_delta,
        .len_entry = len_entry,
        .len_arc = len_arc,
        .len_exit = len_exit,
    };
}

fn build_turn_arc(start: vec2, end: vec2, heading_start: vec2, heading_end: vec2) ?ArcGeometry {
    const cross_z = heading_start[0] * heading_end[1] - heading_start[1] * heading_end[0];
    if (@abs(cross_z) < 0.5) return null;

    const n0 = if (cross_z > 0) left_normal(heading_start) else right_normal(heading_start);
    const n1 = if (cross_z > 0) left_normal(heading_end) else right_normal(heading_end);
    const delta = end - start;
    const denominator = n0 - n1;

    var radius_signed: f32 = 0;
    if (@abs(denominator[0]) > @abs(denominator[1])) {
        if (@abs(denominator[0]) < small_length_epsilon) return null;
        radius_signed = delta[0] / denominator[0];
    } else {
        if (@abs(denominator[1]) < small_length_epsilon) return null;
        radius_signed = delta[1] / denominator[1];
    }

    const center = start + n0 * @as(vec2, @splat(radius_signed));
    const radius = @abs(radius_signed);
    if (radius < small_distance_epsilon) return null;

    const angle_start = std.math.atan2(start[1] - center[1], start[0] - center[0]);
    const angle_end = std.math.atan2(end[1] - center[1], end[0] - center[0]);
    var angle_delta = normalize_angle_pi(angle_end - angle_start);
    if (cross_z > 0 and angle_delta < 0) angle_delta += 2.0 * std.math.pi;
    if (cross_z < 0 and angle_delta > 0) angle_delta -= 2.0 * std.math.pi;

    return .{
        .center = center,
        .radius = radius,
        .start_angle = angle_start,
        .angle_delta = angle_delta,
    };
}

fn normalize_angle_pi(angle: f32) f32 {
    var normalized = angle;
    while (normalized > std.math.pi) normalized -= 2.0 * std.math.pi;
    while (normalized < -std.math.pi) normalized += 2.0 * std.math.pi;
    return normalized;
}

fn arc_polyline_step_count(angle_delta: f32) u32 {
    return @max(4, @as(u32, @intFromFloat(@ceil(@abs(angle_delta) / debug_arc_segment_angle_step_rad))));
}

fn vector_length(vector: vec2) f32 {
    return @sqrt(vector[0] * vector[0] + vector[1] * vector[1]);
}

fn vector_normalize(vector: vec2) vec2 {
    const len = vector_length(vector);
    if (len < small_length_epsilon) return .{ 1, 0 };
    return vector / @as(vec2, @splat(len));
}

fn line_sample(start: vec2, end: vec2, t_input: f32) Sample {
    const t = std.math.clamp(t_input, 0, 1);
    const tangent = vector_normalize(end - start);
    return .{
        .position = start + (end - start) * @as(vec2, @splat(t)),
        .tangent = tangent,
        .curvature = 0,
    };
}

fn arc_sample(
    center: vec2,
    radius: f32,
    start_angle: f32,
    angle_delta: f32,
    t_input: f32,
) Sample {
    const t = std.math.clamp(t_input, 0, 1);
    const angle = start_angle + angle_delta * t;
    const radial = vec2{ @cos(angle), @sin(angle) };
    const tangent = if (angle_delta >= 0)
        vec2{ -radial[1], radial[0] }
    else
        vec2{ radial[1], -radial[0] };
    const curvature_sign: f32 = if (angle_delta >= 0) 1 else -1;
    return .{
        .position = center + radial * @as(vec2, @splat(radius)),
        .tangent = tangent,
        .curvature = curvature_sign / radius,
    };
}

fn edge_sample(edge: Edge, t_input: f32) Sample {
    const t = std.math.clamp(t_input, 0, 1);
    const s = edge.length * t;
    return switch (edge.geometry) {
        .line => |line| blk: {
            const tangent = vector_normalize(line.end - line.start);
            break :blk .{
                .position = line.start + (line.end - line.start) * @as(vec2, @splat(t)),
                .tangent = tangent,
                .curvature = 0,
            };
        },
        .arc => |arc| arc_sample(arc.center, arc.radius, arc.start_angle, arc.angle_delta, t),
        .turn => |turn| blk: {
            if (s <= turn.len_entry or turn.len_arc < small_length_epsilon) {
                break :blk line_sample(turn.start, turn.entry, if (turn.len_entry > small_length_epsilon) s / turn.len_entry else 1.0);
            }
            if (s < turn.len_entry + turn.len_arc) {
                const arc_t = (s - turn.len_entry) / turn.len_arc;
                break :blk arc_sample(
                    turn.arc_center,
                    turn.arc_radius,
                    turn.arc_start_angle,
                    turn.arc_angle_delta,
                    arc_t,
                );
            }
            break :blk line_sample(
                turn.exit,
                turn.end,
                if (turn.len_exit > small_length_epsilon) (s - turn.len_entry - turn.len_arc) / turn.len_exit else 1.0,
            );
        },
    };
}

fn axis_projection_radius(obb: OBB, axis: vec2) f32 {
    const x = @abs(la.dot(vec2, obb.axis_forward, axis)) * obb.half_length;
    const y = @abs(la.dot(vec2, obb.axis_right, axis)) * obb.half_width;
    return x + y;
}

fn obb_with_margin(obb: OBB, margin: f32) OBB {
    return .{
        .center = obb.center,
        .axis_forward = obb.axis_forward,
        .axis_right = obb.axis_right,
        .half_length = obb.half_length + margin,
        .half_width = obb.half_width + margin,
    };
}

fn obb_overlap(a: OBB, b: OBB) bool {
    const center_delta = b.center - a.center;
    const axes = [_]vec2{
        a.axis_forward,
        a.axis_right,
        b.axis_forward,
        b.axis_right,
    };

    for (axes) |axis_raw| {
        const axis = vector_normalize(axis_raw);
        const distance = @abs(la.dot(vec2, center_delta, axis));
        const limit = axis_projection_radius(a, axis) + axis_projection_radius(b, axis);
        if (distance > limit) return false;
    }
    return true;
}
