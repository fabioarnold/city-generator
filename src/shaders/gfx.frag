uniform sampler2D u_colormap;
uniform vec4 u_color;

uniform bool u_colormap_enabled;

in vec2 v_texcoords;

out vec4 out_color;

void main() {
    out_color = u_color;
    if (u_colormap_enabled) out_color *= texture(u_colormap, v_texcoords);
    if (out_color.a == 0.0)
        discard;
}
