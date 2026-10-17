shader_type canvas_item;
// Colour grade for the world layer (applied per pixel, no blur, so pixel art stays crisp).
// Split toning from colour theory: the world is dominated by yellow-green grass and teal
// water, so shadows are pushed toward its complement (violet/purple) and highlights toward
// warm gold. A purple vignette frames the view. UI is not graded.
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.30, 0.62);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.92, 0.76);
uniform float shadow_amount = 0.6;
uniform float highlight_amount = 0.16;
uniform float vignette = 0.7;
uniform float saturation = 1.06;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = c.rgb;
	float sh = 1.0 - smoothstep(0.12, 0.62, l);
	col = mix(col, col * shadow_tint * 1.75, sh * shadow_amount);
	col = mix(col, col * highlight_tint * 1.04, smoothstep(0.55, 0.95, l) * highlight_amount);
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(g), col, saturation);
	vec2 d = (UV - vec2(0.5)) * vec2(1.0, 0.75);
	float v = smoothstep(0.26, 0.6, length(d));
	col = mix(col, col * shadow_tint * 1.3, v * vignette);
	COLOR = vec4(col, c.a);
}
