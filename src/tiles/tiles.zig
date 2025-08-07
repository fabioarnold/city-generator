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
        0, 0, 0, 8,  0,
        8, 0, 0, 16, 0,
        8, 8, 0, 16, 8,
        0, 8, 0, 8,  8,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
    },
};

pub const curb: Tile = .{
    .vertex_data = &[_]f32{
        0, 0, 1, 24, 24,
        8, 0, 1, 32, 24,
        8, 8, 1, 32, 32,
        0, 8, 1, 24, 32,

        0, 0, 0, 24, 24,
        0, 8, 0, 24, 32,
        0, 8, 1, 25, 32,
        0, 0, 1, 25, 24,
    },
    .index_data = &[_]u16{
        0, 1, 2, 0, 2, 3,
        4, 5, 6, 4, 6, 7,
    },
};
