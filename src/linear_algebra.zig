const std = @import("std");
const assert = std.debug.assert;

pub const vec2 = @Vector(2, f32);
pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);
pub const quat = vec4;
pub const mat4 = [4]vec4;

pub fn vec3_from_vec4(v4: vec4) vec3 {
    return .{ v4[0], v4[1], v4[2] };
}

pub fn vec4_from_vec3(v3: vec3) vec4 {
    return .{ v3[0], v3[1], v3[2], 0 };
}

pub fn identity() mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn perspective(fovy_degrees: f32, aspect_ratio: f32, z_near: f32) mat4 {
    const f = 1.0 / @tan(std.math.degreesToRadians(fovy_degrees) * 0.5);
    return .{
        .{ f / aspect_ratio, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, 0, -1 },
        .{ 0, 0, z_near, 0 },
    };
}

pub fn perspective_x(fovx_degrees: f32, aspect_ratio: f32, z_near: f32) mat4 {
    const f = 1.0 / @tan(std.math.degreesToRadians(fovx_degrees) * 0.5);
    return .{
        .{ f, 0, 0, 0 },
        .{ 0, f * aspect_ratio, 0, 0 },
        .{ 0, 0, 0, -1 },
        .{ 0, 0, z_near, 0 },
    };
}

pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) mat4 {
    const right_left = right - left;
    const top_bottom = top - bottom;
    const far_near = far - near;

    return mat4{
        .{ 2 / right_left, 0, 0, 0 },
        .{ 0, 2 / top_bottom, 0, 0 },
        .{ 0, 0, -2 / far_near, 0 },
        .{
            -(right + left) / right_left,
            -(top + bottom) / top_bottom,
            -(far + near) / far_near,
            1,
        },
    };
}

pub fn look_at(eye: vec3, center: vec3, up: vec3) mat4 {
    const f = normalize(vec3, center - eye);
    const s = normalize(vec3, cross(f, up));
    const u = cross(s, f);

    return .{
        .{ s[0], u[0], -f[0], 0 },
        .{ s[1], u[1], -f[1], 0 },
        .{ s[2], u[2], -f[2], 0 },
        .{ -dot(vec3, s, eye), -dot(vec3, u, eye), dot(vec3, f, eye), 1 },
    };
}

pub fn translation(x: f32, y: f32, z: f32) mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ x, y, z, 1 },
    };
}

