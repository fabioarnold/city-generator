uniform mat4 u_view;
uniform float u_fov;
uniform vec2 u_resolution;
uniform vec3 u_sun_pos;
uniform sampler2D u_grass_tex;

in vec2 v_uv;

layout(location=0) out vec4 out_color;
layout(location=1) out vec4 out_normal;

void main() {
    // 1. Setup Camera Ray
    // gl_FragCoord.xy is in window coordinates (0,0 to width,height)
    vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / u_resolution.y;

    float fov_rad = radians(u_fov);
    float tan_half_fov = tan(fov_rad * 0.5);
    vec3 view_dir = normalize(vec3(uv.x * tan_half_fov, uv.y * tan_half_fov, -1.0));

    mat3 view_rot = mat3(u_view);
    mat3 view_rot_inv = transpose(view_rot);
    vec3 ray_dir = normalize(view_rot_inv * view_dir);
    vec3 cam_pos = -view_rot_inv * u_view[3].xyz;

    float floor_height = 0.0;
    float t_bot = (floor_height - cam_pos.z) / ray_dir.z;

    vec3 color;
    vec3 normal = vec3(0.0, 0.0, 1.0); // Default normal is UP for lighting

    // Colors
    vec3 sky_base = vec3(0.6, 0.8, 1.0); // light blue
    vec3 sky_top = vec3(0.2, 0.45, 0.85); // deep blue
    vec3 sun_color = vec3(1.0, 0.95, 0.7);
    vec3 grass_dark = vec3(0.05, 0.25, 0.05); 
    vec3 grass_light = vec3(0.3, 0.6, 0.1);

    vec3 sun_dir = normalize(u_sun_pos);

    if (t_bot > 0.0 && ray_dir.z < 0.0) {
        // --- GROUND ---
        vec3 hit_pos = cam_pos + ray_dir * t_bot;
        
        // Sample grass texture
        color = texture(u_grass_tex, hit_pos.xy * 0.5).rgb;
        
        float dist = length(hit_pos.xy - cam_pos.xy);
        
        // Atmospheric gradient fog based on distance
        float fog_factor = smoothstep(40.0, 150.0, dist);
        // Match the fog color to the horizon sky color
        color = mix(color, sky_base, fog_factor);
        
        // Output normals for ground
        normal = vec3(0.0, 0.0, 1.0); // UP is +Z
    } else {
        // --- SKY / HORIZON ---
        float horizon_fade = smoothstep(0.0, 0.5, ray_dir.z);
        color = mix(sky_base, sky_top, horizon_fade);
        
        // Sun
        float sun_dot = dot(ray_dir, sun_dir);
        float sun_mask = step(0.998, sun_dot); 
        float sun_glow = smoothstep(0.98, 0.998, sun_dot);
        color = mix(color, sun_color, sun_glow * 0.4); // Glow
        color = mix(color, sun_color, sun_mask); // Core
        
        normal = vec3(0.0, 0.0, 1.0);
    }
    
    out_color = vec4(color, 1.0);
    out_normal = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
}
