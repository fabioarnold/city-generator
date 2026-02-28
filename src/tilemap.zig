const std = @import("std");
const builtin = @import("builtin");
const wasm = @import("engine/web/wasm.zig");

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
};

pub fn is_street(index: u6) bool {
    if (index == 0 or index > tile_infos.len) return false;
    return tile_infos[index - 1].is_street;
}

pub fn is_building(index: u6) bool {
    if (index == 0 or index > tile_infos.len) return false;
    return tile_infos[index - 1].is_building;
}

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

    pub fn get_tile(self: *TileMap, x: i32, y: i32) Tile {
        const key = LocationKey.from_pos(x, y);
        if (self.chunks.get(key)) |chunk| {
            const lx: usize = @intCast(@mod(x, chunk_size));
            const ly: usize = @intCast(@mod(y, chunk_size));
            return chunk.tiles[ly][lx];
        }
        return .{};
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

        const res: Tile = switch (mask) {
            0 => .{ .index = 9, .rot = 0 },
            1 => .{ .index = 9, .rot = 0 },
            2 => .{ .index = 9, .rot = 1 },
            3 => .{ .index = 10, .rot = 2 },
            4 => .{ .index = 9, .rot = 0 },
            5 => .{ .index = 9, .rot = 0 },
            6 => .{ .index = 10, .rot = 1 },
            7 => .{ .index = 12, .rot = 1 },
            8 => .{ .index = 9, .rot = 1 },
            9 => .{ .index = 10, .rot = 3 },
            10 => .{ .index = 9, .rot = 1 },
            11 => .{ .index = 12, .rot = 2 },
            12 => .{ .index = 10, .rot = 0 },
            13 => .{ .index = 12, .rot = 3 },
            14 => .{ .index = 12, .rot = 0 },
            15 => .{ .index = 11, .rot = 0 },
        };

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
        if (is_street(self.get_tile(x, y - 1).index)) rot = 0 else if (is_street(self.get_tile(x - 1, y).index)) rot = 1 else if (is_street(self.get_tile(x, y + 1).index)) rot = 2 else if (is_street(self.get_tile(x + 1, y).index)) rot = 3 else rot = random.int(u2);

        try self.set_tile(x, y, .{ .index = index, .rot = rot });
    }

    pub fn save_state(self: *TileMap) !void {
        var out_list = std.ArrayList(u8).empty;
        defer out_list.deinit(self.allocator);

        const count: u32 = @intCast(self.chunks.count());
        try out_list.appendSlice(self.allocator, std.mem.asBytes(&count));

        var iterator = self.chunks.iterator();
        while (iterator.next()) |entry| {
            try out_list.appendSlice(self.allocator, std.mem.asBytes(&entry.key_ptr.*));
            try out_list.appendSlice(self.allocator, std.mem.asBytes(&entry.value_ptr.*.tiles));
        }

        if (builtin.cpu.arch.isWasm()) {
            wasm.js_save_state(out_list.items);
        }
    }

    pub fn load_state(self: *TileMap) !void {
        if (builtin.cpu.arch.isWasm()) {
            const size = wasm.js_get_state_size();
            if (size == 0) return;
            const buf = try self.allocator.alloc(u8, size);
            defer self.allocator.free(buf);
            wasm.js_read_state(buf);

            var stream = std.io.fixedBufferStream(buf);
            const reader = stream.reader();

            var iterator = self.chunks.iterator();
            while (iterator.next()) |entry| {
                self.allocator.destroy(entry.value_ptr.*);
            }
            self.chunks.clearAndFree();

            const count = reader.readInt(u32, .little) catch return;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                var key: LocationKey = undefined;
                const bytes_read_key = reader.readAll(std.mem.asBytes(&key)) catch return;
                if (bytes_read_key != @sizeOf(LocationKey)) return;

                var tiles: [chunk_size][chunk_size]Tile = undefined;
                const bytes_read_tiles = reader.readAll(std.mem.asBytes(&tiles)) catch return;
                if (bytes_read_tiles != @sizeOf(@TypeOf(tiles))) return;

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
