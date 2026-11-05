shader_type spatial;
// Sky for the main-menu title diorama. Ported from the web menu scene's sky shader
// (bundle `main-C5MieX6g-mvpjh5lt.js`, renderer class at offset 100575): flat dithered
// gradient bands, a pixel sun disc and four-tone cumulus. Moon/eclipse/stars are omitted
// because the pond title calls setMoon(0), setAtmos(1,1,1,0,0,.4).
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform vec3 u_top;
uniform vec3 u_bottom;
uniform vec3 u_sun_dir = vec3(0.531, 0.77, 0.354);
uniform vec3 u_cloud_tint : source_color = vec3(1.0);
uniform float u_time = 0.0;
uniform float u_px = 4.0;
uniform float u_cover = 0.0;

varying vec3 v_dir;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x),
		mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return n(p) * 0.5 + n(p * 2.03 + 1.7) * 0.28 + n(p * 4.1 + 4.3) * 0.14 + n(p * 8.3 + 2.1) * 0.08;
}

float bayer(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	int i = int(q.y * 4.0 + q.x);
	float m[16];
	m[0] = 0.0; m[1] = 8.0; m[2] = 2.0; m[3] = 10.0;
	m[4] = 12.0; m[5] = 4.0; m[6] = 14.0; m[7] = 6.0;
	m[8] = 3.0; m[9] = 11.0; m[10] = 1.0; m[11] = 9.0;
	m[12] = 15.0; m[13] = 7.0; m[14] = 13.0; m[15] = 5.0;
	for (int k = 0; k < 16; k++) {
		if (k == i) {
			return m[k] / 16.0;
		}
	}
	return 0.0;
}

float clouds(vec2 uv) {
	return fbm(uv) + u_cover * 0.28;
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	// Pixel-art sky: each u_px block takes the colour of its centre direction.
	vec2 fc = FRAGCOORD.xy;
	vec2 cell = floor(fc / u_px);
	vec2 sc = (cell + 0.5) * u_px;
	vec3 dir = normalize(v_dir + dFdx(v_dir) * (sc.x - fc.x) + dFdy(v_dir) * (sc.y - fc.y));
	float dth = bayer(cell);

	float y = clamp(dir.y * 1.4 + 0.15, 0.0, 1.0);
	float bands = 7.0;
	float t = pow(y, 0.8) * bands;
	float tb = (floor(t) + step(1.0 - fract(t), 0.35) * step(dth, (fract(t) - 0.65) / 0.35)) / bands;
	vec3 c = mix(u_bottom, u_top, clamp(tb, 0.0, 1.0));

	// Sun: a pixel disc with a pale ring and two stepped glow bands.
	float s = max(dot(dir, normalize(u_sun_dir)), 0.0);
	c = mix(c, mix(c, vec3(1.0, 0.97, 0.86), 0.5), step(0.9955, s));
	c = mix(c, vec3(1.0, 0.98, 0.9), step(0.9985, s));
	c += vec3(1.0, 0.85, 0.6) * (step(0.97, s) * 0.06 + step(0.92, s + (dth - 0.5) * 0.01) * 0.04);

	// Cumulus on a cloud plane, in four flat tones.
	vec2 uv = dir.xz / (dir.y + 0.18) * 1.1 + vec2(u_time * 0.012, u_time * 0.004);
	float fade = smoothstep(0.02, 0.2, dir.y);
	float cl = clouds(uv) * fade;
	float edge = 0.56 + (dth - 0.5) * 0.02;
	if (cl > edge) {
		vec2 to_sun = normalize(u_sun_dir.xz + vec2(1e-4)) * 0.16;
		float lit = clouds(uv + to_sun) * fade;
		float shade = clouds(uv - to_sun) * fade;
		vec3 body = vec3(0.97, 0.98, 1.0);
		vec3 sh = vec3(0.78, 0.82, 0.96);
		vec3 base = vec3(0.64, 0.68, 0.88);
		vec3 rim = vec3(1.0, 0.99, 0.93);
		float away = step(shade, cl - 0.01);
		float toward = step(lit, cl - 0.01);
		vec3 cc = mix(body, sh, away);
		cc = mix(cc, base, away * step(cl, edge + 0.05));
		cc = mix(cc, rim, toward * step(cl, edge + 0.06));
		cc = mix(cc, vec3(1.0), step(edge + 0.16, cl) * (1.0 - away));
		c = mix(c, cc * u_cloud_tint, 0.97);
	}

	ALBEDO = c;
}
