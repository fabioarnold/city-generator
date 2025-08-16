#version 410

uniform mat4 u_projection;
uniform mat4 u_view;
uniform mat4 u_model;

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texcoords;

out vec2 v_texcoords;

void main() {
    v_texcoords = a_texcoords;
    gl_Position = u_projection * u_view * u_model * vec4(a_position, 0.0, 1.0);
}
