const std = @import("std");
const builtin = @import("builtin");
const wasm = @import("engine/web/wasm.zig");
const assets = @import("assets.zig");

pub const chunk_size = 8;

pub const LocationKey = packed struct(u32) {
    x: i16,
    y: i16,

    pub fn from_pos(x: i32, y: i32) LocationKey {
        return .{
            .x = @intCast(@divFloor(x, chunk_size)),
            .y = @intCast(@divFloor(y, chunk_size)),
        };
    }
};

pub const Tile = packed struct(u8) {
    index: u6 = 0,
    rot: u2 = 0,
};

pub const TileChunk = struct {
    tiles: [chunk_size][chunk_size]Tile = @splat(@splat(.{})),
    count: u16 = 0, // Number of non-empty tiles.
};

pub const TileInfo = struct {
    is_street: bool = false,
    is_building: bool = false,
    is_park: bool = false,
};

pub const tile_infos = [_]TileInfo{
    .{ .is_building = true }, // building_a (1)
    .{ .is_building = true }, // building_b
    .{ .is_building = true }, // building_c
    .{ .is_building = true }, // building_d
    .{ .is_building = true }, // building_e
    .{ .is_building = true }, // building_f
    .{ .is_building = true }, // building_g
    .{ .is_building = true }, // building_h (8)
    .{ .is_street = true }, // road_straight (9)
    .{ .is_street = true }, // road_corner (10)
    .{ .is_street = true }, // road_crossing (11)
    .{ .is_street = true }, // road_tsplit (12)
    .{ .is_street = true }, // road_junction (13)
    .{ .is_park = true }, // park (14)
};

pub fn is_street(index: u6) bool {
    if (index == 0 or index > tile_infos.len) return false;
    return tile_infos[index - 1].is_street;
}

pub fn is_building(index: u6) bool {
    if (index == 0 or index > tile_infos.len) return false;
    return tile_infos[index - 1].is_building;
}

pub fn is_park(index: u6) bool {
    if (index == 0 or index > tile_infos.len) return false;
    return tile_infos[index - 1].is_park;
}

pub const StreetTile = struct {
    index: u6,
    mask: u4, // bit 0: North, bit 1: East, bit 2: South, bit 3: West
};

pub const tile_set = [_]StreetTile{
    .{ .index = assets.tile_road_straight, .mask = 0b0101 }, // North(1) | South(4)
    .{ .index = assets.tile_road_crossing, .mask = 0b0101 }, // North(1) | South(4)
    .{ .index = assets.tile_road_corner, .mask = 0b0110 }, // East(2) | South(4)
    .{ .index = assets.tile_road_tsplit, .mask = 0b0111 }, // North(1) | East(2) | South(4)
    .{ .index = assets.tile_road_junction, .mask = 0b1111 }, // North(1) | East(2) | South(4) | West(8)
};

