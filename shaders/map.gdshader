shader_type canvas_item;
// Paradox-style province map.
// index_tex: province id per pixel (R + 256 * G). palette_tex row 0 = fill colour (alpha = strength),
// row 1 = owner key (R) used to draw thicker nation borders, row 2 = stripe colour (occupier or
// coloniser; alpha = 0 for none). id 0 = sea / open sky.

uniform sampler2D index_tex : filter_nearest;
uniform sampler2D terrain_tex : filter_linear;
uniform sampler2D palette_tex : filter_nearest;
uniform vec2 map_size = vec2(2000.0, 1092.0);
uniform int selected_id = -1;
uniform int hovered_id = -1;
uniform float border_width = 1.0;
uniform float doomsday = 0.0;
uniform float stripe_scale = 7.0;

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
	int id = id_at(UV);
	vec3 terr = texture(terrain_tex, UV).rgb;
	vec3 col = terr;
	int n0 = id_at(UV + vec2(t.x, 0.0));
	int n1 = id_at(UV - vec2(t.x, 0.0));
	int n2 = id_at(UV + vec2(0.0, t.y));
	int n3 = id_at(UV - vec2(0.0, t.y));
	bool edge = (n0 != id) || (n1 != id) || (n2 != id) || (n3 != id);

	if (id > 0) {
		vec4 fill = texelFetch(palette_tex, ivec2(id, 0), 0);
		float shade = 0.70 + 0.38 * terr.r;
		col = mix(terr, fill.rgb * shade, fill.a);
		vec4 stripe = texelFetch(palette_tex, ivec2(id, 2), 0);
		if (stripe.a > 0.0) {
			vec2 px = UV * map_size;
			if (fract((px.x + px.y) / stripe_scale) < 0.45) {
				col = mix(col, stripe.rgb * shade, stripe.a);
			}
		}
		if (edge) {
			float own = owner_of(id);
			bool nation_edge = abs(owner_of(n0) - own) > 0.001 || abs(owner_of(n1) - own) > 0.001
				|| abs(owner_of(n2) - own) > 0.001 || abs(owner_of(n3) - own) > 0.001;
			col *= nation_edge ? 0.30 : 0.72;
		}
		if (id == hovered_id) {
			col = mix(col, vec3(1.0), 0.16);
		}
		if (id == selected_id) {
			float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
			col = edge ? vec3(1.0, 0.96, 0.75) : mix(col, vec3(1.0, 0.97, 0.85), 0.22 + 0.10 * pulse);
		}
	} else if (edge) {
		col *= 0.55; // coastline
	}

	if (doomsday > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 night = vec3(0.30, 0.12, 0.42) * (0.4 + l);
		col = mix(col, night, 0.6 * doomsday);
	}
	COLOR = vec4(col, 1.0);
}