pub fn scale(x: f32, y: f32, z: f32) mat4 {
    return .{
        .{ x, 0, 0, 0 },
        .{ 0, y, 0, 0 },
        .{ 0, 0, z, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotation(angle_degrees: f32, axis: vec3) mat4 {
    var result = identity();

    const sin_theta = @sin(std.math.degreesToRadians(angle_degrees));
    const cos_theta = @cos(std.math.degreesToRadians(angle_degrees));
    const cos_value = 1 - cos_theta;

    const x = axis[0];
    const y = axis[1];
    const z = axis[2];

    result[0][0] = (x * x * cos_value) + cos_theta;
    result[0][1] = (x * y * cos_value) + (z * sin_theta);
    result[0][2] = (x * z * cos_value) - (y * sin_theta);

    result[1][0] = (y * x * cos_value) - (z * sin_theta);
    result[1][1] = (y * y * cos_value) + cos_theta;
    result[1][2] = (y * z * cos_value) + (x * sin_theta);

    result[2][0] = (z * x * cos_value) + (y * sin_theta);
    result[2][1] = (z * y * cos_value) - (x * sin_theta);
    result[2][2] = (z * z * cos_value) + cos_theta;

    return result;
}

/// XYZW
pub fn rotation_from_quat(q: quat) mat4 {
    var result: mat4 = undefined;

    const xx = q[0] * q[0];
    const yy = q[1] * q[1];
    const zz = q[2] * q[2];
    const xy = q[0] * q[1];
    const xz = q[0] * q[2];
    const yz = q[1] * q[2];
    const wx = q[3] * q[0];
    const wy = q[3] * q[1];
    const wz = q[3] * q[2];

    result[0][0] = 1 - 2 * (yy + zz);
    result[0][1] = 2 * (xy + wz);
    result[0][2] = 2 * (xz - wy);
    result[0][3] = 0;

    result[1][0] = 2 * (xy - wz);
    result[1][1] = 1 - 2 * (xx + zz);
    result[1][2] = 2 * (yz + wx);
    result[1][3] = 0;

    result[2][0] = 2 * (xz + wy);
    result[2][1] = 2 * (yz - wx);
    result[2][2] = 1 - 2 * (xx + yy);
    result[2][3] = 0;

    result[3][0] = 0;
    result[3][1] = 0;
    result[3][2] = 0;
    result[3][3] = 1;

    return result;
}

pub fn recompose(r: quat, s: vec3, t: vec3) mat4 {
    var result = rotation_from_quat(r);
    result[0] *= @splat(s[0]);
    result[1] *= @splat(s[1]);
    result[2] *= @splat(s[2]);
    result[3] = .{ t[0], t[1], t[2], 1 };
    return result;
}

/// Only works if matrix is an affine transformation.
pub fn invert_affine(m: mat4) mat4 {
    var result = mat4{
        .{ m[0][0], m[1][0], m[2][0], 0 },
        .{ m[0][1], m[1][1], m[2][1], 0 },
        .{ m[0][2], m[1][2], m[2][2], 0 },
        .{ 0, 0, 0, 1 },
    };

    const t = mul_vector(result, m[3]);
    result[3] = .{ -t[0], -t[1], -t[2], 1 };

    return result;
}

pub fn invert(m: mat4) ?mat4 {
    var inv: mat4 = undefined;

    inv[0][0] =
        m[1][1] * m[2][2] * m[3][3] -
        m[1][1] * m[2][3] * m[3][2] -
        m[2][1] * m[1][2] * m[3][3] +
        m[2][1] * m[1][3] * m[3][2] +
        m[3][1] * m[1][2] * m[2][3] -
        m[3][1] * m[1][3] * m[2][2];

    inv[1][0] =
        -m[1][0] * m[2][2] * m[3][3] +
        m[1][0] * m[2][3] * m[3][2] +
        m[2][0] * m[1][2] * m[3][3] -
        m[2][0] * m[1][3] * m[3][2] -
        m[3][0] * m[1][2] * m[2][3] +
        m[3][0] * m[1][3] * m[2][2];

    inv[2][0] =
        m[1][0] * m[2][1] * m[3][3] -
        m[1][0] * m[2][3] * m[3][1] -
        m[2][0] * m[1][1] * m[3][3] +
        m[2][0] * m[1][3] * m[3][1] +
        m[3][0] * m[1][1] * m[2][3] -
        m[3][0] * m[1][3] * m[2][1];

    inv[3][0] =
        -m[1][0] * m[2][1] * m[3][2] +
        m[1][0] * m[2][2] * m[3][1] +
        m[2][0] * m[1][1] * m[3][2] -
        m[2][0] * m[1][2] * m[3][1] -
        m[3][0] * m[1][1] * m[2][2] +
        m[3][0] * m[1][2] * m[2][1];

    inv[0][1] =
        -m[0][1] * m[2][2] * m[3][3] +
        m[0][1] * m[2][3] * m[3][2] +
        m[2][1] * m[0][2] * m[3][3] -
        m[2][1] * m[0][3] * m[3][2] -
        m[3][1] * m[0][2] * m[2][3] +
        m[3][1] * m[0][3] * m[2][2];

    inv[1][1] =
        m[0][0] * m[2][2] * m[3][3] -
        m[0][0] * m[2][3] * m[3][2] -
        m[2][0] * m[0][2] * m[3][3] +
        m[2][0] * m[0][3] * m[3][2] +
        m[3][0] * m[0][2] * m[2][3] -
        m[3][0] * m[0][3] * m[2][2];

    inv[2][1] =
        -m[0][0] * m[2][1] * m[3][3] +
        m[0][0] * m[2][3] * m[3][1] +
        m[2][0] * m[0][1] * m[3][3] -
        m[2][0] * m[0][3] * m[3][1] -
        m[3][0] * m[0][1] * m[2][3] +
        m[3][0] * m[0][3] * m[2][1];

    inv[3][1] =
        m[0][0] * m[2][1] * m[3][2] -
        m[0][0] * m[2][2] * m[3][1] -
        m[2][0] * m[0][1] * m[3][2] +
        m[2][0] * m[0][2] * m[3][1] +
        m[3][0] * m[0][1] * m[2][2] -
        m[3][0] * m[0][2] * m[2][1];

    inv[0][2] =
        m[0][1] * m[1][2] * m[3][3] -
        m[0][1] * m[1][3] * m[3][2] -
        m[1][1] * m[0][2] * m[3][3] +
        m[1][1] * m[0][3] * m[3][2] +
        m[3][1] * m[0][2] * m[1][3] -
        m[3][1] * m[0][3] * m[1][2];

    inv[1][2] =
        -m[0][0] * m[1][2] * m[3][3] +
        m[0][0] * m[1][3] * m[3][2] +
        m[1][0] * m[0][2] * m[3][3] -
        m[1][0] * m[0][3] * m[3][2] -
        m[3][0] * m[0][2] * m[1][3] +
        m[3][0] * m[0][3] * m[1][2];

    inv[2][2] =
        m[0][0] * m[1][1] * m[3][3] -
        m[0][0] * m[1][3] * m[3][1] -
        m[1][0] * m[0][1] * m[3][3] +
        m[1][0] * m[0][3] * m[3][1] +
        m[3][0] * m[0][1] * m[1][3] -
        m[3][0] * m[0][3] * m[1][1];

    inv[3][2] =
        -m[0][0] * m[1][1] * m[3][2] +
        m[0][0] * m[1][2] * m[3][1] +
        m[1][0] * m[0][1] * m[3][2] -
        m[1][0] * m[0][2] * m[3][1] -
        m[3][0] * m[0][1] * m[1][2] +
        m[3][0] * m[0][2] * m[1][1];

    inv[0][3] =
        -m[0][1] * m[1][2] * m[2][3] +
        m[0][1] * m[1][3] * m[2][2] +
        m[1][1] * m[0][2] * m[2][3] -
        m[1][1] * m[0][3] * m[2][2] -
        m[2][1] * m[0][2] * m[1][3] +
        m[2][1] * m[0][3] * m[1][2];

    inv[1][3] =
        m[0][0] * m[1][2] * m[2][3] -
        m[0][0] * m[1][3] * m[2][2] -
        m[1][0] * m[0][2] * m[2][3] +
        m[1][0] * m[0][3] * m[2][2] +
        m[2][0] * m[0][2] * m[1][3] -
        m[2][0] * m[0][3] * m[1][2];

    inv[2][3] =
        -m[0][0] * m[1][1] * m[2][3] +
        m[0][0] * m[1][3] * m[2][1] +
        m[1][0] * m[0][1] * m[2][3] -
        m[1][0] * m[0][3] * m[2][1] -
        m[2][0] * m[0][1] * m[1][3] +
        m[2][0] * m[0][3] * m[1][1];

    inv[3][3] =
        m[0][0] * m[1][1] * m[2][2] -
        m[0][0] * m[1][2] * m[2][1] -
        m[1][0] * m[0][1] * m[2][2] +
        m[1][0] * m[0][2] * m[2][1] +
        m[2][0] * m[0][1] * m[1][2] -
        m[2][0] * m[0][2] * m[1][1];

    var det = m[0][0] * inv[0][0] + m[0][1] * inv[1][0] + m[0][2] * inv[2][0] + m[0][3] * inv[3][0];
    if (det == 0)
        return null;

    det = 1.0 / det;
    inv[0] *= @splat(det);
    inv[1] *= @splat(det);
    inv[2] *= @splat(det);
    inv[3] *= @splat(det);

    return inv;
}

pub fn mul(m0: mat4, m1: mat4) mat4 {
    var result: mat4 = undefined;
    inline for (m1, 0..) |row, i| {
        const x = @shuffle(f32, row, undefined, [4]i32{ 0, 0, 0, 0 });
        const y = @shuffle(f32, row, undefined, [4]i32{ 1, 1, 1, 1 });
        const z = @shuffle(f32, row, undefined, [4]i32{ 2, 2, 2, 2 });
        const w = @shuffle(f32, row, undefined, [4]i32{ 3, 3, 3, 3 });
        result[i] = m0[0] * x + m0[1] * y + m0[2] * z + m0[3] * w;
    }
    return result;
}

pub fn muln(m: []const mat4) mat4 {
    assert(m.len > 2);
    var result: mat4 = mul(m[0], m[1]);
    for (m[2..]) |e| result = mul(result, e);
    return result;
}

pub fn mul_vector(m: mat4, v: vec4) vec4 {
    const x = m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2] + m[3][0] * v[3];
    const y = m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3];
    const z = m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3];
    const w = m[0][3] * v[0] + m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3];
    return .{ x, y, z, w };
}

