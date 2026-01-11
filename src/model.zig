const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const Gltf = @import("zgltf").Gltf;
const la = @import("linear_algebra.zig");
const vec3 = la.vec3;
const quat = la.vec4;
const mat4 = la.mat4;
const gl = @import("gl");
const web_gl = @import("web/gl.zig");
const shaders = @import("shaders.zig");

const Model = @This();

pub const Transform = struct {
    rotation: quat,
    scale: vec3,
    translation: vec3,

    pub fn from_node(node: *const Gltf.Node) Transform {
        return .{
            .rotation = node.rotation,
            .scale = node.scale,
            .translation = node.translation,
        };
    }

    pub fn identity() Transform {
        return .{
            .rotation = .{ 0, 0, 0, 1 },
            .scale = @splat(1),
            .translation = @splat(0),
        };
    }

    pub fn to_mat4(self: *Transform) mat4 {
        return la.recompose(self.rotation, self.scale, self.translation);
    }
};

pub const ShaderInfo = struct {
    model_loc: gl.int,
    joints_loc: gl.int = 0,
    blend_skin_loc: ?gl.int = null,
};

gltf: Gltf,
buffer_objects: []gl.uint,
textures: []gl.uint,

pub fn load(self: *Model, allocator: std.mem.Allocator, data: []align(4) const u8) !void {
    self.gltf = Gltf.init(allocator);
    try self.gltf.parse(data);
    const binary = self.gltf.glb_binary.?;

    // load buffers
    self.buffer_objects = try allocator.alloc(gl.uint, self.gltf.data.buffer_views.len);
    gl.GenBuffers(@intCast(self.buffer_objects.len), self.buffer_objects.ptr);
    for (self.gltf.data.buffer_views, self.buffer_objects) |buffer_view, buffer_object| {
        if (buffer_view.target) |target| {
            gl.BindBuffer(@intCast(@intFromEnum(target)), buffer_object);
            gl.BufferData(@intCast(@intFromEnum(target)), @intCast(buffer_view.byte_length), binary.ptr + buffer_view.byte_offset, gl.STATIC_DRAW);
        }
    }

    // load textures
    self.textures = try allocator.alloc(gl.uint, self.gltf.data.textures.len);
    if (self.textures.len > 0) {
        gl.GenTextures(@intCast(self.textures.len), self.textures.ptr);
        for (self.gltf.data.textures, 0..) |texture, i| {
            const source = blk: {
                if (texture.extensions.EXT_texture_webp) |webp| {
                    break :blk webp.source;
                }
                break :blk texture.source.?;
            };
            const image = self.gltf.data.images[source];
            const mime = image.mime_type.?;
            const sampler = self.gltf.data.samplers[texture.sampler.?]; // TODO set filter, wrap
            
            if (builtin.cpu.arch.isWasm()) {
                self.textures[i] = web_gl.loadTextureIMG(
                    image.data.?,
                    mime,
                    null,
                    null,
                    @intCast(@intFromEnum(sampler.min_filter orelse .linear)),
                    @intCast(@intFromEnum(sampler.mag_filter orelse .linear)),
                    @intCast(@intFromEnum(sampler.wrap_s)),
                    @intCast(@intFromEnum(sampler.wrap_t)),
                );
            } else {
                self.textures[i] = 0;
            }
        }
    }
}

pub fn computeAnimationDuration(self: Model, animation: *const Gltf.Animation) f32 {
    var duration: f32 = 0;
    for (animation.samplers.items) |sampler| {
        const input = self.gltf.data.accessors.items[sampler.input];
        const samples = self.getFloatBuffer(input);
        duration = @max(duration, samples[samples.len - 1]);
    }
    return duration;
}

pub fn getFloatBuffer(self: Model, accessor: Gltf.Accessor) []const f32 {
    std.debug.assert(accessor.component_type == .float);
    const binary = self.gltf.glb_binary.?;
    const buffer_view = self.gltf.data.buffer_views[accessor.buffer_view.?];
    const byte_offset = accessor.byte_offset + buffer_view.byte_offset;
    std.debug.assert(byte_offset % 4 == 0);
    const buffer: [*]align(4) const u8 = @alignCast(binary.ptr + byte_offset);
    const component_count = accessor.type.componentCount();
    const count = component_count * @as(usize, @intCast(accessor.count));
    return @as([*]const f32, @ptrCast(buffer))[0..count];
}

pub fn access(comptime T: type, data: []const f32, i: usize) T {
    return switch (T) {
        vec3 => .{ data[3 * i + 0], data[3 * i + 1], data[3 * i + 2] },
        quat => .{ data[4 * i + 0], data[4 * i + 1], data[4 * i + 2], data[4 * i + 3] }, // TODO: swizzle?
        mat4 => .{
            data[16 * i ..][0..4].*,
            data[16 * i ..][4..8].*,
            data[16 * i ..][8..12].*,
            data[16 * i ..][12..16].*,
        },
        else => @compileError("unexpected type"),
    };
}

