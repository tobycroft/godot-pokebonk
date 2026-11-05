shader_type spatial;
// Menu-only variant of pb_terrain.gdshader, following the web's `up` diorama ground
// material (bundle offset ~274.5k, class `up` buildGround at 275.4k):
//   - grass detail is drawn on the sprite pixel grid (13.5 px/unit), not u_px
//   - cliff strata run along the *arc length* of the nearest mesa rim (radial
//     coordinate), which is what makes the walls read as curved stone blocks
//   - wet zones round both waterfall hits darken/blue the rock and raise the moss
//   - the wet sand band, contact shadow and hanging grass use the menu's thresholds
// The run screen keeps the shared pb_terrain.gdshader; this file is only assigned to
// the menu diorama's terrain material.
render_mode unshaded, cull_disabled;

uniform sampler2D t_ground : filter_nearest_mipmap_anisotropic;
uniform sampler2D t_path : filter_nearest_mipmap_anisotropic;
uniform sampler2D t_sand : filter_nearest_mipmap_anisotropic;
uniform sampler2D t_rock : filter_nearest_mipmap_anisotropic;
uniform sampler2D t_shade;

// Cliff palette (`Wu[pack]`): RA/RB base, RL lit, RD dark, RK ink, MA/MB moss.
uniform vec3 u_ra = vec3(0.58, 0.41, 0.30);
uniform vec3 u_rb = vec3(0.68, 0.50, 0.35);
uniform vec3 u_rl = vec3(0.86, 0.69, 0.47);
uniform vec3 u_rd = vec3(0.40, 0.27, 0.24);
uniform vec3 u_rk = vec3(0.24, 0.16, 0.22);
uniform vec3 u_ma = vec3(0.38, 0.60, 0.24);
uniform vec3 u_mb = vec3(0.26, 0.45, 0.20);
uniform vec3 u_band = vec3(0.0);
uniform vec3 u_shore_col = vec3(0.9, 0.85, 0.7);
uniform float u_moss = 0.74;
uniform float u_block_a = 2.2;
uniform float u_block_b = 3.2;
uniform float u_band_on = 1.0;
uniform float u_has_shore = 0.0;

// Ground detail flavour: 0 grass, 1 sand, 2 snow, 3 beach (the `_d()` switch).
uniform int u_detail = 0;
uniform int u_toon = 1;
uniform int u_no_shore = 0;

uniform vec3 u_sun_dir = vec3(0.458, 0.814, 0.356);
uniform vec3 u_cam = vec3(0.0);
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform vec3 u_sun_col = vec3(1.0);
uniform vec3 u_shadow_col = vec3(0.5);
uniform vec3 u_fog_col = vec3(0.6);
uniform float u_fog_near = 45.0;
uniform float u_fog_far = 170.0;
uniform float u_water = -999.0;
uniform float u_lava = 0.0;
uniform float u_tex_scale = 3.0;
uniform float u_grass_scale = 6.4;
uniform float u_px = 20.0;
uniform float u_world = 120.0;
uniform float u_shore_h = 0.5;
uniform float u_time_g = 0.0;

// Two waterfall footprints: (x, z, top, bottom) and the six mesa rims (x, z, r).
uniform vec4 u_fall1 = vec4(0.0);
uniform vec4 u_fall2 = vec4(0.0);
uniform vec3 u_mesa1 = vec3(0.0);
uniform vec3 u_mesa2 = vec3(0.0);
uniform vec3 u_mesa3 = vec3(0.0);
uniform vec3 u_mesa4 = vec3(0.0);
uniform vec3 u_mesa5 = vec3(0.0);
uniform vec3 u_mesa6 = vec3(0.0);

varying vec3 v_w;
varying vec3 v_n;
varying vec2 v_mask;   // uv2: (pathMask, colour variation)
varying vec2 v_cliff;  // tangent.xy: (cliff max, cliff min)

void vertex() {
	// The mesh is authored in world space and its node sits at the origin, so VERTEX already
	// is the world position -- no matrix juggling in a Godot spatial shader.
	v_w = VERTEX;
	v_n = normalize(NORMAL);
	v_mask = UV2;
	v_cliff = TANGENT.xy;
}

