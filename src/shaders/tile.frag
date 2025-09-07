uniform vec3 u_light_dir;
uniform sampler2D u_colormap;

in vec3 v_normal;
in vec2 v_texcoords;

out vec4 out_color;

void main() {
    vec3 light_dir = normalize(u_light_dir);
    float light = 0.5 + 0.5 * dot(normalize(v_normal), light_dir);
    out_color = texture(u_colormap, v_texcoords);
    out_color.rgb *= light;
    if(out_color.a == 0.0)
        discard;
}
