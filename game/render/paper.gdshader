shader_type canvas_item;
// Paper: a flat cream base, fine grain, long soft fibres and a gentle vignette.
// Everything is computed from screen position, so it costs no textures.

uniform vec4 tint : source_color = vec4(0.96, 0.933, 0.875, 1.0);
uniform float grain = 1.0;
uniform float vignette = 0.22;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float g = hash(floor(px)) - 0.5;
	float blotch = vnoise(px / 140.0) * 0.6 + vnoise(px / 37.0) * 0.4 - 0.5;
	float fibre = vnoise(vec2(px.x / 260.0, px.y / 7.0)) - 0.5;
	vec3 col = tint.rgb;
	col += g * 0.035 * grain;
	col += blotch * 0.05 * grain;
	col += fibre * 0.018 * grain;
	vec2 uv = SCREEN_UV - 0.5;
	float v = 1.0 - dot(uv, uv) * vignette * 2.2;
	col *= v;
	COLOR = vec4(col, tint.a);
}
