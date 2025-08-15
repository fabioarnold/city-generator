#version 410

uniform sampler2D colormap;

in vec2 v_texcoord;

out vec4 out_color;

void main() {
    out_color = texture(colormap, v_texcoord);
    if(out_color.a == 0)
        discard;
}
