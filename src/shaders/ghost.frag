uniform sampler2D u_colormap;
uniform vec4 u_tint;

in vec3 v_normal;
in vec2 v_texcoords;

layout(location=0) out vec4 out_color;
layout(location=1) out vec4 out_normal;

void main() {
    vec4 tex = texture(u_colormap, v_texcoords);
    out_color = vec4(tex.rgb * u_tint.rgb, tex.a * u_tint.a);
    out_normal = vec4(0.5 + 0.5 * normalize(v_normal), 1.0);
    if (out_color.a == 0.0)
        discard;
}
