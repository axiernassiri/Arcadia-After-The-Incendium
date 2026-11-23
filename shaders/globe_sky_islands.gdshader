shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D terrain_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D index_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform float colour_strength = 0.0;
uniform float black_moon = 0.0;
uniform int selected_id = -1;
uniform int hovered_id = -1;
varying vec3 land_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0,0.0)), f.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), f.x), f.y);
}
void vertex() { land_position = VERTEX; }
void fragment() {
    // Thick meadow cover, mottled soil patches, moss and fine grass texture.
    float large = noise(land_position.xz * 3.7);
    float medium = noise(land_position.xz * 16.0);
    float small = noise(land_position.xz * 64.0);
    vec3 grass = mix(vec3(0.16, 0.31, 0.12), vec3(0.43, 0.60, 0.20), large * 0.55 + medium * 0.45);
    grass += vec3(0.070, 0.073, 0.011) * (small - 0.5);
    float soil = smoothstep(0.65, 0.85, large * 0.68 + medium * 0.32);
    vec3 col = mix(grass, vec3(0.46, 0.39, 0.26), soil * 0.52);
    // Tiny flowering meadow clusters and limestone flecks break up the atlas look.
    float flower = step(0.977, hash(floor(land_position.xz * 37.0)));
    float meadow = smoothstep(0.30, 0.61, large) * (1.0 - soil);
    col = mix(col, vec3(0.95, 0.92, 0.68), flower * meadow * 0.75);
    vec3 src = texture(terrain_tex, UV).rgb;
    float brightness = dot(src, vec3(0.299, 0.587, 0.114));
    col = mix(col, col * vec3(1.15, 1.18, 0.95), smoothstep(0.78, 0.98, brightness) * 0.23);

    // Keep 3D political map modes, selection and mouse-over working.
    vec3 index_color = texture(index_tex, UV).rgb;
    int id = int(round(index_color.r * 255.0)) + 256 * int(round(index_color.g * 255.0));
    if (id > 0 && colour_strength > 0.0) {
        vec4 palette = texture(palette_tex, vec2((float(id) + 0.5) / 1024.0, 1.0 / 6.0));
        col = mix(col, palette.rgb * (0.75 + 0.26 * medium), palette.a * colour_strength);
    }
    if (id == hovered_id) { col = mix(col, vec3(1.0, 0.88, 0.55), 0.32); }
    if (id == selected_id) { col = mix(col, vec3(1.0, 0.82, 0.37), 0.35 + 0.06 * sin(TIME * 4.0)); }

    float grey = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, grey * vec3(0.36, 0.23, 0.43), black_moon * 0.78);
    ALBEDO = col;
    ROUGHNESS = 0.97;
    METALLIC = 0.0;
}
