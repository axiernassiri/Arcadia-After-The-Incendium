shader_type spatial;
render_mode unshaded, cull_front;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0,0.0)), f.x), mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), f.x), f.y);
}
void fragment(){
    vec2 uv = UV;
    vec2 cell = fract(uv * vec2(140.0, 70.0));
    vec2 grid = floor(uv * vec2(140.0, 70.0));
    float rnd = hash(grid);
    float star = step(0.995, rnd) * smoothstep(0.22, 0.0, length(cell - 0.5));
    float star2 = step(0.9985, hash(grid + 17.3)) * smoothstep(0.30, 0.0, length(cell - vec2(0.35, 0.62)));
    float nebula = pow(noise(uv * 6.0 + vec2(TIME * 0.002, 0.0)), 2.5);
    vec3 bg = vec3(0.01, 0.02, 0.06);
    bg += vec3(0.04, 0.03, 0.10) * nebula;
    vec3 col = bg + vec3(0.9, 0.95, 1.0) * (star + 0.8 * star2);
    ALBEDO = col;
}
