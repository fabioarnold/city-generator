const std = @import("std");
const assert = std.debug.assert;
const nvg = @import("nanovg");

pub fn mix(x: anytype, y: anytype, a: anytype) @TypeOf(x, y, a) {
    return x + (y - x) * a;
}

pub fn mix_color(x: nvg.Color, y: nvg.Color, a: f32) nvg.Color {
    return .{
        .r = mix(x.r, y.r, a),
        .g = mix(x.g, y.g, a),
        .b = mix(x.b, y.b, a),
        .a = mix(x.a, y.a, a),
    };
}

pub fn approach(origin: anytype, target: anytype, step: anytype) @TypeOf(origin, target, step) {
    assert(step >= 0);
    return if (origin < target)
        @min(origin + step, target)
    else
        @max(origin - step, target);
}

pub fn approach_wrap(origin: anytype, target: anytype, step: anytype, wrap: anytype) @TypeOf(origin, target, step, wrap) {
    assert(step >= 0);

    if (@abs(target - origin) > 0.5 * wrap) {
        if (origin < target) {
            const value = origin - step;
            if (value < 0) return @max(@mod(value, wrap), target);
            return value;
        } else {
            const value = origin + step;
            if (value > wrap) return @min(@mod(value, wrap), target);
            return value;
        }
    }

    return approach(origin, target, step);
}

pub fn map_range(x: anytype, x0: anytype, x1: anytype, y0: anytype, y1: anytype) @TypeOf(x, x0, x1, y0, y1) {
    return (x - x0) / (x1 - x0) * (y1 - y0) + y0;
}

pub fn point_in_rect(px: f32, py: f32, rx: f32, ry: f32, rw: f32, rh: f32) bool {
    return px >= rx and py >= ry and px <= rx + rw and py <= ry + rh;
}
