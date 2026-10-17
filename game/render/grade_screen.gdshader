shader_type canvas_item;
// Same split-tone grade as grade.gdshader (violet shadows, warm highlights,
// purple vignette) but read from the screen behind this rect, so it can sit
// between the world and the UI in an ordinary scene tree.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.30, 0.62);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.92, 0.76);
uniform float shadow_amount = 0.55;
uniform float highlight_amount = 0.14;
uniform float vignette = 0.55;
uniform float saturation = 1.05;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 col = c;
	float sh = 1.0 - smoothstep(0.12, 0.62, l);
	col = mix(col, col * shadow_tint * 1.75, sh * shadow_amount);
	col = mix(col, col * highlight_tint * 1.04, smoothstep(0.55, 0.95, l) * highlight_amount);
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(g), col, saturation);
	vec2 d = (SCREEN_UV - vec2(0.5)) * vec2(1.0, 0.75);
	float v = smoothstep(0.26, 0.6, length(d));
	col = mix(col, col * shadow_tint * 1.3, v * vignette);
	COLOR = vec4(col, 1.0);
}
