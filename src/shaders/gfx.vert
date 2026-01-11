uniform mat4 u_projection;
uniform mat4 u_view;
uniform mat4 u_model;
uniform mat3 u_gradient_xform;

uniform vec4 u_src_rect;
uniform int u_colormap_type;

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texcoords;

out vec2 v_position;
out vec2 v_gradient;
out vec2 v_texcoords;

void main() {
    v_position = a_position;
    v_gradient = (u_gradient_xform * vec3(a_position, 1.)).xy;
    if (u_colormap_type == 1) {
        v_texcoords = (a_position - u_src_rect.xy) / u_src_rect.zw;
    } else if (u_colormap_type == 2) {
        v_texcoords = a_texcoords;
    }
    gl_Position = u_projection * u_view * u_model * vec4(a_position, 0.0, 1.0);
}
