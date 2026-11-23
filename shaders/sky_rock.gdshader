shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform float black_moon = 0.0;
varying vec3 rock_position;
varying float grass_edge;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float noise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f*f*(3.0 - 2.0*f);
    float a = mix(hash(i), hash(i+vec3(1.0,0.0,0.0)), f.x);
    float b = mix(hash(i+vec3(0.0,1.0,0.0)), hash(i+vec3(1.0,1.0,0.0)), f.x);
    float c = mix(hash(i+vec3(0.0,0.0,1.0)), hash(i+vec3(1.0,0.0,1.0)), f.x);
    float d = mix(hash(i+vec3(0.0,1.0,1.0)), hash(i+vec3(1.0,1.0,1.0)), f.x);
    return mix(mix(a,b,f.y), mix(c,d,f.y), f.z);
}
void vertex() { rock_position = VERTEX; grass_edge = COLOR.r; }
void fragment() {
    float broad = noise(rock_position * 3.6);
    float cracks = noise(rock_position * 23.0);
    float bands = sin(rock_position.y * 22.0 + broad * 4.0) * 0.5 + 0.5;
    vec3 slate = mix(vec3(0.13,0.17,0.21), vec3(0.38,0.38,0.35), broad * 0.6 + bands * 0.4);
    slate += vec3(0.05,0.037,0.025) * (cracks - 0.48);
    float moss = smoothstep(0.20, 0.94, grass_edge) * (0.28 + 0.42 * broad);
    vec3 col = mix(slate, vec3(0.22,0.37,0.14), moss);
    float grey = dot(col, vec3(0.299, 0.587, 0.114));
    ALBEDO = mix(col, grey * vec3(0.42, 0.22, 0.45), black_moon * 0.78);
    ROUGHNESS = 1.0;
}
