shader_type canvas_item;
// Two layers of the web main menu, in the same order as the reference:
//   1. the composer vignette (renderer `vignette`, offset 0.4 / darkness 0.4)
//   2. `.mm:before` (main CSS): a left gradient #140e32 99->4d->00 and a bottom
//      gradient #140e32 00 (82%) -> 59 (100%).
// Both are tinted #140e32 and live below the menu content.
uniform vec4 u_tint : source_color = vec4(0.078, 0.055, 0.196, 1.0);
uniform float u_left_a = 0.6;
uniform float u_mid_a = 0.302;
uniform float u_bottom_a = 0.349;
uniform float u_vignette_a = 0.4;

void fragment() {
	vec2 uv = UV;

	// Horizontal `.mm:before` layer: 0% -> 34% -> 58%.
	float ha;
	if (uv.x < 0.34) {
		ha = mix(u_left_a, u_mid_a, uv.x / 0.34);
	} else if (uv.x < 0.58) {
		ha = mix(u_mid_a, 0.0, (uv.x - 0.34) / 0.24);
	} else {
		ha = 0.0;
	}

	// Vertical `.mm:before` layer: transparent until 82%, then linear to 100%.
	float va = clamp((uv.y - 0.82) / 0.18, 0.0, 1.0) * u_bottom_a;

	float a = 1.0 - (1.0 - ha) * (1.0 - va);

	// Composer vignette: offset 0.4, darkness 0.4 (radial, all four edges).
	float d = length(uv - vec2(0.5)) * 1.4142;
	a = max(a, smoothstep(0.4, 0.92, d) * u_vignette_a);

	COLOR = vec4(u_tint.rgb, u_tint.a * a);
}