// ---------------------------------------------------------------- helpers (Lu / Ru)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
	mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float bayer4(vec2 p) {
	vec2 q = mod(p, 4.0);
	float v = mod(q.x + q.y * 2.0, 4.0) / 4.0;
	return fract(v + q.y * 0.3125);
}

float eqf(float a, float b) {
	return step(abs(a - b), 0.5);
}

// ---------------------------------------------------------------- Ku(): the cliff blocks
vec3 rock(float u, float y, float wet) {
	float px = 1.0 / u_px;
	vec2 ws = floor(v_w.xz * u_px) / u_px;
	float w = (vnoise(ws * 0.2 + 1.7) - 0.5) * 1.3 + (vnoise(ws * 0.75 + 5.3) - 0.5) * 0.3;
	float yy = y + w;
	yy += 0.22 * sin(yy * 2.3);
	float BH = 0.95;
	float bi = floor(yy / BH);
	float f = fract(yy / BH);
	float bh = hash(vec2(bi, 3.1));
	float bw = u_block_a + bh * u_block_b;
	float uu = u + (vnoise(vec2(u * 1.1, y * 1.8)) - 0.5) * 0.45;
	float bx = (uu + hash(vec2(bi, 9.2)) * 7.0) / bw;
	float bt = hash(vec2(floor(bx), bi));
	float tf = (1.0 - f) * BH;
	float bf = f * BH;
	float cx = fract(bx) * bw;
	float cr = (1.0 - fract(bx)) * bw;
	vec3 base = mix(u_ra, u_rb, clamp(bh * 0.45 + bt * 0.7 - 0.1, 0.0, 1.0));
	if (u_band_on > 0.5) {
		base = mix(base, u_band * (0.94 + bt * 0.1), step(0.8, bh));
	}
	float dth = bayer4(floor(vec2(u, y) * u_px)) * 0.12;
	float tone = f + (bt - 0.5) * 0.15;
	vec3 c = tone + dth > 0.78 ? mix(base, u_rl, 0.45)
	: (tone + dth < 0.3 ? mix(base, u_rd, 0.5) : base);
	float g = hash(floor(vec2(u, y) * u_px));
	c *= 0.97 + 0.06 * step(0.86, g) - 0.08 * step(g, 0.06);
	c = mix(c, u_rl, max(step(tf, 2.0 * px), step(cx, 2.0 * px) * step(0.35, f) * 0.6));
	c = mix(c, u_rd, max(step(cr, 2.0 * px), step(bf, 2.5 * px)));
	float dx = min(cx, cr);
	float dy = min(tf, bf);
	float chip = 2.5 * px + bt * 2.0 * px;
	float ink = max(step(bf, 1.0 * px), step(cx, 1.0 * px)) + step(dx + dy, chip) * step(dx, chip) * step(dy, chip);
	c = mix(c, u_rk, clamp(ink, 0.0, 1.0));
	float freq = u_moss > 0.0 ? 1.6 : 0.7;
	float mz = vnoise(vec2(u * freq, bi * 3.1)) + wet * 0.35;
	float drip = (0.1 + 0.4 * hash(vec2(floor(u * u_px / 2.0), bi))) * step(0.58, mz);
	float moss = step(u_moss > 0.0 ? u_moss : 0.64, mz) * step(tf, 2.5 * px + drip);
	c = mix(c, mix(u_mb, u_ma, step(tf, 1.5 * px)), moss);
	return c;
}