fn bindVertexAttrib(self: Model, accessor_index: usize, attrib_index: usize) void {
    const accessor = self.gltf.data.accessors[accessor_index];
    const buffer_view = self.gltf.data.buffer_views[accessor.buffer_view.?];
    gl.BindBuffer(@intCast(@intFromEnum(buffer_view.target.?)), self.buffer_objects[accessor.buffer_view.?]);
    const size: gl.int = @intCast(accessor.type.componentCount());
    const typ: gl.uint = @intFromEnum(accessor.component_type);
    const normalized: u8 = @intFromBool(accessor.normalized);
    const byte_size: usize = accessor.type.componentCount() * accessor.component_type.byteSize();
    const stride: gl.sizei = @intCast(if (buffer_view.byte_stride) |byte_stride| byte_stride else byte_size);
    gl.EnableVertexAttribArray(@intCast(attrib_index));
    gl.VertexAttribPointer(@intCast(attrib_index), size, typ, normalized, stride, @intCast(accessor.byte_offset));
}

pub fn drawWithTransforms(self: *Model, si: ShaderInfo, model_mat: mat4, global_transforms: []const mat4) void {
    const data = &self.gltf.data;
    const nodes = data.nodes;

    for (nodes, 0..) |*node, node_i| {
        const mesh = &data.meshes[node.mesh orelse continue];

        if (node.skin) |skin_index| {
            const skin = data.skins[skin_index];
            const inverse_bind_matrices = self.getFloatBuffer(data.accessors[skin.inverse_bind_matrices.?]);
            var joints: [128]mat4 = undefined;
            for (skin.joints, 0..) |joint_index, i| {
                const inverse_bind_matrix = access(mat4, inverse_bind_matrices, i);
                joints[i] = la.mul(global_transforms[joint_index], inverse_bind_matrix);
            }
            gl.UniformMatrix4fv(si.joints_loc, @intCast(skin.joints.len), 0, @ptrCast(&joints));
            if (si.blend_skin_loc) |blend_skin| gl.Uniform1f(blend_skin, 1);
            gl.UniformMatrix4fv(si.model_loc, 1, 0, @ptrCast(&model_mat));
        } else {
            const model = la.mul(model_mat, global_transforms[node_i]);
            gl.UniformMatrix4fv(si.model_loc, 1, 0, @ptrCast(&model));
        }
        defer if (si.blend_skin_loc) |blend_skin| gl.Uniform1f(blend_skin, 0);

        for (mesh.primitives) |*primitive| {
            if (primitive.material) |material_index| {
                const material = data.materials[material_index];

                if (material.metallic_roughness.base_color_texture) |base_color| {
                    gl.BindTexture(gl.TEXTURE_2D, self.textures[base_color.index]);
                }
            }
            for (primitive.attributes) |attribute| {
                switch (attribute) {
                    .position => |accessor_index| self.bindVertexAttrib(accessor_index, 0),
                    .normal => |accessor_index| self.bindVertexAttrib(accessor_index, 1),
                    .texcoord => |accessor_index| self.bindVertexAttrib(accessor_index, 2),
                    .joints => |accessor_index| self.bindVertexAttrib(accessor_index, 3),
                    .weights => |accessor_index| self.bindVertexAttrib(accessor_index, 4),
                    else => {},
                }
            }
            defer for (primitive.attributes) |attribute| {
                switch (attribute) {
                    .position => gl.DisableVertexAttribArray(0),
                    .normal => gl.DisableVertexAttribArray(1),
                    .texcoord => gl.DisableVertexAttribArray(2),
                    .joints => gl.DisableVertexAttribArray(3),
                    .weights => gl.DisableVertexAttribArray(4),
                    else => {},
                }
            };
            const accessor_index = primitive.indices.?;
            const accessor = data.accessors[accessor_index];
            const buffer_view = data.buffer_views[accessor.buffer_view.?];
            gl.BindBuffer(@intCast(@intFromEnum(buffer_view.target.?)), self.buffer_objects[accessor.buffer_view.?]);

            gl.DrawElements(@intCast(@intFromEnum(primitive.mode)), @intCast(accessor.count), @intCast(@intFromEnum(accessor.component_type)), accessor.byte_offset);
        }
    }
}

pub fn draw(self: *Model, si: ShaderInfo, model_mat: mat4) void {
    const nodes = self.gltf.data.nodes;

    var local_transforms: [32]Transform = undefined;
    for (nodes, 0..) |*node, i| {
        local_transforms[i] = Transform.from_node(node);
    }

    var global_transforms: [32]mat4 = undefined;
    for (0..nodes.len) |i| {
        global_transforms[i] = local_transforms[i].to_mat4();
        // in gltf parents can appear after their children, so we can't do a linear scan
        var node = &nodes[i];
        while (node.parent) |parent_index| : (node = &nodes[parent_index]) {
            const parent_transform = local_transforms[parent_index].to_mat4();
            global_transforms[i] = la.mul(parent_transform, global_transforms[i]);
        }
    }

    self.drawWithTransforms(si, model_mat, &global_transforms);
}
