shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Compute globe texture coordinates from the normalized sphere direction per pixel,
// not from UVs interpolated across polar triangles. This removes the pole pinch.
uniform sampler2D terrain_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D index_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform float black_moon = 0.0;
uniform float colour_strength = 0.52;
uniform int selected_id = -1;
uniform int hovered_id = -1;
uniform float polar_padding = 0.11;
varying vec3 sphere_direction;

void vertex() {
    sphere_direction = normalize(VERTEX);
}

void fragment() {
    vec3 dir = normalize(sphere_direction);
    float longitude = atan(dir.x, dir.z);
    float globe_v = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / PI;
    // A short fade hides the abrupt land edges in the source's polar rows.
    float polar_cap = max(polar_padding, 0.001);
    float source_v = (globe_v - polar_cap) / (1.0 - 2.0 * polar_cap);
    vec2 map_uv = vec2(fract(longitude / TAU + 0.5), clamp(source_v, 0.0, 1.0));
    float land_alpha = smoothstep(polar_cap, polar_cap + 0.027, globe_v)
        * (1.0 - smoothstep(1.0 - polar_cap - 0.027, 1.0 - polar_cap, globe_v));

    // The source map has unconnected northern/southern edges, so cap with an
    // ocean pixel instead of stretching arbitrary land around both poles.
    vec3 ocean = texture(terrain_tex, vec2(0.50, 0.08)).rgb;
    vec3 base = mix(ocean, texture(terrain_tex, map_uv).rgb, land_alpha);
    vec3 code = texture(index_tex, map_uv).rgb;
    int id = int(round(code.r * 255.0)) + 256 * int(round(code.g * 255.0));
    vec3 col = base;
    if (id > 0 && land_alpha > 0.01) {
        vec4 palette = texture(palette_tex, vec2((float(id) + 0.5) / 1024.0, 1.0 / 6.0));
        vec3 painted = mix(base, palette.rgb * (0.68 + 0.34 * base.r), palette.a * colour_strength);
        col = mix(base, painted, land_alpha);
        if (id == hovered_id) { col = mix(col, vec3(1.0, 0.91, 0.65), 0.25 * land_alpha); }
        if (id == selected_id) { col = mix(col, vec3(1.0, 0.88, 0.45), (0.33 + 0.08 * sin(TIME * 4.0)) * land_alpha); }
    }
    float scar = sin(map_uv.x * 73.0 + sin(map_uv.y * 51.0 + TIME * 0.5) * 2.0)
        * sin(map_uv.y * 67.0 - map_uv.x * 23.0 + TIME * 0.35);
    float vein = smoothstep(0.92, 0.99, scar) * (0.5 + 0.5 * sin(TIME * 3.2));
    float grey = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, grey * vec3(0.35, 0.23, 0.43), 0.78 * black_moon);
    col = mix(col, vec3(0.75, 0.025, 0.09), vein * black_moon * 0.94);
    ALBEDO = col;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    // A per-pixel rim replaces the former transparent shell (which made a seam).
    float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 4.0);
    vec3 rim_tint = mix(vec3(0.018, 0.040, 0.080), vec3(0.15, 0.012, 0.03), black_moon);
    EMISSION = rim * rim_tint + black_moon * vein * vec3(0.34, 0.01, 0.05);
}
