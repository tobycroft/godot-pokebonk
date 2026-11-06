shader_type spatial;
// Atlas props as cylindrical billboards, ported from the client's prop material
// (bundle offset 186300: `cu` windSway + `lu` instanced billboards).
//
// Props are drawn from one MultiMesh, so per-prop data rides on the instance transform plus
// INSTANCE_CUSTOM: MODEL_MATRIX[0].xyz = (width, height, pixel size),
// MODEL_MATRIX[1].xy = (sway amount, wind height offset), MODEL_MATRIX[3].xyz = anchor,
// INSTANCE_CUSTOM = (u0, v_bottom, du, dv) for the sprite's atlas rect (flip already baked
// in). VERTEX is the unit quad: x in [-0.5, 0.5], y in [0, 1].
// (The earlier batched ArrayMesh stored these in TANGENT/COLOR, but Godot normalises tangents
// and clamps vertex colours to 8 bits, which collapsed every prop onto the origin.)
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D map : filter_nearest;
uniform vec3 u_tint = vec3(1.0);
uniform vec3 u_fog_col = vec3(0.6);
uniform vec3 u_player = vec3(0.0, -999.0, 0.0);
uniform vec3 u_cam = vec3(0.0);
uniform vec3 u_cam_right = vec3(1.0, 0.0, 0.0);
uniform float u_fog_near = 45.0;
uniform float u_fog_far = 170.0;
uniform float u_wind = 1.0;
uniform vec3 u_cam_fwd = vec3(0.0, 0.0, -1.0);
uniform float u_time = 0.0;

varying float v_dist;
varying float v_y;
varying float v_fade;
varying vec2 v_uv;

const vec2 WIND_DIR = vec2(0.86, 0.51);

// cu: horizontal offset at relative height h, as a share of the sprite height.
float wind_sway(vec2 p, float t, float h, float height_offset) {
	float bend = max(0.0, h - height_offset) / (1.0 - height_offset);
	bend *= bend;
	float min_s = 0.35, max_s = 1.0, interval = 3.5, detail = 1.7;
	float gust = mix(min_s, max_s, 0.5 + 0.5 * sin(t / interval + dot(p, vec2(0.031, 0.017))));
	float ph = t * 1.6 - dot(p, WIND_DIR) * 0.22;
	float wave = (sin(ph) + cos(ph * detail + 0.6)) * 0.5;
	return wave * gust * bend;
}

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float width = MODEL_MATRIX[0].x;
	float height = MODEL_MATRIX[0].y;
	float pixel = max(MODEL_MATRIX[0].z, 0.0001);
	float sway_amount = MODEL_MATRIX[1].x;
	float height_offset = MODEL_MATRIX[1].y;
	// Atlas rect, packed per instance as (u0, v_bottom, du, dv).
	vec4 rect = INSTANCE_CUSTOM;
	v_uv = vec2(rect.x + (VERTEX.x + 0.5) * rect.z, rect.y + VERTEX.y * rect.w);

	float h = VERTEX.y;
	float sway = 0.0;
	float dip = 0.0;
	if (sway_amount > 0.0) {
		sway = wind_sway(anchor.xz, u_time, h, height_offset) * sway_amount * u_wind * height * 1.2;
		// Whole atlas pixels, so the sprite never smears like a 3D quad would.
		sway = floor(sway / pixel + 0.5) * pixel;
		dip = 0.5 * sway * sway / max(height, 0.01);
	}
	// The reference takes the camera right axis out of the view matrix; here it arrives as a
	// uniform, so the billboard stays upright without touching any matrix.
	vec3 right = normalize(u_cam_right);
	vec3 w = anchor + right * (VERTEX.x * width + sway) + vec3(0.0, h * height - dip, 0.0);
	// Replace the instance transform with the billboard basis, so the unit quad lands on the
	// world-space rectangle above.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right * width, 0.0),
		vec4(0.0, height, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(anchor + right * sway + vec3(0.0, -dip, 0.0), 1.0));

	v_dist = dot(w - u_cam, u_cam_fwd);
	v_y = h;
	// Props standing between the camera and the player thin out with a dither, so they never
	// hide the character.
	vec3 a = u_cam;
	vec3 b = u_player + vec3(0.0, 1.0, 0.0);
	vec3 ab = b - a;
	float t = clamp(dot(w - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	float dseg = length(a + ab * t - (anchor + vec3(0.0, height * 0.45, 0.0)));
	v_fade = (1.0 - smoothstep(width * 0.35 + 0.8, width * 0.6 + 2.5, dseg))
	* step(t, 0.97) * step(0.02, t);
}

float bayer4(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	float i = q.y * 4.0 + q.x;
	return mod(i * 7.0, 16.0) / 16.0;
}

void fragment() {
	vec4 t = texture(map, v_uv);
	if (t.a < 0.5) {
		discard;
	}
	if (v_fade > 0.01 && bayer4(FRAGCOORD.xy) < v_fade * 0.75) {
		discard;
	}
	vec3 c = t.rgb * u_tint * mix(0.78, 1.0, smoothstep(0.0, 0.22, v_y));
	ALBEDO = mix(c, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
}