// ---------------------------------------------------------------- the ground details
vec3 toon_grass(vec2 pp, vec3 base) {
	vec2 ws = pp / 13.5;
	base *= vec3(1.06, 1.1, 0.92);
	float pv = vnoise(ws * 0.08 + 3.1) * 0.7 + vnoise(ws * 0.23) * 0.3 + (bayer4(pp + 1.0) - 0.5) * 0.1;
	float zone = pv > 0.6 ? 1.0 : (pv < 0.38 ? -1.0 : 0.0);
	vec3 lawn = base * (zone > 0.5 ? vec3(1.12, 1.1, 0.86) : (zone < -0.5 ? vec3(0.86, 0.92, 1.0) : vec3(1.0)));
	vec3 dark = base * vec3(0.58, 0.72, 0.82);
	vec3 lit = base * vec3(1.26, 1.2, 0.8);
	vec2 cell = floor(pp / vec2(7.0, 6.0));
	vec2 h = vec2(hash(cell), hash(cell + 17.3));
	vec2 l = pp - cell * vec2(7.0, 6.0) - floor(h * vec2(2.99, 3.99));
	float has = step(hash(cell + 5.1), 0.55 - zone * 0.15);
	float in_box = step(0.0, l.x) * step(l.x, 4.0) * step(0.0, l.y) * step(l.y, 2.0);
	float mark = eqf(l.y, 2.0) * (eqf(l.x, 0.0) + eqf(l.x, 4.0))
	+ eqf(l.y, 1.0) * (eqf(l.x, 0.0) + eqf(l.x, 2.0) + eqf(l.x, 4.0))
	+ eqf(l.y, 0.0) * (eqf(l.x, 1.0) + eqf(l.x, 3.0));
	vec3 c = mix(lawn, zone > 0.5 && h.x > 0.5 ? lit : dark, clamp(mark * in_box * has, 0.0, 1.0));
	// Flowers: a pixel cross in a 9x9 cell, one of four colours, with a yellow eye.
	vec2 fc = floor(pp / vec2(9.0, 9.0));
	vec2 fl = pp - fc * 9.0 - floor(vec2(hash(fc + 3.3), hash(fc + 8.1)) * 5.99);
	float is_f = step(hash(fc + 9.7), 0.09 + 0.06 * step(0.5, zone));
	float eye = eqf(fl.x, 0.0) * eqf(fl.y, 0.0);
	float pet = (eqf(abs(fl.x), 1.0) * eqf(fl.y, 0.0) + eqf(abs(fl.y), 1.0) * eqf(fl.x, 0.0));
	float k = hash(fc + 2.2);
	vec3 pc = k < 0.4 ? vec3(1.0, 0.98, 0.92) : (k < 0.65 ? vec3(1.0, 0.62, 0.72) : (k < 0.85 ? vec3(0.55, 0.7, 1.0) : vec3(1.0, 0.86, 0.3)));
	c = mix(c, pc, pet * is_f);
	c = mix(c, vec3(1.0, 0.8, 0.2), eye * is_f);
	return c;
}

vec3 toon_sand(vec2 pp, vec3 base) {
	vec2 ws = pp / 13.5;
	base = mix(base, vec3(0.97, 0.83, 0.58), 0.45);
	float pv = vnoise(ws * 0.07 + 5.3) * 0.7 + vnoise(ws * 0.2) * 0.3 + (bayer4(pp + 1.0) - 0.5) * 0.1;
	float zone = pv > 0.62 ? 1.0 : (pv < 0.36 ? -1.0 : 0.0);
	vec3 c = base * (zone > 0.5 ? vec3(1.06, 1.05, 1.0) : (zone < -0.5 ? vec3(0.92, 0.88, 0.9) : vec3(1.0)));
	float yy = pp.y + floor(2.5 * sin(pp.x * 0.1 + vnoise(ws * 0.25) * 6.0));
	float row = mod(yy, 8.0);
	float ri = floor(yy / 8.0);
	float seg = step(0.42, vnoise(vec2(pp.x * 0.07 + ri * 13.1, ri * 3.7)));
	c = mix(c, base * vec3(0.8, 0.7, 0.74), eqf(row, 0.0) * seg);
	c = mix(c, base * vec3(1.1, 1.08, 1.02), eqf(row, 7.0) * seg);
	float pb = step(0.993, hash(pp));
	c = mix(c, base * vec3(0.72, 0.58, 0.55), pb);
	c = mix(c, base * vec3(1.12, 1.08, 1.02), step(0.993, hash(pp - vec2(0.0, 1.0))) * (1.0 - pb));
	return c;
}

