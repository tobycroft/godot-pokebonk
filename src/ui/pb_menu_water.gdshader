shader_type spatial;
// Pond water for the main-menu diorama. Ported from the web title diorama's
// `waterMat()` (bundle offset 275528): four flat depth bands, drifting wave dashes,
// single-pixel glints, fall-hit rings/foam and a breathing shoreline band.
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

uniform sampler2D t_h : filter_nearest;   // normalised height lattice (FORMAT_RF)
uniform vec3 u_cam = vec3(0.0);
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform float u_time = 0.0;
uniform float u_min = 0.0;
uniform float u_range = 1.0;
uniform float u_level = -0.6;
uniform float u_max_depth = 99.0;
uniform vec2 u_flow = vec2(0.0);
uniform float u_shore = 1.0;
uniform vec3 u_hit = vec3(0.0);
uniform vec3 u_sky : source_color = vec3(0.51, 0.615, 0.72);
uniform vec3 u_fog_col : source_color = vec3(0.6);
uniform float u_fog_near = 54.0;
uniform float u_fog_far = 162.0;

varying vec3 v_w;
varying float v_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = -mv.z;
}

void fragment() {
	float ground = texture(t_h, (v_w.xz + 60.0) / 120.0).r * u_range + u_min;
	float depth = u_level - ground;
	if (depth < 0.0 || depth > u_max_depth) {
		discard;
	}
	if (u_shore < 0.5) {
		// Flow strips: no water over steep ground.
		vec2 e = vec2(0.5, 0.0) / 120.0;
		vec2 c = (v_w.xz + 60.0) / 120.0;
		float gx = texture(t_h, c + e.xy).r - texture(t_h, c - e.xy).r;
		float gz = texture(t_h, c + e.yx).r - texture(t_h, c - e.yx).r;
		if (length(vec2(gx, gz)) * u_range > 1.6) {
			discard;
		}
	}

	vec2 px = floor(v_w.xz * 12.0) / 12.0;
	vec2 fl = u_flow * u_time;
	float dd = depth + (vnoise(px * 0.6 + fl * 0.3) - 0.5) * 0.3;
	vec3 col = dd < 0.28 ? vec3(0.56, 0.94, 0.90)
		: dd < 0.75 ? vec3(0.27, 0.78, 0.92)
		: dd < 1.4 ? vec3(0.14, 0.55, 0.86)
		: vec3(0.10, 0.40, 0.75);

	vec3 V = normalize(u_cam - v_w);
	col = mix(col, u_sky, pow(1.0 - V.y, 4.0) * 0.45);

	float wv = vnoise(vec2(px.x * 0.55 + u_time * 0.18, px.y * 1.9 - u_time * 0.12) + fl);
	float line = step(abs(fract(wv * 4.0) - 0.5), 0.045)
		* step(0.5, vnoise(px * 0.3 + u_time * 0.04 + fl * 0.5));
	col = mix(col, min(col + vec3(0.2, 0.18, 0.12), vec3(1.0)), line);
	col = mix(col, vec3(1.0), step(0.996, hash(floor(v_w.xz * 12.0) + floor(u_time * 2.5) * 1.7)) * 0.9);

	float foam = 0.0;
	if (u_hit.z > 0.5) {
		float d = distance(v_w.xz, u_hit.xy);
		float ring = step(fract(d * 0.6 - u_time * 0.7), 0.06) * (1.0 - smoothstep(1.8, 6.5, d));
		col = mix(col, vec3(0.86, 1.0, 1.0), ring * 0.8);
		float fn1 = vnoise(px * 1.6 + vec2(u_time * 1.3, -u_time));
		foam = max(foam, step(d, 1.2 + 1.1 * fn1));
		foam = max(foam, step(d, 2.4) * step(0.72, vnoise(px * 2.2 - u_time * 0.9)));
	}
	float fw = 0.11 + 0.06 * sin(u_time * 1.6 + vnoise(px * 0.6) * 6.0);
	foam = max(foam, step(depth, fw) * u_shore);
	foam = max(foam, step(depth, fw + 0.2) * step(0.6, vnoise(px * 1.4 + u_time * 0.35)) * 0.85 * u_shore);
	col = mix(col, vec3(1.0), foam);

	float alpha = mix(0.74, 0.94, smoothstep(0.0, 1.4, depth));
	ALBEDO = mix(col, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
	ALPHA = max(alpha, foam * 0.97);
}
