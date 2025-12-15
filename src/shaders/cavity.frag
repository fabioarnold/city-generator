uniform sampler2D u_colormap;
uniform sampler2D u_normalmap;
uniform sampler2D u_depthmap;

uniform vec2 u_pixel;

in vec2 v_uv;
out vec4 out_color;

vec3 normal_decode(vec4 encoded) {
    return 2.0 * encoded.rgb - 1.0;
}

float soft_clamp(float curvature, float control) {
    if (curvature < 0.5 / control) {
        return curvature * (1.0 - curvature * control);
    }
    return 0.25 / control;
}

void main() {
    //float depth = texture(u_depthmap, v_uv).x;
    //vec3 position = u_invprojection * vec4(v_uv, depth, 1.0);
    //vec3 normal = 2.0 * texture(u_normalmap, v_uv).xyz - 1.0;

    vec3 offset = vec3(u_pixel, 0.0);
    float normal_u = normal_decode(texture(u_normalmap, v_uv + offset.zy)).y;
    float normal_d = normal_decode(texture(u_normalmap, v_uv - offset.zy)).y;
    float normal_r = normal_decode(texture(u_normalmap, v_uv + offset.xz)).x;
    float normal_l = normal_decode(texture(u_normalmap, v_uv - offset.xz)).x;
    float normal_diff = (normal_u - normal_d) + (normal_r - normal_l);

    float curvature = 0.0;
    if(normal_diff < 0.0) {
        // valley
        curvature = -2.0 * soft_clamp(-normal_diff, 1.0);
    } else {
        // ridge
        curvature = 2.0 * soft_clamp(normal_diff, 1.0);
    }

    out_color = texture(u_colormap, v_uv);
    out_color.rgb += 0.25 * curvature;

    // out_color.rgb = texture(u_normalmap, v_uv).rgb;
}