vec3 toon_beach(vec2 pp, vec3 base) {
	// The same ripple recipe as the desert sand, but wetter and paler (stormcape coast).
	vec2 ws = pp / 13.5;
	base = mix(base, vec3(0.97, 0.83, 0.58), 0.6);
	float pv = vnoise(ws * 0.07 + 5.3) * 0.7 + vnoise(ws * 0.2) * 0.3 + (bayer4(pp + 1.0) - 0.5) * 0.1;
	float zone = pv > 0.62 ? 1.0 : (pv < 0.36 ? -1.0 : 0.0);
	vec3 c = base * (zone > 0.5 ? vec3(1.06, 1.05, 1.0) : (zone < -0.5 ? vec3(0.92, 0.88, 0.9) : vec3(1.0)));
	float yy = pp.y + floor(2.5 * sin(pp.x * 0.1 + vnoise(ws * 0.25) * 6.0));
	float row = mod(yy, 8.0);
	float ri = floor(yy / 8.0);
	float seg = step(0.42, vnoise(vec2(pp.x * 0.07 + ri * 13.1, ri * 3.7)));
	c = mix(c, base * vec3(0.8, 0.7, 0.74), eqf(row, 0.0) * seg);
	c = mix(c, base * vec3(1.1, 1.08, 1.02), eqf(row, 7.0) * seg);
	float pb = step(0.993, hash(pp));
	c = mix(c, base * vec3(0.72, 0.58, 0.55), pb);
	return c;
}

vec3 toon_snow(vec2 pp, vec3 base) {
	vec2 ws = pp / 13.5;
	base = mix(base, vec3(0.84, 0.88, 0.97), 0.7);
	float pv = vnoise(ws * 0.07 + 2.3) * 0.7 + vnoise(ws * 0.21) * 0.3 + (bayer4(pp + 1.0) - 0.5) * 0.1;
	float zone = pv > 0.6 ? 1.0 : (pv < 0.36 ? -1.0 : 0.0);
	vec3 c = base * (zone > 0.5 ? vec3(1.09, 1.08, 1.03) : (zone < -0.5 ? vec3(0.88, 0.89, 0.99) : vec3(1.0)));
	float yy = pp.y + floor(3.0 * sin(pp.x * 0.07 + vnoise(ws * 0.2) * 5.0));
	float row = mod(yy, 11.0);
	float ri = floor(yy / 11.0);
	float seg = step(0.5, vnoise(vec2(pp.x * 0.06 + ri * 7.3, ri * 2.9)));
	c = mix(c, base * vec3(0.8, 0.82, 0.97), eqf(row, 0.0) * seg);
	c = mix(c, base * 1.12, eqf(row, 10.0) * seg);
	vec2 lc = floor(pp / 9.0);
	vec2 lh = vec2(hash(lc + 3.3), hash(lc + 8.1));
	vec2 ll = pp - lc * 9.0 - floor(lh * 5.99);
	float has = step(hash(lc + 1.7), 0.18);
	float lump = step(0.0, ll.x) * step(ll.x, 2.0) * step(0.0, ll.y) * step(ll.y, 1.0);
	float under = step(0.0, ll.x) * step(ll.x, 2.0) * eqf(ll.y, -1.0);
	c = mix(c, base * 1.12, lump * has);
	c = mix(c, base * vec3(0.76, 0.78, 0.95), under * has);
	float g = hash(pp + 0.37);
	float tw = step(0.75, fract(g * 13.7 + u_time_g * (0.2 + g * 0.4)));
	c = mix(c, mix(vec3(0.75, 0.95, 1.0), vec3(1.0), step(0.5, g)), step(0.9965, g) * tw);
	return c;
}

// ---------------------------------------------------------------- Zu(): the toon light
vec3 toon_light(vec3 n, vec2 pp) {
	float ndl = dot(n, normalize(u_sun_dir));
	float d = (bayer4(pp) - 0.5) * 0.06;
	float band = step(0.02, ndl + d) * 0.72 + step(0.58, ndl + d) * 0.28;
	float sky = floor(n.y * 3.0 + bayer4(pp + 2.0) * 0.9) / 3.0;
	return mix(mix(u_shadow_col, u_sun_col, 0.3), u_sun_col, band) + vec3(0.06, 0.08, 0.12) * sky;
}

vec3 ground_detail(vec2 pp, vec3 base) {
	if (u_detail == 1) {
		return toon_sand(pp, base);
	} else if (u_detail == 2) {
		return toon_snow(pp, base);
	} else if (u_detail == 3) {
		return toon_beach(pp, base);
	}
	return toon_grass(pp, base);
}

