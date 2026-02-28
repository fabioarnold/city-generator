uniform vec2 u_resolution;
uniform mat4 u_view;

in vec2 v_uv;

out vec4 out_color;

void main() {
    // 1. Normalized Device Coordinates (-1 to 1)
    vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / u_resolution.y;

    // 2. Setup Camera Ray
    // Extract camera vectors from the view matrix
    vec3 camRight = vec3(u_view[0][0], u_view[1][0], u_view[2][0]);
    vec3 camUp    = vec3(u_view[0][1], u_view[1][1], u_view[2][1]);
    vec3 camForward = -vec3(u_view[0][2], u_view[1][2], u_view[2][2]);
    vec3 camPos   = vec3(u_view[3][0], u_view[3][1], u_view[3][2]);

    vec3 rayDir = normalize(camForward + uv.x * camRight + uv.y * camUp);

    // 3. Ground Plane Intersection (y = -1.0 for the floor)
    float floorHeight = -1.0;
    float t = (floorHeight - camPos.y) / rayDir.y;

    vec3 color;

    if (t > 0.0 && rayDir.y < 0.0) {
        // --- GROUND ---
        vec3 hitPos = camPos + rayDir * t;
        float dist = length(hitPos.xz - camPos.xz);
        
        // Base green color
        vec3 groundColor = vec3(0.2, 0.5, 0.2);
        
        // Z-Distance Vignette (fades to horizon color)
        float fog = smoothstep(0.0, 50.0, dist);
        vec3 skyBlue = vec3(0.5, 0.7, 1.0);
        
        color = mix(groundColor, skyBlue, fog);
    } else {
        // --- SKY / HORIZON ---
        vec3 skyBlue = vec3(0.5, 0.7, 1.0);
        vec3 deepBlue = vec3(0.1, 0.3, 0.8);
        
        // Gradient based on ray height
        float horizonFade = smoothstep(-0.2, 0.5, rayDir.y);
        color = mix(skyBlue, deepBlue, horizonFade);
    }

    out_color = vec4(color, 1.0);
}
