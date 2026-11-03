shader_type spatial;
// Water / ice / lava, ported from the client's `buildWater()` material
// (bundle offset 240620). Ripples are snapped to an 8 px grid and ice cracks to 13.5 px, so
// the surface keeps the same pixel-art read as the ground.
render_mode unshaded, cull_back, depth_draw_always;

uniform sampler2D t_h;              // height lattice (FORMAT_RF), world extents
uniform float u_time = 0.0;
uniform vec3 u_cam = vec3(0.0);
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform float u_scale = 1.0;
uniform float u_world = 360.0;
uniform float u_level = 0.0;
uniform float u_lava = 0.0;
uniform float u_ice = 0.0;
uniform vec3 u_deep = vec3(0.06, 0.2, 0.4);
uniform vec3 u_shallow = vec3(0.42, 0.7, 0.9);
uniform vec3 u_fog_col = vec3(0.6);
uniform float u_fog_near = 45.0;
uniform float u_fog_far = 170.0;

varying vec3 v_w;
varying float v_dist;

void vertex() {
	v_w = VERTEX;
	v_dist = dot(v_w - u_cam, u_cam_fwd);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
	mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 huv = (v_w.xz + u_world * 0.5) / u_world;
	float depth = max(0.0, u_level - texture(t_h, huv).r) / u_scale;
	vec3 col = mix(u_shallow, u_deep, smoothstep(0.0, 3.0, depth));
	vec2 px = floor(v_w.xz * 8.0) / 8.0;
	float r1 = vnoise(px * 0.9 + vec2(u_time * 0.6, u_time * 0.25));
	float r2 = vnoise(px * 1.3 - vec2(u_time * 0.35, -u_time * 0.5));
	float spark = step(0.9, r1 * r2 * 1.9);
	float band = step(0.62, (r1 + r2) * 0.5);
	float foam_w = 0.3 + 0.12 * sin(u_time * 1.6 + vnoise(px * 0.5) * 6.0);
	float foam = step(depth, foam_w) + step(depth, foam_w + 0.25) * step(0.55, r1) * 0.7;
	float alpha = 1.0;

	if (u_ice > 0.5) {
		vec2 ip = floor(v_w.xz * 13.5);
		vec3 ice = mix(vec3(0.78, 0.92, 1.0), vec3(0.42, 0.7, 0.95), smoothstep(0.2, 3.5, depth));
		float pv = vnoise(ip * 0.02 + 4.0) * 0.7 + vnoise(ip * 0.07) * 0.3;
		ice *= pv > 0.62 ? 1.05 : (pv < 0.38 ? 0.93 : 1.0);
		float frost = step(depth, 0.35 + 0.25 * vnoise(ip * 0.05));
		ice = mix(ice, vec3(0.93, 0.97, 1.0), frost);
		// Long cracks: one wobbly line through some 60 px cells, fading toward the rim.
		vec2 cq = ip / 60.0;
		vec2 cf = fract(cq) - 0.5, ci = floor(cq);
		float ang = hash(ci) * 6.283, ca = cos(ang), sa = sin(ang);
		float along = cf.x * ca + cf.y * sa;
		float crack = abs(cf.x * sa - cf.y * ca + (vnoise(vec2(along * 9.0, hash(ci) * 50.0)) - 0.5) * 0.09) * 60.0;
		float has_c = step(0.62, hash(ci + 7.0)) * step(abs(along), 0.36 + 0.1 * hash(ci + 3.0));
		ice = mix(ice, vec3(0.3, 0.52, 0.8), step(crack, 0.6) * has_c * (1.0 - frost));
		ice = mix(ice, vec3(1.0), step(0.6, crack) * step(crack, 1.6) * has_c * (1.0 - frost) * 0.6);
		float g = hash(ip + 0.31);
		float tw = step(0.8, fract(g * 9.1 + u_time * (0.25 + g * 0.5)));
		ice = mix(ice, vec3(1.0), step(0.996, g) * tw);
		ALBEDO = mix(ice, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
		ALPHA = 1.0;
	} else if (u_lava > 0.5) {
		float crust = step(0.55, vnoise(px * 0.6 + u_time * 0.1));
		col = mix(vec3(1.2, 0.45, 0.06), vec3(0.25, 0.08, 0.05), crust * 0.85) + vec3(1.0, 0.8, 0.3) * spark;
		ALBEDO = mix(col, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
		ALPHA = 1.0;
	} else {
		col = mix(col, col * 1.15, band);
		col = mix(col, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.9);
		col += vec3(0.9, 1.0, 1.0) * spark * 0.8;
		alpha = mix(0.75, 0.95, smoothstep(0.0, 2.5, depth));
		// Water is the only transparent surface in this renderer, matching the reference.
		ALBEDO = mix(col, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
		ALPHA = max(alpha, clamp(foam, 0.0, 1.0) * 0.95);
	}
}
