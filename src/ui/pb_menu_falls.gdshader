shader_type spatial;
// Waterfall curtain for the main-menu diorama. Ported from the web menu scene
// (`buildWaterfall`, bundle offset 275528).
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, fog_disabled;

uniform float u_time = 0.0;
uniform vec2 u_size = vec2(2.2, 5.0);
uniform float u_back = 0.0;
uniform vec3 u_fog_col = vec3(0.45);
uniform float u_fog_near = 54.0;
uniform float u_fog_far = 162.0;

varying vec2 v_uv;
varying float v_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_uv = UV;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = -mv.z;
}

void fragment() {
	vec2 P = floor(vec2(v_uv.x * u_size.x, (1.0 - v_uv.y) * u_size.y) * 10.0);
	float s = 1.0 - v_uv.y;
	float lane = hash(vec2(P.x, 1.0));
	float y = P.y - floor(u_time * (60.0 + lane * 30.0) * (1.0 - u_back * 0.45));
	float len = 7.0 + lane * 12.0;
	float streak = step(0.62, fract(y / len + lane * 3.1));
	float fleck = step(0.86, fract(y / (len * 0.45) + lane * 7.3));

	float jag = hash(vec2(floor(y / 3.0), step(0.5, v_uv.x))) * 0.09;
	float edge = step(0.03 + jag, v_uv.x) * step(v_uv.x, 0.97 - jag);
	float cen = 1.0 - abs(v_uv.x - 0.5) * 2.0;
	vec3 col = cen < 0.22 ? vec3(0.22, 0.56, 0.92)
		: cen < 0.6 ? vec3(0.42, 0.78, 1.0)
		: vec3(0.55, 0.88, 1.0);
	col = mix(col, vec3(0.86, 0.97, 1.0), streak * 0.85);
	col = mix(col, vec3(1.0), fleck * step(0.3, cen));
	col = mix(col, col * vec3(0.62, 0.72, 0.85), u_back);

	float curl = step(s * u_size.y, 0.22 + 0.12 * hash(vec2(P.x, 3.0)));
	float froth = step(1.0 - 0.9 / u_size.y - 0.08 * hash(vec2(P.x, floor(u_time * 8.0))), s)
		+ step(1.0 - 2.2 / u_size.y, s) * step(0.55, hash(P + floor(u_time * 10.0)));
	col = mix(col, vec3(1.0), clamp(curl + froth, 0.0, 1.0) * (1.0 - u_back));

	float a = mix(0.88, 0.78, u_back) * edge;
	if (a < 0.05) {
		discard;
	}
	ALBEDO = mix(col, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
	ALPHA = a;
}
