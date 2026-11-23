shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;
uniform float black_moon = 0.0;
void fragment() {
    float glow = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.5);
    ALBEDO = mix(vec3(0.27, 0.60, 0.91), vec3(0.65, 0.08, 0.23), black_moon);
    ALPHA = glow * (0.30 + 0.19 * black_moon);
}