pub fn dot(comptime T: type, v0: T, v1: T) f32 {
    return @reduce(.Add, v0 * v1);
}

pub fn cross(v0: vec3, v1: vec3) vec3 {
    return .{
        v0[1] * v1[2] - v0[2] * v1[1],
        v0[2] * v1[0] - v0[0] * v1[2],
        v0[0] * v1[1] - v0[1] * v1[0],
    };
}

pub fn length_squared(comptime T: type, v: T) f32 {
    return dot(T, v, v);
}

pub fn length(comptime T: type, v: T) f32 {
    return @sqrt(length_squared(T, v));
}

pub fn normalize(comptime T: type, v: T) T {
    const len = length(T, v);
    if (len < 0.001) return @splat(0);
    return v * @as(T, @splat(1.0 / len));
}

pub fn lerp(comptime T: type, v0: T, v1: T, t: f32) T {
    return v0 + (v1 - v0) * @as(T, @splat(t));
}

// Shortest path slerp between two quaternions.
// Taken from "Physically Based Rendering, 3rd Edition, Chapter 2.9.2"
// https://pbr-book.org/3ed-2018/Geometry_and_Transformations/Animating_Transformations#QuaternionInterpolation
pub fn slerp(left: quat, right: quat, t: f32) quat {
    const parallel_threshold = 0.9995;
    var cos_theta = dot(quat, left, right);
    var right1 = right;

    // We need the absolute value of the dot product to take the shortest path.
    if (cos_theta < 0) {
        cos_theta *= -1;
        right1 = -right;
    }

    if (cos_theta > parallel_threshold) {
        // Use regular old lerp to avoid numerical instability.
        return lerp(quat, left, right1, t);
    } else {
        const theta = std.math.acos(std.math.clamp(cos_theta, -1, 1));
        const thetap = theta * t;
        const qperp = normalize(quat, right1 - left * @as(quat, @splat(cos_theta)));
        return left * @as(quat, @splat(@cos(thetap))) + qperp * @as(quat, @splat(@sin(thetap)));
    }
}

pub fn interpolate_cubic(comptime T: type, p0: T, c0: T, c1: T, p1: T, t: f32) T {
    const a = lerp(T, p0, c0, t);
    const b = lerp(T, c0, c1, t);
    const c = lerp(T, c1, p1, t);
    const d = lerp(T, a, b, t);
    const e = lerp(T, b, c, t);
    return lerp(T, d, e, t);
}
