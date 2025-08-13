pub const image = struct {
    pub const pixels = @embedFile("galletcity_tiles.raw");
    pub const width = 64;
    pub const height = 168;
};

pub const Tile = struct {
    vertex_data: []const f32,
    index_data: []const u16,
};

pub const street: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, -1, 8,  0,
        8, 0, -1, 16, 0,
        8, 8, -1, 16, 8,
        0, 8, -1, 8,  8,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
    },
};

pub const street_zebra: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, -1, 16, 8,
        8, 0, -1, 24, 8,
        8, 8, -1, 24, 16,
        0, 8, -1, 16, 16,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
    },
};

pub const curb: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, 0,  24, 24,
        8, 0, 0,  32, 24,
        8, 8, 0,  32, 32,
        0, 8, 0,  24, 32,

        0, 0, -1, 24, 24,
        0, 8, -1, 24, 32,
        0, 8, 0,  25, 32,
        0, 0, 0,  25, 24,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
        4, 5, 6, 4, 6, 7,
    },
};

pub const curb_corner: Tile = .{
    .vertex_data = &[_]f32{
        4, 4, 0, 28, 28,
        4, 0, 0, 24, 24,
        0, 4, 0, 24, 24,
    },
    .index_data = &[_]u16{
        0, 1, 2,
    },
};

pub const wall: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, 0, 32, 48,
        0, 8, 0, 40, 48,
        0, 8, 8, 40, 56,
        0, 0, 8, 32, 56,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
    },
};

pub const wall_corner: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, 0, 32, 48,
        0, 0, 8, 32, 56,
        0, 8, 0, 40, 48,
        0, 8, 8, 40, 56,
        8, 0, 0, 40, 48,
        8, 0, 8, 40, 56,
    },
    .index_data = &[_]u16{
        0, 1, 2, 1, 2, 3,
        0, 1, 4, 1, 4, 5,
    },
};
