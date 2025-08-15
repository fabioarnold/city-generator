#version 410

uniform mat4 u_projection;
uniform mat4 u_view;

layout(location = 0) in vec3 a_position;

void main() {
    gl_Position = u_projection * u_view * vec4(a_position, 1.0);
}