pub const TileMap = struct {
    allocator: std.mem.Allocator,
    chunks: std.AutoHashMap(LocationKey, *TileChunk),

    pub fn init(allocator: std.mem.Allocator) TileMap {
        return .{
            .allocator = allocator,
            .chunks = std.AutoHashMap(LocationKey, *TileChunk).init(allocator),
        };
    }

    pub fn deinit(self: *TileMap) void {
        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk| {
            self.allocator.destroy(chunk.*);
        }
        self.chunks.deinit();
    }

    pub fn get_tile(self: *const TileMap, x: i32, y: i32) Tile {
        const key = LocationKey.from_pos(x, y);
        const chunk = self.chunks.get(key) orelse return .{};
        const lx: usize = @intCast(@mod(x, chunk_size));
        const ly: usize = @intCast(@mod(y, chunk_size));
        return chunk.tiles[ly][lx];
    }

    pub fn get_building_orientation(self: *const TileMap, x: i32, y: i32) u2 {
        if (is_street(self.get_tile(x, y - 1).index)) return 0;
        if (is_street(self.get_tile(x + 1, y).index)) return 1;
        if (is_street(self.get_tile(x, y + 1).index)) return 2;
        if (is_street(self.get_tile(x - 1, y).index)) return 3;
        return 0;
    }

    pub fn set_tile(self: *TileMap, x: i32, y: i32, tile: Tile) !void {
        const key = LocationKey.from_pos(x, y);
        const chunk = if (self.chunks.get(key)) |c| c else try self.alloc_chunk(key);

        const lx: usize = @intCast(@mod(x, chunk_size));
        const ly: usize = @intCast(@mod(y, chunk_size));

        const old_tile = chunk.tiles[ly][lx];
        if (old_tile.index == 0 and tile.index != 0) {
            chunk.count += 1;
        } else if (old_tile.index != 0 and tile.index == 0) {
            chunk.count -= 1;
        }

        chunk.tiles[ly][lx] = tile;

        if (chunk.count == 0) {
            _ = self.chunks.remove(key);
            self.allocator.destroy(chunk);
        }
    }

    fn alloc_chunk(self: *TileMap, key: LocationKey) !*TileChunk {
        const chunk = try self.allocator.create(TileChunk);
        chunk.* = .{};
        try self.chunks.put(key, chunk);
        return chunk;
    }

    pub fn get_street_autotile(self: *const TileMap, x: i32, y: i32) Tile {
        const neighbors = [_][2]i32{
            .{ 0, 1 }, // North
            .{ 1, 0 }, // East
            .{ 0, -1 }, // South
            .{ -1, 0 }, // West
        };

        var mask: u4 = 0;
        for (neighbors, 0..) |offset, i| {
            const nx = x + offset[0];
            const ny = y + offset[1];
            if (is_street(self.get_tile(nx, ny).index)) {
                mask |= @as(u4, 1) << @intCast(i);
            }
        }

        var best_score: u32 = 9999;
        var res: Tile = .{ .index = assets.tile_road_straight, .rot = 0 };

        for (tile_set) |st| {
            var rot: u2 = 0;
            while (true) {
                const rotated_mask = std.math.rotr(u4, st.mask, rot);
                const missing = @as(u32, @popCount(~rotated_mask & mask));
                const extra = @as(u32, @popCount(rotated_mask & ~mask));
                const score = missing * 10 + extra;

                if (score < best_score) {
                    best_score = score;
                    res = .{ .index = st.index, .rot = rot };
                }

                if (rot == 3) break;
                rot += 1;
            }
        }
        return res;
    }

    pub fn autotile_street(self: *TileMap, x: i32, y: i32) !void {
        const neighbors = [_][2]i32{
            .{ 0, 1 }, // North
            .{ 1, 0 }, // East
            .{ 0, -1 }, // South
            .{ -1, 0 }, // West
        };

        var mask: u4 = 0;
        for (neighbors, 0..) |offset, i| {
            const nx = x + offset[0];
            const ny = y + offset[1];
            if (is_street(self.get_tile(nx, ny).index)) {
                mask |= @as(u4, 1) << @intCast(i);
            }
        }

        var best_score: u32 = 9999;
        var res: Tile = .{ .index = assets.tile_road_straight, .rot = 0 };

        for (tile_set) |st| {
            var rot: u2 = 0;
            while (true) {
                const rotated_mask = std.math.rotr(u4, st.mask, rot);
                const missing = @as(u32, @popCount(~rotated_mask & mask));
                const extra = @as(u32, @popCount(rotated_mask & ~mask));
                // Weight missing connections heavily so we prioritize fully connecting paths
                const score = missing * 10 + extra;

                if (score < best_score) {
                    best_score = score;
                    res = .{ .index = st.index, .rot = rot };
                }

                if (rot == 3) break;
                rot += 1;
            }
        }

        const key = LocationKey.from_pos(x, y);
        const chunk = if (self.chunks.get(key)) |c| c else try self.alloc_chunk(key);
        const lx: usize = @intCast(@mod(x, chunk_size));
        const ly: usize = @intCast(@mod(y, chunk_size));

        const old_tile = chunk.tiles[ly][lx];
        if (old_tile.index == 0) chunk.count += 1;
        chunk.tiles[ly][lx] = res;
    }

    pub fn update_tile_autotiling(self: *TileMap, x: i32, y: i32) !void {
        const tile = self.get_tile(x, y);
        if (is_street(tile.index)) {
            try self.autotile_street(x, y);
        }
    }

    pub fn place_street(self: *TileMap, x: i32, y: i32) !void {
        try self.autotile_street(x, y);
        try self.update_tile_autotiling(x, y + 1);
        try self.update_tile_autotiling(x + 1, y);
        try self.update_tile_autotiling(x, y - 1);
        try self.update_tile_autotiling(x - 1, y);
    }

    pub fn place_building(self: *TileMap, x: i32, y: i32, random: std.Random) !void {
        const index = @as(u6, @intCast(random.intRangeAtMost(usize, 1, 8)));

        var rot: u2 = 0;
        if (is_street(self.get_tile(x, y - 1).index)) rot = 0 else if (is_street(self.get_tile(x + 1, y).index)) rot = 1 else if (is_street(self.get_tile(x, y + 1).index)) rot = 2 else if (is_street(self.get_tile(x - 1, y).index)) rot = 3 else rot = random.int(u2);

        try self.set_tile(x, y, .{ .index = index, .rot = rot });
    }

    pub fn place_park(self: *TileMap, x: i32, y: i32) !void {
        try self.set_tile(x, y, .{ .index = 14, .rot = 0 });
    }

    pub fn save(self: *TileMap, writer: anytype) !void {
        const count: u32 = @intCast(self.chunks.count());
        try writer.writeInt(u32, count, .little);

        var iterator = self.chunks.iterator();
        while (iterator.next()) |entry| {
            try writer.writeAll(std.mem.asBytes(&entry.key_ptr.*));
            try writer.writeAll(std.mem.asBytes(&entry.value_ptr.*.tiles));
        }
    }

    pub fn load(self: *TileMap, reader: anytype) !void {
        var iterator = self.chunks.iterator();
        while (iterator.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.chunks.clearAndFree();

        const count = try reader.readInt(u32, .little);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            var key: LocationKey = undefined;
            try reader.readNoEof(std.mem.asBytes(&key));

            var tiles: [chunk_size][chunk_size]Tile = undefined;
            try reader.readNoEof(std.mem.asBytes(&tiles));

            const chunk = try self.allocator.create(TileChunk);
            chunk.tiles = tiles;
            chunk.count = 0;
            for (tiles) |row| {
                for (row) |tile_val| {
                    if (tile_val.index != 0) chunk.count += 1;
                }
            }
            try self.chunks.put(key, chunk);
        }
    }

    pub const Bounds = struct { min_x: i32, min_y: i32, max_x: i32, max_y: i32 };

    pub fn get_bounds(self: *const TileMap) ?Bounds {
        if (self.chunks.count() == 0) return null;
        var min_x: i32 = std.math.maxInt(i32);
        var min_y: i32 = std.math.maxInt(i32);
        var max_x: i32 = std.math.minInt(i32);
        var max_y: i32 = std.math.minInt(i32);

        var iter = self.chunks.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const chunk = entry.value_ptr.*;
            for (chunk.tiles, 0..) |row, ly| {
                for (row, 0..) |tile, lx| {
                    if (tile.index > 0) {
                        const tx = @as(i32, key.x) * chunk_size + @as(i32, @intCast(lx));
                        const ty = @as(i32, key.y) * chunk_size + @as(i32, @intCast(ly));
                        if (tx < min_x) min_x = tx;
                        if (ty < min_y) min_y = ty;
                        if (tx > max_x) max_x = tx;
                        if (ty > max_y) max_y = ty;
                    }
                }
            }
        }
        return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
    }
};
