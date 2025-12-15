uniform mat4 u_projection;
uniform mat4 u_view;
uniform mat4 u_model;

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_texcoords;

out vec3 v_normal;
out vec2 v_texcoords;

void main() {
    mat4 viewmodel = u_view * u_model;
    v_normal = (viewmodel * vec4(a_normal, 0.0)).xyz;
    v_texcoords = a_texcoords;
    gl_Position = u_projection * u_view * u_model * vec4(a_position, 1.0);
}
