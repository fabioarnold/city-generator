uniform sampler2D u_ssao;
uniform sampler2D u_depthmap;
uniform vec2 u_pixel;

in vec2 v_uv;
out vec4 out_ao;

void main() {
    float center_depth = texture(u_depthmap, v_uv).r;
    float result       = 0.0;
    float total_weight = 0.0;

    // 5×5 bilateral blur: samples are weighted by depth similarity so AO
    // does not bleed across depth discontinuities (building edges, etc.).
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2 offset_uv   = v_uv + vec2(float(x), float(y)) * u_pixel;
            float sample_depth = texture(u_depthmap, offset_uv).r;

            // Gaussian falloff in depth space: weight drops sharply when a
            // neighbouring sample lives on a different surface.
            float depth_delta = abs(center_depth - sample_depth);
            float weight      = exp(-depth_delta * 1000.0);

            result       += texture(u_ssao, offset_uv).r * weight;
            total_weight += weight;
        }
    }

    float ao = result / max(total_weight, 0.001);
    out_ao = vec4(ao, ao, ao, 1.0);
}
