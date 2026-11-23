shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform float black_moon = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
    vec2 p = UV * 33.0;
    float rolls = sin(p.x * 0.51 + TIME * 0.012) * cos(p.y * 0.53 - TIME * 0.009);
    float smaller = sin(p.x * 1.2 + p.y * 0.33) * cos(p.y * 1.5);
    VERTEX.y += 0.28 * rolls + 0.075 * smaller;
}
void fragment() {
    vec2 p = UV * 27.0 + vec2(TIME * 0.0018, -TIME * 0.0011);
    float n = 0.55 * noise(p) + 0.29 * noise(p * 2.13) + 0.16 * noise(p * 4.31);
    float broad = noise(p * 0.39);
    float gleam = smoothstep(0.36, 0.79, n * 0.80 + broad * 0.20);
    vec3 golden_shade = vec3(0.83, 0.80, 0.67);
    vec3 sunlit_cream = vec3(0.995, 0.987, 0.943);
    vec3 colour = mix(golden_shade, sunlit_cream, gleam);
    colour += vec3(0.023, 0.016, 0.002) * broad;
    ALBEDO = mix(colour, vec3(0.18, 0.08, 0.18), black_moon * 0.87);
}
