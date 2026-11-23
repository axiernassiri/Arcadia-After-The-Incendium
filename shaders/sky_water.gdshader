shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float black_moon = 0.0;
void fragment() {
    float edge = smoothstep(0.0, 0.20, UV.x) * (1.0 - smoothstep(0.80, 1.0, UV.x));
    float stream = 0.60 + 0.40 * sin(UV.x * 25.0 + UV.y * 38.0 + TIME * 5.0);
    float foam = 0.5 + 0.5 * sin(UV.y * 65.0 - TIME * 5.0);
    vec3 col = mix(vec3(0.32, 0.68, 0.87), vec3(0.87, 0.96, 1.0), stream * 0.55 + foam * 0.25);
    ALBEDO = mix(col, vec3(0.56, 0.05, 0.15), black_moon * 0.8);
    ALPHA = edge * (0.62 + 0.30 * foam) * (1.0 - smoothstep(0.74, 1.0, UV.y) * 0.45);
}
