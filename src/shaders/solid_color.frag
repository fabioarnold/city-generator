uniform vec4 u_color;
in vec3 v_normal;

layout(location=0) out vec4 out_color;
layout(location=1) out vec4 out_normal;

void main() {
    out_color = u_color;
    out_normal = vec4(0.5 + 0.5 * normalize(v_normal), 1.0);
    if (out_color.a == 0.0)
        discard;
}
