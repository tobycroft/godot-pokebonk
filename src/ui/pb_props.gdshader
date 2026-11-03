shader_type spatial;
// Atlas props as cylindrical billboards, ported from the client's prop material
// (bundle offset 186300: `cu` windSway + `lu` instanced billboards).
//
// Per-instance data is carried on built-in vertex channels (Godot has no custom attributes in
// spatial shaders): tangent = (x, y, z, windHeightOffset), color = (width, height, pixel size,
// sway), uv = the sprite's atlas rect (flip already baked in), vertex = the unit quad.
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
	vec3 inst_pos = TANGENT.xyz;
	float width = COLOR.x;
	float height = COLOR.y;
	float sway_amount = COLOR.z;
	float pixel = UV2.x;
	float height_offset = UV2.y;

	float h = VERTEX.y;
	float sway = 0.0;
	float dip = 0.0;
	if (sway_amount > 0.0) {
		sway = wind_sway(inst_pos.xz, u_time, h, height_offset) * sway_amount * u_wind * height * 1.2;
		// Whole atlas pixels, so the sprite never smears like a 3D quad would.
		sway = floor(sway / pixel + 0.5) * pixel;
		dip = 0.5 * sway * sway / max(height, 0.01);
	}
	// The reference takes the camera right axis out of the view matrix; here it arrives as a
	// uniform, so the billboard stays upright without touching any matrix.
	vec3 right = normalize(u_cam_right);
	vec3 w = inst_pos + right * (VERTEX.x * width + sway) + vec3(0.0, h * height - dip, 0.0);

	VERTEX = w;
	v_dist = dot(w - u_cam, u_cam_fwd);
	v_y = h;
	// Props standing between the camera and the player thin out with a dither, so they never
	// hide the character.
	vec3 a = u_cam;
	vec3 b = u_player + vec3(0.0, 1.0, 0.0);
	vec3 ab = b - a;
	float t = clamp(dot(w - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	float dseg = length(a + ab * t - (inst_pos + vec3(0.0, height * 0.45, 0.0)));
	v_fade = (1.0 - smoothstep(width * 0.35 + 0.8, width * 0.6 + 2.5, dseg))
	* step(t, 0.97) * step(0.02, t);
}

float bayer4(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	float i = q.y * 4.0 + q.x;
	return mod(i * 7.0, 16.0) / 16.0;
}

void fragment() {
	vec4 t = texture(map, UV);
	if (t.a < 0.5) {
		discard;
	}
	if (v_fade > 0.01 && bayer4(FRAGCOORD.xy) < v_fade * 0.75) {
		discard;
	}
	vec3 c = t.rgb * u_tint * mix(0.78, 1.0, smoothstep(0.0, 0.22, v_y));
	ALBEDO = mix(c, u_fog_col, smoothstep(u_fog_near, u_fog_far, v_dist));
}
