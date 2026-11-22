shader_type canvas_item;
// Paradox-style province map.
// index_tex: province id per pixel (R + 256 * G). palette_tex row 0 = fill colour (alpha = strength),
// row 1 = owner key (R) used to draw thicker nation borders, row 2 = stripe colour (occupier or
// coloniser; alpha = 0 for none). id 0 = sea / open sky.

uniform sampler2D index_tex : filter_nearest, repeat_enable;   // repeat: the world loops east-west
uniform sampler2D terrain_tex : filter_linear, repeat_enable;
uniform sampler2D palette_tex : filter_nearest;
uniform vec2 map_size = vec2(2000.0, 1092.0);
uniform int selected_id = -1;
uniform int hovered_id = -1;
uniform float border_width = 1.0;
uniform float doomsday = 0.0;
uniform float corruption = 0.0;   // 0..1 as the Eschaton nears: glitching bands, red veins, drained colour
uniform float stripe_scale = 7.0;
uniform float zoom = 1.0;
uniform sampler2D paper_tex : repeat_enable, filter_linear_mipmap;
uniform float paper_strength = 0.10;

int id_at(vec2 uv) {
	vec4 c = texture(index_tex, uv);
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
}

float owner_of(int id) {
	if (id <= 0) {
		return -1.0;
	}
	return texelFetch(palette_tex, ivec2(id, 1), 0).r;
}

void fragment() {
	vec2 t = border_width / map_size;
	// the Eschaton nears: thin horizontal bands of the map slip sideways, flickering
	vec2 uv = UV;
	if (corruption > 0.0) {
		float band = floor(UV.y * 140.0) + floor(TIME * 7.0) * 13.0;
		float r = fract(sin(band * 12.9898) * 43758.5453);
		uv.x += (r - 0.5) * 0.006 * corruption * step(0.93 - 0.08 * corruption, r);
	}
	int id = id_at(uv);
	vec3 terr = texture(terrain_tex, uv).rgb;
	vec3 col = terr;
	int n0 = id_at(uv + vec2(t.x, 0.0));
	int n1 = id_at(uv - vec2(t.x, 0.0));
	int n2 = id_at(uv + vec2(0.0, t.y));
	int n3 = id_at(uv - vec2(0.0, t.y));
	bool edge = (n0 != id) || (n1 != id) || (n2 != id) || (n3 != id);
	vec2 px_pos = uv * map_size;
	float paper = texture(paper_tex, px_pos / 384.0).r;

	if (id > 0) {
		vec4 fill = texelFetch(palette_tex, ivec2(id, 0), 0);
		float shade = 0.70 + 0.38 * terr.r;
		col = mix(terr, fill.rgb * shade, fill.a);
		vec4 stripe = texelFetch(palette_tex, ivec2(id, 2), 0);
		if (stripe.a > 0.0) {
			vec2 px = uv * map_size;
			if (fract((px.x + px.y) / stripe_scale) < 0.45) {
				col = mix(col, stripe.rgb * shade, stripe.a);
			}
		}
		// nation borders are drawn twice as wide as province borders, and darker
		float own = owner_of(id);
		vec2 t2 = t * 2.0;
		bool nation_edge = abs(owner_of(id_at(uv + vec2(t2.x, 0.0))) - own) > 0.001 || abs(owner_of(id_at(uv - vec2(t2.x, 0.0))) - own) > 0.001
			|| abs(owner_of(id_at(uv + vec2(0.0, t2.y))) - own) > 0.001 || abs(owner_of(id_at(uv - vec2(0.0, t2.y))) - own) > 0.001;
		col *= mix(1.0 - paper_strength, 1.0 + paper_strength * 0.6, paper);
		if (nation_edge) {
			col *= 0.34;
		} else if (edge) {
			col *= mix(0.72, 0.82, clamp((1.6 - zoom) / 1.2, 0.0, 1.0)); // province borders soften when zoomed out
		}
		if (id == hovered_id) {
			col = mix(col, vec3(1.0), 0.16);
		}
		if (id == selected_id) {
			float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
			col = edge ? vec3(1.0, 0.96, 0.75) : mix(col, vec3(1.0, 0.97, 0.85), 0.22 + 0.10 * pulse);
		}
	} else {
		// open water / open sky: grain plus a slow shimmer
		float wave = texture(paper_tex, px_pos / 520.0 + vec2(TIME * 0.004, TIME * 0.0025)).r;
		col *= mix(0.93, 1.05, wave * 0.6 + paper * 0.4);
		if (edge) {
			col *= 0.55; // coastline
		}
	}

	if (doomsday > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 night = vec3(0.30, 0.12, 0.42) * (0.4 + l);
		col = mix(col, night, 0.6 * doomsday);
	}
	if (corruption > 0.0) {
		// colour drains toward a bruised grey-red, and red veins crawl slowly across land and sea
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(l) * vec3(0.85, 0.55, 0.55), 0.55 * corruption);
		float v = texture(paper_tex, px_pos / 260.0 + vec2(TIME * 0.006, -TIME * 0.004)).r;
		float vein = smoothstep(0.60, 0.64, v) * (1.0 - smoothstep(0.64, 0.69, v));
		col = mix(col, vec3(0.62, 0.02, 0.05), vein * corruption * 0.85);
		// and the far edges of the world darken
		vec2 d = uv - 0.5;
		col *= 1.0 - corruption * 0.55 * smoothstep(0.25, 0.75, length(d * vec2(1.0, 1.6)));
	}
	COLOR = vec4(col, 1.0);
}
