#version 410

uniform mat4 u_projection;
uniform mat4 u_view;

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_texcoords;
layout(location = 3) in vec4 a_transform;

out vec3 v_normal;
out vec2 v_texcoords;

void main() {
    v_normal = a_normal;
    float rot = a_transform.w;
    vec3 pos = a_position / 8.0;
    if(rot == 1) {
        pos.xy = vec2(pos.y, 1 - pos.x);
    } else if(rot == 2) {
        pos.xy = vec2(1 - pos.x, 1 - pos.y);
    } else if(rot == 3) {
        pos.xy = vec2(1 - pos.y, pos.x);
    }
    pos += a_transform.xyz;
    v_texcoords = a_texcoords / vec2(64.0, 168.0);

    gl_Position = u_projection * u_view * vec4(pos, 1.0);
}
