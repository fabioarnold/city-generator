uniform sampler2D u_normalmap;
uniform sampler2D u_depthmap;
uniform sampler2D u_noise;

uniform mat4 u_projection;
uniform mat4 u_proj_inv;
uniform vec2 u_noise_scale;
uniform float u_radius;
uniform float u_bias;
uniform vec3 u_samples[64];

in vec2 v_uv;
out vec4 out_ao;

const int NUM_SAMPLES = 64;

// Reconstructs view-space position from screen UV and raw depth buffer value.
// Uses reverse-Z infinite perspective: depth in [0.5,1] for geometry, 0 for sky.
vec3 reconstruct_position(vec2 uv, float depth) {
    vec4 clip = vec4(2.0 * uv - 1.0, 2.0 * depth - 1.0, 1.0);
    vec4 view_h = u_proj_inv * clip;
    return view_h.xyz / view_h.w;
}

void main() {
    float depth = texture(u_depthmap, v_uv).r;

    // Sky and empty regions have depth 0 (reverse-Z clear value) — no occlusion.
    if (depth < 0.5) {
        out_ao = vec4(1.0);
        return;
    }

    vec3 pos    = reconstruct_position(v_uv, depth);
    vec3 normal = normalize(2.0 * texture(u_normalmap, v_uv).rgb - 1.0);

    // Build a random TBN basis using a tiled 4×4 noise texture so that each
    // pixel gets a different hemisphere orientation, breaking banding patterns.
    vec2 noise_xy   = texture(u_noise, v_uv * u_noise_scale).rg * 2.0 - 1.0;
    vec3 random_vec = normalize(vec3(noise_xy, 0.0));
    vec3 tangent    = normalize(random_vec - normal * dot(random_vec, normal));
    vec3 bitangent  = cross(normal, tangent);
    mat3 TBN        = mat3(tangent, bitangent, normal);

    float occlusion = 0.0;
    for (int i = 0; i < NUM_SAMPLES; i++) {
        // Transform hemisphere sample from tangent space to view space.
        vec3 sample_vs = pos + TBN * (u_samples[i] * u_radius);

        // Project the sample position back to screen space.
        vec4 clip_s     = u_projection * vec4(sample_vs, 1.0);
        vec2 sample_uv  = 0.5 * clip_s.xy / clip_s.w + 0.5;

        float sample_depth = texture(u_depthmap, sample_uv).r;
        if (sample_depth < 0.5) continue;

        vec3 actual_pos = reconstruct_position(sample_uv, sample_depth);

        // Fade occlusion contribution for samples whose surfaces are far from
        // the shaded point in depth, preventing halos from unrelated geometry.
        float range_check = smoothstep(0.0, 1.0, u_radius / abs(pos.z - actual_pos.z));

        // Camera looks along −Z so view-space z is negative; a surface with
        // a higher (less negative) z is closer to the camera and occludes.
        occlusion += (actual_pos.z >= sample_vs.z + u_bias ? 1.0 : 0.0) * range_check;
    }

    float ao = 1.0 - (occlusion / float(NUM_SAMPLES));
    out_ao = vec4(ao, ao, ao, 1.0);
}
