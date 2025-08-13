import bpy
import bmesh
import math
import mathutils

depsgraph = bpy.context.evaluated_depsgraph_get()

out_zig = bpy.path.abspath("//../src/tiles/tile_data.zig")

tex_w = 64
tex_h = 168

def clean_zero(f):
    return 0.0 if f == 0.0 else f

with open(out_zig, "w") as file:
    file.write("const Mesh = @import(\"../mesh.zig\").Mesh;\n\n")

    file.write("pub const tiles: []const Mesh = &.{\n")
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        mesh = ob.data
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        bm.edges.ensure_lookup_table()
        bm.faces.ensure_lookup_table()

        # Marked edges for splitting
        #sharp_edges = [e for e in bm.edges if not e.smooth]
        #bmesh.ops.split_edges(bm, edges=sharp_edges)
        bmesh.ops.split_edges(bm, edges=bm.edges)

        bmesh.ops.triangulate(bm, faces=bm.faces)

        vertex_dict = {}  # Dictionary to store unique vertices and indices
        indices = []
        file.write("    .{\n")
        file.write("        .vertex_data = &[_]f32{\n")
        for face in bm.faces:
            for loop in face.loops:
                vert = loop.vert
                uv_layer = bm.loops.layers.uv.active
                uv = loop[uv_layer].uv if uv_layer else (0.0, 0.0)
                key = (vert.co.x, vert.co.y, vert.co.z, vert.normal.x, vert.normal.y, vert.normal.z, uv.x, uv.y)

                if key not in vertex_dict:
                    vertex_dict[key] = len(vertex_dict)
                    file.write("            ")
                    file.write("%g, %g, %g, " % (vert.co[0]*8, vert.co[1]*8, vert.co[2]*8))
                    file.write("%g, %g, %g, " % vert.normal[:])
                    file.write("%g, %g,\n" % (clean_zero(uv.x * tex_w), clean_zero(tex_h - uv.y * tex_h)))

                indices.append(vertex_dict[key])
        file.write("        },\n")
        print(len(indices))
        file.write("        .index_data = &[_]u16{\n")
        for i in range(0, len(indices), 3):
            file.write(f"            {indices[i]}, {indices[i+1]}, {indices[i+2]},\n")
        file.write("        },\n")
        file.write("    },\n")

        bm.free()
    file.write("};\n")