void fragment() {
	vec3 n = normalize(v_n);
	float slope = 1.0 - n.y;
	vec2 pp = floor(v_w.xz * u_px);
	vec2 ws = pp / u_px;
	vec2 uv = v_w.xz / u_tex_scale;

	// Grass detail sits on the sprite's 13.5 px/unit grid; rock keeps u_px (20/unit).
	vec2 gp = floor(v_w.xz * 13.5);
	vec3 g = ground_detail(gp, texture(t_ground, vec2(0.5)).rgb);

	// Wet zone round each fall: darker, bluer rock and more moss.
	float wet = max((1.0 - smoothstep(1.4, 3.2, distance(v_w.xz, u_fall1.xy))) * step(u_fall1.w - 0.5, v_w.y) * step(v_w.y, u_fall1.z + 0.3),
		(1.0 - smoothstep(1.4, 3.2, distance(v_w.xz, u_fall2.xy))) * step(u_fall2.w - 0.5, v_w.y) * step(v_w.y, u_fall2.z + 0.3));

	// Coordinate along the wall: arc length round the closest mesa rim.
	vec3 best = u_mesa1;
	float bd = abs(distance(v_w.xz, u_mesa1.xy) - u_mesa1.z);
	float dm = abs(distance(v_w.xz, u_mesa2.xy) - u_mesa2.z);
	if (dm < bd) { bd = dm; best = u_mesa2; }
	dm = abs(distance(v_w.xz, u_mesa3.xy) - u_mesa3.z);
	if (dm < bd) { bd = dm; best = u_mesa3; }
	dm = abs(distance(v_w.xz, u_mesa4.xy) - u_mesa4.z);
	if (dm < bd) { bd = dm; best = u_mesa4; }
	dm = abs(distance(v_w.xz, u_mesa5.xy) - u_mesa5.z);
	if (dm < bd) { bd = dm; best = u_mesa5; }
	dm = abs(distance(v_w.xz, u_mesa6.xy) - u_mesa6.z);
	if (dm < bd) { bd = dm; best = u_mesa6; }
	float along = atan(v_w.x - best.x, v_w.z - best.y) * best.z + best.x * 3.7;
	float u = floor(along * u_px) / u_px;
	float y = floor(v_w.y * u_px) / u_px;

	vec3 r = rock(u, y, wet);
	r *= mix(1.0, 0.72, wet);
	r.b += 0.04 * wet;
	// Ambient occlusion at the foot of every wall.
	r *= mix(0.68, 1.0, smoothstep(0.0, 1.8, v_w.y - v_cliff.y));

	vec3 col = mix(g, texture(t_sand, uv).rgb,
		step(v_w.y, u_water + 0.5 + (hash(pp) - 0.5) * 0.12));
	col *= 1.0 - 0.1 * smoothstep(1.5, 4.0, v_cliff.x - v_w.y) * step(slope, 0.3);
	col *= mix(1.0, 0.72, smoothstep(u_water + 0.15, u_water - 0.4, v_w.y));

	// Crisp, dithered grass/rock border.
	float is_rock = step(0.34 + (hash(pp) - 0.5) * 0.1, slope);
	// Grass hanging over the top edge of the walls.
	float d = v_cliff.x - v_w.y;
	float col_n = floor(along * u_px / 2.0);
	float L = 0.22 + 0.3 * hash(vec2(col_n, 1.3)) + 0.25 * vnoise(vec2(along * 0.9, 2.0));
	float hang = step(d, L) * is_rock * step(v_cliff.x - v_cliff.y, 30.0)
		* step(1.2, v_cliff.x - v_cliff.y);
	vec3 hg = mix(g, vec3(0.2, 0.36, 0.2), step(L - 1.5 / u_px, d));
	col = mix(col, r, is_rock);
	col = mix(col, hg, hang);

	col *= toon_light(n, pp);

	// Baked prop shadows: one flat tone, cut on the pixel grid, never stacking.
	float sh = texture(t_shade, (ws + 0.5 / u_px) / u_world + 0.5).r;
	col *= mix(vec3(1.0), vec3(0.66, 0.72, 0.9), step(0.5 + (bayer4(pp + 3.0) - 0.5) * 0.5, sh) * (1.0 - is_rock));
	if (u_lava > 0.5) {
		col += vec3(1.0, 0.35, 0.05) * smoothstep(u_water + 0.6, u_water, v_w.y) * 0.7;
	}

	ALBEDO = mix(col, u_fog_col, smoothstep(u_fog_near, u_fog_far, dot(v_w - u_cam, u_cam_fwd)));
}
