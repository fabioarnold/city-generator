uniform sampler2D u_colormap;
uniform sampler2D u_normalmap;
uniform sampler2D u_depthmap;

in vec2 v_uv;
out vec4 out_color;

void main() {
    out_color = texture(u_colormap, v_uv);
    out_color += vec4(texture(u_normalmap, v_uv).rgb, 1.0);
    out_color.rgb *= (texture(u_depthmap, v_uv).r - 0.5) * 10.;
}
