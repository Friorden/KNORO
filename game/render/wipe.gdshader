shader_type canvas_item;
// Ink-blot screen transition. progress 0 = clear, 1 = fully covered.
// The edge is ragged (value noise) so it reads like ink soaking into paper.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 ink : source_color = vec4(0.184, 0.165, 0.208, 1.0);
uniform vec2 aspect = vec2(1.777, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = (UV - center) * aspect;
	float d = length(uv);
	float ang = atan(uv.y, uv.x);
	float edge = vnoise(vec2(ang * 3.0, progress * 4.0)) * 0.18 + vnoise(uv * 9.0) * 0.06;
	float r = progress * 2.4 - 0.2;
	float a = smoothstep(r + 0.01, r - 0.01, d + edge);
	COLOR = vec4(ink.rgb, ink.a * a);
}
