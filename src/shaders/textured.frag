#version 410

uniform sampler2D u_colormap;

in vec2 v_texcoords;

out vec4 out_color;

void main() {
    out_color = texture(u_colormap, v_texcoords);
    if(out_color.a == 0)
        discard;
}
