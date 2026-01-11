uniform vec4 u_color;
uniform sampler2D u_colormap;
uniform int u_colormap_type;

#define GRADIENT_COUNT_MAX 4
uniform vec4 u_gradient_colors[GRADIENT_COUNT_MAX];
uniform float u_gradient_stops[GRADIENT_COUNT_MAX];
uniform int u_gradient_count;
uniform vec2 u_gradient_extents;
uniform float u_gradient_radius;
uniform float u_gradient_feather;
uniform bool u_gradient_smooth;

#define COLORMAP_TYPE_RGBA 1
#define COLORMAP_TYPE_ALPHA 2

in vec2 v_position;
in vec2 v_gradient;
in vec2 v_texcoords;

out vec4 out_color;

float sdroundrect(vec2 pt, vec2 ext, float rad) {
    vec2 ext2 = ext - vec2(rad,rad);
    vec2 d = abs(pt) - ext2;
    return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rad;
}

void main() {
    out_color = u_color;

    if (u_gradient_count >= 2) {
        float d = clamp(sdroundrect(
            v_gradient,
            u_gradient_extents,
            u_gradient_radius
        ) / u_gradient_feather + 0.5, 0., 1.);
        vec4 gradient_color = u_gradient_colors[0];
        if (u_gradient_smooth) {
            for (int i = 0; i < u_gradient_count-1; i++) {
                if (d >= u_gradient_stops[i] && d <= u_gradient_stops[i+1]) {
                    float alpha = (d - u_gradient_stops[i]) / (u_gradient_stops[i+1] - u_gradient_stops[i]);
                    gradient_color = mix(u_gradient_colors[i], u_gradient_colors[i+1], smoothstep(0.0, 1.0, alpha));
                }
            }
        } else {
            for (int i = 0; i < u_gradient_count-1; i++) {
                if (d >= u_gradient_stops[i] && d <= u_gradient_stops[i+1]) {
                    float alpha = (d - u_gradient_stops[i]) / (u_gradient_stops[i+1] - u_gradient_stops[i]);
                    gradient_color = mix(u_gradient_colors[i], u_gradient_colors[i+1], alpha);
                }
            }
        }
        out_color *= gradient_color;
    }

    if (u_colormap_type == COLORMAP_TYPE_RGBA) {
        out_color *= texture(u_colormap, v_texcoords);
    } else if (u_colormap_type == COLORMAP_TYPE_ALPHA) {
        out_color.a *= texture(u_colormap, v_texcoords).r;
    }

    out_color.rgb *= out_color.a; // premultiplied alpha

    if (out_color.a == 0.0)
        discard;
}
