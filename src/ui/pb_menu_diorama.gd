class_name PbMenuDiorama
extends Node3D
## Live 3D title diorama for the main menu, ported from the web menu scene's `up` class
## (bundle `main-C5MieX6g-mvpjh5lt.js` @275528). It builds the same 120 m height field,
## pond, mesa waterfalls, forest prop scatter (seed 2026), lily pads and PMD actors, and
## drives the same slow camera drift. Rendering reuses PbWorldView for the height-field
## mesh/props/sky and adds the pond water, fall curtains and sprite actors on top.

# --------------------------- web constants (bundle @270000) ---------------------------
const WORLD := 120.0
const GRID := 240
const CELL := WORLD / float(GRID)
const WATER_LEVEL := -0.6
const POND_X := 6.5
const POND_Z := 0.5
const POND_RX := 10.5
const POND_RZ := 6.8

const CAM_POS := Vector3(-6.0, 5.6, 19.5)
const LOOK_AT := Vector3(5.5, 2.9, -4.5)

# Kf / qf / Jf / Yf / Xf / Zf in the web source.
const MESA_A := {"x": 10.0, "z": -19.5, "r": 10.5, "h": 10.0}
const MESA_B := {"x": 11.0, "z": -9.0, "r": 5.6, "h": 4.6}
const MESA_C := {"x": 0.8, "z": -13.8, "r": 3.8, "h": 7.2}
const MESA_D := {"x": -15.0, "z": -23.0, "r": 9.0, "h": 6.4}
const MESA_E := {"x": -14.0, "z": -21.5, "r": 11.6, "h": 2.6}
const MESA_F := {"x": 32.0, "z": -7.0, "r": 8.0, "h": 3.4}

const FALL_A := {"x": 15.0, "z": -29.0, "w": 1.8}
const WATER_LIP := {"x": 10.5, "z": -9.4}
const FALL_B := {"x": 10.5, "z": -7.2, "r": 2.2}
const FALL_B_TOP := {"x": 10.6, "z": -3.4}

# np = Kf.h - 0.35, rp = qf.h - 0.45.
const MESA_TOP := 9.65
const MESA_MID := 4.15

# ------------------------------- web colours (sRGB hex) -------------------------------
const SKY_TOP := 3970303
const SKY_BOTTOM := 13823999
const FOG_COLOR := 12904191
const SUN_COLOR := 16773328
const SHADOW_COLOR := 8030408
const WATER_SKY := 13496063

const SUN_DIR := Vector3(0.531, 0.77, 0.354)

const PROP_TINT := Vector3(1.0, 0.98, 0.94)

var _view: PbWorldView
var _terrain: PbTerrain
var _cam: Camera3D
var _height_tex: ImageTexture
var _pack: Dictionary
var _noise_a: PbSimplex
var _noise_b: PbSimplex
var _sun: DirectionalLight3D

var _heights: PackedFloat32Array
var _min_h := 0.0
var _max_h := 0.0

var _falls: Array = []
var _pads: Array = []
var _actors: Array = []
var _water_mats: Array = []
var _rng := RandomNumberGenerator.new()

var _t := 0.0
var _sky_mat: ShaderMaterial
var _water_mat: ShaderMaterial

const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.07, 0.05, 0.18);
	ALPHA = smoothstep(1.0, 0.32, d) * 0.34;
}
"""


func _ready() -> void:
	_noise_a = PbSimplex.new(77)
	_noise_b = PbSimplex.new(91)
	_rng.seed = 20261105
	_build_terrain()
	_build_height_texture()
	_build_view()
	_build_camera()
	_build_water()
	_build_falls()
	_build_pads()
	_build_actors()
	_build_environment()


# ------------------------------------------------------------------------ terrain
func _build_terrain() -> void:
	var n := GRID + 1
	_heights = PackedFloat32Array()
	_heights.resize(n * n)
	_min_h = 1e9
	_max_h = -1e9
	for gz in n:
		for gx in n:
			var h := _shape(gx * CELL - WORLD * 0.5, gz * CELL - WORLD * 0.5)
			_heights[gz * n + gx] = h
			_min_h = minf(_min_h, h)
			_max_h = maxf(_max_h, h)

	_terrain = PbTerrain.new()
	_terrain.world = WORLD
	_terrain.res = GRID
	_terrain.cell = CELL
	_terrain.heights = _heights
	_terrain.path_mask = PackedFloat32Array()
	_terrain.path_mask.resize(n * n)
	_terrain.has_water = true
	_terrain.water_level = WATER_LEVEL
	_terrain.has_relief = true
	_terrain.is_lava = false
	_terrain.frozen = false
	_terrain.ponds = []
	_terrain.min_h = _min_h
	_terrain.max_h = _max_h
	# vertex_attributes() feeds the arena ground shader's per-vertex noise band.
	_terrain.set("_noise", PbSimplex.new(13))

	_falls = _find_falls()
	_pack = PbData.world_pack("forest")
	_terrain.props = _scatter_props()


## The web water shader samples a 0..1 height texture and rescales with uMin/uRange;
## PbWorldView's own t_h is raw metres, so build the normalised copy the menu needs.
func _build_height_texture() -> void:
	var n := GRID + 1
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	var span := maxf(_max_h - _min_h, 0.0001)
	for gz in n:
		for gx in n:
			img.set_pixel(gx, gz, Color((_heights[gz * n + gx] - _min_h) / span, 0.0, 0.0, 1.0))
	_height_tex = ImageTexture.create_from_image(img)


func _shape(x: float, z: float) -> float:
	var i := _noise_a.get2(x * 0.09, z * 0.09)
	var a := _noise_b.get2(x * 0.035, z * 0.035) * 0.45 + i * 0.12
	a += _sstep(34.0, 58.0, _hypot2(x, z * 1.1)) * (5.0 + _noise_b.get2(x * 0.05, z * 0.05) * 3.0)

	var s := 0.2 + 0.8 * minf(_sstep(1.5, 5.0, _hypot2(x - WATER_LIP["x"], z - WATER_LIP["z"]))
		, _sstep(1.5, 5.0, _hypot2(x - FALL_B_TOP["x"], z - FALL_B_TOP["z"])))
	var c := (i * 1.4 + _noise_b.get2(x * 0.07 + 40.0, z * 0.07) * 2.6) * s

	var u := _mesa_lobe(x, z, c, MESA_A)
	var d := _mesa_lobe(x, z, c, MESA_B)
	a = maxf(a, MESA_A["h"] * u + a * (1.0 - u))
	a = maxf(a, MESA_B["h"] * d + a * (1.0 - d))
	var lc := _mesa_lobe(x, z, c, MESA_C)
	a = maxf(a, MESA_C["h"] * lc + a * (1.0 - lc))
	var ld := _mesa_lobe(x, z, c, MESA_D)
	var le := _mesa_lobe(x, z, c, MESA_E)
	a = maxf(a, maxf(MESA_D["h"] * ld, MESA_E["h"] * le))
	a = maxf(a, MESA_F["h"] * _mesa_lobe(x, z, c, MESA_F))

	var cut := _line_dist(x, z, Vector2(FALL_A["x"], FALL_A["z"]), Vector2(WATER_LIP["x"], WATER_LIP["z"] + 1.0))
	if u > 0.5:
		a -= (1.0 - _sstep(FALL_A["w"] * 0.45, FALL_A["w"], cut)) * 0.75 * _sstep(0.5, 0.95, u)

	var mid := _sstep(0.5, 0.95, d) * (1.0 - u)
	if mid > 0.0:
		var notch := 1.0 - _sstep(FALL_B["r"] * 0.55, FALL_B["r"],
			_hypot2(x - FALL_B["x"], z - FALL_B["z"]) + i * 0.25)
		var channel := 1.0 - _sstep(0.6, 1.3, _line_dist(x, z, Vector2(FALL_B["x"], FALL_B["z"]), Vector2(FALL_B_TOP["x"], FALL_B_TOP["z"] + 1.0)))
		a -= maxf(notch * 1.1, channel * 0.7) * mid

	var m := _hypot2((x - POND_X) / POND_RX, (z - POND_Z) / POND_RZ) + i * 0.08
	var h := _sstep(1.12, 0.62, m) * (1.0 - maxf(u, d))
	a = a * (1.0 - h) + (-2.3 + m * 0.6) * h
	return a


func _mesa_lobe(x: float, z: float, c: float, mesa: Dictionary) -> float:
	var r: float = mesa["r"]
	var d := _hypot2(x - mesa["x"], z - mesa["z"]) + c * minf(1.0, r / 10.0)
	return 1.0 - _sstep(r - 1.0, r + 0.8, d)


func _height(x: float, z: float) -> float:
	var fx := (x + WORLD * 0.5) / CELL
	var fz := (z + WORLD * 0.5) / CELL
	var gx := clampi(int(floor(fx)), 0, GRID - 1)
	var gz := clampi(int(floor(fz)), 0, GRID - 1)
	var tx := clampf(fx - gx, 0.0, 1.0)
	var tz := clampf(fz - gz, 0.0, 1.0)
	var n := GRID + 1
	var h00 := _heights[gz * n + gx]
	var h10 := _heights[gz * n + gx + 1]
	var h01 := _heights[(gz + 1) * n + gx]
	var h11 := _heights[(gz + 1) * n + gx + 1]
	var a := h00 * (1.0 - tx) + h10 * tx
	var b := h01 * (1.0 - tx) + h11 * tx
	return a * (1.0 - tz) + b * tz


func _in_pond(x: float, z: float, margin: float) -> bool:
	return _height(x, z) < WATER_LEVEL + margin


func _flat(x: float, z: float) -> bool:
	var h := _height(x, z)
	return absf(_height(x + 0.9, z) - h) < 0.6 and absf(_height(x, z + 0.9) - h) < 0.6 \
		and absf(_height(x - 0.9, z) - h) < 0.6 and absf(_height(x, z - 0.9) - h) < 0.6


func _find_falls() -> Array:
	var a := _ray_fall(Vector2(WATER_LIP["x"], WATER_LIP["z"] - 4.0),
		Vector2(WATER_LIP["x"], WATER_LIP["z"]), MESA_TOP - 0.6)
	var b := _ray_fall(Vector2(FALL_B["x"], FALL_B["z"] + FALL_B["r"] + 0.3),
		Vector2(FALL_B_TOP["x"], FALL_B_TOP["z"]), MESA_MID - 0.4)
	var out: Array = []
	out.append({"start": a, "x": a["x"], "z": a["z"], "dir": a["dir"], "top": MESA_TOP,
		"bottom": MESA_MID, "w": 2.2, "reach": 2.0,
		"hit": Vector2(a["x"] + sin(a["dir"]) * 2.0, a["z"] + cos(a["dir"]) * 2.0)})
	out.append({"start": b, "x": b["x"], "z": b["z"], "dir": b["dir"], "top": MESA_MID,
		"bottom": WATER_LEVEL, "w": 2.3, "reach": 2.0,
		"hit": Vector2(b["x"] + sin(b["dir"]) * 2.0, b["z"] + cos(b["dir"]) * 2.0)})
	return out


func _ray_fall(from: Vector2, to: Vector2, level: float) -> Dictionary:
	var dx := to.x - from.x
	var dz := to.y - from.y
	var length := sqrt(dx * dx + dz * dz)
	var t := 0.0
	while t < length + 8.0:
		var x := from.x + dx / length * t
		var z := from.y + dz / length * t
		if _height(x, z) < level:
			return {"x": x - dx / length * 0.25, "z": z - dz / length * 0.25,
				"dir": atan2(dx, dz)}
		t += 0.05
	return {"x": to.x, "z": to.y, "dir": atan2(dx, dz)}


func _scatter_props() -> Array:
	var props: Array = []
	var rng := PbJsRng.new(2026)
	var trees: Array = _pack.get("trees", [])
	var big: Array = _pack.get("big", [])
	var small: Array = _pack.get("small", [])
	var kinds_main: Array = ["tree0", "tree1", "tree2", "tree3", "tree4", "tree5"]

	var push_kind := func(name: String, x: float, z: float, s: float = -1.0) -> void:
		var kind := _find_kind(name, trees, big, small)
		if kind.is_empty():
			return
		if s < 0.0:
			s = rng.range_f(0.9, 1.15)
		props.append({"kind": kind, "x": x,
			"y": _height(x, z) - 0.08, "z": z, "flip": rng.chance(0.5), "s": s})

	var corridor := func(x: float, z: float) -> bool:
		var d := _line_dist(x, z, Vector2(CAM_POS.x, CAM_POS.z), Vector2(POND_X, POND_Z))
		var t := _line_t(x, z, Vector2(CAM_POS.x, CAM_POS.z), Vector2(POND_X, POND_Z))
		return d < 7.0 + t * 6.0

	var bad_spot := func(x: float, z: float) -> bool:
		return _line_dist(x, z, Vector2(FALL_A["x"], FALL_A["z"]),
				Vector2(_falls[0]["x"], _falls[0]["z"])) < 2.6 \
			or _dist2(x, z, FALL_B["x"], FALL_B["z"]) < FALL_B["r"] + 1.2 \
			or _line_dist(x, z, Vector2(FALL_B["x"], FALL_B["z"]),
				Vector2(_falls[1]["x"], _falls[1]["z"])) < 2.2

	var far_enough := func(x: float, z: float, n: float) -> bool:
		for p in props:
			if _dist2(x, z, p["x"], p["z"]) < n:
				return false
		return true

	var growlithe_x := 14.2
	var growlithe_z := -10.5
	var scatter := func(kinds: Array, count: int, mode: int, accept: Callable, min_dist: float) -> void:
		var budget := count * 8
		while budget > 0 and count > 0:
			budget -= 1
			var x := 0.0
			var z := 0.0
			match mode:
				0:
					var ang := rng.range_f(0.0, TAU)
					var rad := rng.range_f(19.0, 44.0)
					x = cos(ang) * rad + 4.0
					z = sin(ang) * rad - 6.0
				1:
					x = MESA_A["x"] + rng.range_f(-9.0, 9.0)
					z = MESA_A["z"] + rng.range_f(-9.0, 7.0)
				2:
					x = MESA_D["x"] + rng.range_f(-8.0, 8.0)
					z = MESA_D["z"] + rng.range_f(-8.0, 8.0)
				3:
					x = MESA_C["x"] + rng.range_f(-2.5, 2.5)
					z = MESA_C["z"] + rng.range_f(-2.5, 2.5)
				4:
					var ang := rng.range_f(0.0, TAU)
					var rad := rng.range_f(MESA_D["r"] + 0.8, MESA_E["r"] - 1.0)
					x = MESA_E["x"] + cos(ang) * rad
					z = MESA_E["z"] + sin(ang) * rad
				5:
					x = MESA_F["x"] + rng.range_f(-6.0, 6.0)
					z = MESA_F["z"] + rng.range_f(-6.0, 6.0)
				6:
					x = MESA_B["x"] + rng.range_f(-5.0, 5.0)
					z = MESA_B["z"] + rng.range_f(-5.0, 4.0)
				7:
					var ang := rng.range_f(0.0, TAU)
					var rad := rng.range_f(13.0, 30.0)
					x = cos(ang) * rad + 4.0
					z = sin(ang) * rad - 6.0
				8:
					var ang := rng.range_f(0.0, TAU)
					var rad := rng.range_f(1.05, 1.5)
					x = POND_X + cos(ang) * POND_RX * rad
					z = POND_Z + sin(ang) * POND_RZ * rad
				9:
					x = rng.range_f(-24.0, 30.0)
					z = rng.range_f(-22.0, 20.0)
			if not _flat(x, z) or _in_pond(x, z, 0.5) or bad_spot.call(x, z) or not accept.call(x, z):
				continue
			if not far_enough.call(x, z, min_dist):
				continue
			if _dist2(x, z, growlithe_x, growlithe_z) < 3.0:
				continue
			push_kind.call(rng.pick(kinds), x, z, -1.0)
			count -= 1

	scatter.call(kinds_main, 70, 0, func(x, z): return not corridor.call(x, z) and z < 16.0, 3.2)
	scatter.call(kinds_main, 10, 1, func(x, z):
		return _dist2(x, z, MESA_A["x"], MESA_A["z"]) < MESA_A["r"] - 1.5, 3.0)
	scatter.call(kinds_main, 7, 2, func(x, z):
		return _dist2(x, z, MESA_D["x"], MESA_D["z"]) < MESA_D["r"] - 1.5, 3.0)
	scatter.call(kinds_main, 2, 3, func(x, z):
		return _dist2(x, z, MESA_C["x"], MESA_C["z"]) < MESA_C["r"] - 1.2 \
			and _dist2(x, z, MESA_A["x"], MESA_A["z"]) > MESA_A["r"] + 1.0, 2.5)
	scatter.call(["bush", "berrybush", "fern", "tallgrass", "flowersA"], 10, 4,
		func(x, z):
			return z > -18.0 and _dist2(x, z, MESA_D["x"], MESA_D["z"]) > MESA_D["r"] + 0.8 \
				and _dist2(x, z, MESA_E["x"], MESA_E["z"]) < MESA_E["r"] - 1.0, 1.6)
	scatter.call(kinds_main, 4, 5, func(x, z):
		return _dist2(x, z, MESA_F["x"], MESA_F["z"]) < MESA_F["r"] - 1.5, 3.0)
	scatter.call(["bush", "berrybush", "fern", "flowersA", "tallgrass", "flowersB"], 9, 6,
		func(x, z):
			return _dist2(x, z, MESA_B["x"], MESA_B["z"]) < MESA_B["r"] - 1.0 \
				and _dist2(x, z, MESA_A["x"], MESA_A["z"]) > MESA_A["r"] + 0.8, 1.3)

	push_kind.call("tree4", -0.4, -6.8, 0.95)
	push_kind.call("tree1", -3.4, -4.6, 0.85)
	push_kind.call("tree4", 21.0, 9.0, 1.25)
	push_kind.call("tree0", 25.0, 3.0, 1.1)

	var fall_dir: float = _falls[1]["dir"]
	var around_fall := func(t: float, n: float) -> Vector2:
		return Vector2(_falls[1]["hit"].x + cos(fall_dir) * t - sin(fall_dir) * n,
			_falls[1]["hit"].y - sin(fall_dir) * t - cos(fall_dir) * n)
	var fixed_bits := [
		[around_fall.call(-2.6, 0.2), "boulder", 1.1],
		[around_fall.call(2.9, 0.4), "boulder", 1.0],
		[around_fall.call(3.9, -0.6), "rocks", 0.9],
		[Vector2(FALL_B["x"] - FALL_B["r"] - 0.6, FALL_B["z"] + 0.6), "boulder", 0.8],
		[Vector2(FALL_B["x"] + FALL_B["r"] + 0.5, FALL_B["z"] + 1.2), "rocks", 0.9],
		[Vector2(POND_X - POND_RX + 0.5, POND_Z + 2.5), "rocks", 1.0],
		[Vector2(POND_X + 4.0, POND_Z + POND_RZ + 0.3), "log", 1.0],
	]
	for item in fixed_bits:
		push_kind.call(item[1], item[0].x, item[0].y, item[2])

	scatter.call(["bush", "berrybush", "stump", "mushrooms", "boulder"], 22, 7,
		func(x, z): return not corridor.call(x, z), 2.4)
	scatter.call(["flowersA", "flowersB", "tallgrass", "fern"], 60, 8,
		func(x, z): return z > -4.0, 0.9)
	scatter.call(["tallgrass", "fern", "flowersA", "flowersB", "tallgrass", "fern",
		"flowersA", "sunflower"], 130, 9,
		func(x, z):
			return _dist2(x, z, CAM_POS.x, CAM_POS.z) > 13.0 and not corridor.call(x, z), 1.0)
	return props


func _find_kind(name: String, trees: Array, big: Array, small: Array) -> Dictionary:
	for bucket in [trees, big, small]:
		if bucket.is_empty():
			continue
		for kind in bucket:
			if str(kind.get("name", "")) == name:
				return kind
	return {}


# ---------------------------------------------------------------- world / view
func _build_view() -> void:
	_view = PbWorldView.new()
	_view.name = "World"
	add_child(_view)
	var biome := PbData.biome("forest")
	var palette := PbJson.as_dict(PbJson.as_dict(PbData.world_palettes().get("by_pack")).get("forest"))
	_view.setup(_terrain, biome, _pack, palette, PbData.world_fx())

	# The pond calls setSky(...,36,120,1.05,...) which the shared look expands to 54/162.
	_view.set_look({
		"top": SKY_TOP, "bottom": SKY_BOTTOM, "fog": FOG_COLOR,
		"near": 54.0, "far": 162.0, "light": 1.05, "sun": SUN_COLOR,
	})
	_view.blend_look(1.0)

	# The pond builds its own ground material (13.5 px grass grid, cliff strata measured
	# along the nearest mesa rim, wet zones round both falls), so swap in the menu variant.
	var mat := _view.terrain_mat
	mat.shader = load("res://src/ui/pb_menu_ground.gdshader") as Shader
	mat.set_shader_parameter("u_px", 20.0)
	# `loadPack()` overrides the material's initial uTexScale 3 with 4 once the forest ground
	# texture arrives, so the shipped scene tiles at 4.
	mat.set_shader_parameter("u_tex_scale", 4.0)
	mat.set_shader_parameter("u_grass_scale", 128.0 / 20.0)
	mat.set_shader_parameter("u_world", WORLD)
	mat.set_shader_parameter("u_shore_h", 0.5)
	mat.set_shader_parameter("u_detail", 0)
	mat.set_shader_parameter("u_sun_col",
		PbWorldView.color_from_int(SUN_COLOR).srgb_to_linear() * 1.08)
	mat.set_shader_parameter("u_shadow_col",
		PbWorldView.color_from_int(SHADOW_COLOR).srgb_to_linear() * 0.8)
	mat.set_shader_parameter("u_water", WATER_LEVEL)
	mat.set_shader_parameter("u_sun_dir", SUN_DIR)

	# `uFalls[2]` = (x, z, top, bottom); `uMesas[6]` follows Qf = [Kf, qf, Jf, Yf, Xf, Zf].
	mat.set_shader_parameter("u_fall1", Vector4(_falls[0]["x"], _falls[0]["z"],
		float(_falls[0]["top"]), float(_falls[0]["bottom"])))
	mat.set_shader_parameter("u_fall2", Vector4(_falls[1]["x"], _falls[1]["z"],
		float(_falls[1]["top"]), float(_falls[1]["bottom"])))
	var mesas: Array = [MESA_A, MESA_B, MESA_C, MESA_D, MESA_E, MESA_F]
	for i in mesas.size():
		mat.set_shader_parameter("u_mesa%d" % (i + 1),
			Vector3(mesas[i]["x"], mesas[i]["z"], mesas[i]["r"]))
	_view.prop_mat.set_shader_parameter("u_tint", PROP_TINT)

	# Replace the biome gradient sky with the web menu's pixel sky (clouds + sun + dither).
	_sky_mat = _view.sky_mat
	_sky_mat.shader = load("res://src/ui/pb_menu_sky.gdshader") as Shader
	_sky_mat.set_shader_parameter("u_top", PbWorldView.color_from_int(SKY_TOP).srgb_to_linear())
	_sky_mat.set_shader_parameter("u_bottom", PbWorldView.color_from_int(SKY_BOTTOM).srgb_to_linear())
	_sky_mat.set_shader_parameter("u_sun_dir", SUN_DIR)
	_sky_mat.set_shader_parameter("u_px", 4.0)
	_sky_mat.set_shader_parameter("u_cover", 0.0)
	_sky_mat.set_shader_parameter("u_cloud_tint", Color(1, 1, 1))
	_sky_mat.set_shader_parameter("u_time", 0.0)

	# A low directional light only feeds Sprite3D actors (the world shaders are unshaded).
	_sun = DirectionalLight3D.new()
	_sun.light_color = PbWorldView.color_from_int(SUN_COLOR)
	_sun.light_energy = 1.0
	_sun.rotation_degrees = Vector3(-52.0, 31.0, 0.0)
	add_child(_sun)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "MenuCamera"
	_cam.fov = 50.0
	_cam.near = 0.1
	_cam.far = 600.0
	_cam.position = CAM_POS
	add_child(_cam)
	_cam.look_at(LOOK_AT, Vector3.UP)
	_cam.current = true


func _water_material(level: float, max_depth: float, flow: Vector2, shore: float,
		hit: Variant) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/ui/pb_menu_water.gdshader")
	mat.set_shader_parameter("t_h", _height_tex)
	mat.set_shader_parameter("u_min", _min_h)
	mat.set_shader_parameter("u_range", _max_h - _min_h)
	mat.set_shader_parameter("u_level", level)
	mat.set_shader_parameter("u_max_depth", max_depth)
	mat.set_shader_parameter("u_flow", flow)
	mat.set_shader_parameter("u_shore", shore)
	mat.set_shader_parameter("u_hit", Vector3(hit.x, hit.y, 1.0) if hit != null else Vector3.ZERO)
	mat.set_shader_parameter("u_sky", PbWorldView.color_from_int(WATER_SKY).srgb_to_linear())
	mat.set_shader_parameter("u_fog_col", PbWorldView.color_from_int(FOG_COLOR).srgb_to_linear())
	mat.set_shader_parameter("u_fog_near", 54.0)
	mat.set_shader_parameter("u_fog_far", 162.0)
	return mat


func _build_water() -> void:
	# PbWorldView names the world-water root and its plane both "Water".
	var node := _view.get_node_or_null("Water/Water") as MeshInstance3D
	if node == null:
		return
	_water_mat = _water_material(WATER_LEVEL, 99.0, Vector2.ZERO, 1.0, _falls[1]["hit"])
	node.material_override = _water_mat
	node.position = Vector3.ZERO
	node.mesh = _pond_mesh(POND_X, POND_Z, POND_RX * 2.6, POND_RZ * 2.6, WATER_LEVEL)
	_water_mats.append(_water_mat)

	# Two shallow channels that carry the falls across the mesa tops (web buildWater()).
	var a := Vector2(_falls[0]["x"], _falls[0]["z"])
	var strip := _strip_mesh(Vector2(FALL_A["x"], FALL_A["z"]), Vector2(a.x, a.y),
		float(FALL_A["w"]) * 1.6, MESA_TOP)
	var m1 := _water_material(MESA_TOP, 0.9,
		Vector2(-(a.x - FALL_A["x"]), -(a.y - FALL_A["z"])).normalized() * 2.2, 0.0, null)
	_water_mats.append(m1)
	_add_mesh(node, "FallChannelHigh", strip, m1, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var b := Vector2(_falls[1]["x"], _falls[1]["z"])
	var from_b := Vector2(FALL_B["x"], FALL_B["z"] - FALL_B["r"] - 0.6)
	var strip2 := _strip_mesh(from_b, Vector2(b.x, b.y), float(FALL_B["r"]) * 2.4, MESA_MID)
	var m2 := _water_material(MESA_MID, 0.9,
		Vector2(-(b.x - from_b.x), -(b.y - from_b.y)).normalized() * 2.2,
		0.0, _falls[1]["hit"])
	_water_mats.append(m2)
	_add_mesh(node, "FallChannelMid", strip2, m2, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _build_falls() -> void:
	var sh: Shader = load("res://src/ui/pb_menu_falls.gdshader")
	for idx in _falls.size():
		var fall: Dictionary = _falls[idx]
		var height: float = float(fall["top"]) - float(fall["bottom"])
		for back in [true, false]:
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("u_time", 0.0)
			mat.set_shader_parameter("u_size", Vector2(float(fall["w"]), height))
			mat.set_shader_parameter("u_back", 1.0 if back else 0.0)
			mat.set_shader_parameter("u_fog_col", PbWorldView.color_from_int(FOG_COLOR).srgb_to_linear())
			mat.set_shader_parameter("u_fog_near", 54.0)
			mat.set_shader_parameter("u_fog_far", 162.0)
			mat.render_priority = 3 if back else 4
			var inst := MeshInstance3D.new()
			inst.name = "Fall%d%s" % [idx, "Back" if back else "Front"]
			inst.mesh = _fall_mesh(float(fall["w"]), height, float(fall["reach"]), back)
			inst.material_override = mat
			inst.position = Vector3(fall["x"], float(fall["bottom"]) + height * 0.5, fall["z"])
			inst.rotation.y = float(fall["dir"])
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)


func _build_pads() -> void:
	var rng := PbJsRng.new(4242)
	var hit: Vector2 = _falls[1]["hit"]
	var data: Array = []
	for n in 60:
		if data.size() >= 16:
			break
		var ang := rng.range_f(0.0, PI * 2.0)
		var rad := sqrt(rng.next()) * 0.85
		var x := POND_X + cos(ang) * POND_RX * rad
		var z := POND_Z + sin(ang) * POND_RZ * rad
		if _height(x, z) > -0.95 or _dist2(x, z, hit.x, hit.y) < 4.5:
			continue
		var close := false
		for p in data:
			if _dist2(x, z, p["x"], p["z"]) < 1.4:
				close = true
				break
		if close:
			continue
		data.append({"x": x, "z": z, "r": rng.range_f(0.0, 6.28),
			"s": rng.range_f(0.45, 0.8), "ph": rng.range_f(0.0, 6.28)})

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = PbWorldView.color_from_int(4173388).srgb_to_linear()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := _pad_mesh(1.0, 14, 0.35, TAU - 0.7)
	for p in data:
		var inst := MeshInstance3D.new()
		inst.name = "Pad"
		inst.mesh = disc
		inst.material_override = mat
		inst.scale = Vector3(p["s"], 1.0, p["s"])
		inst.position = Vector3(p["x"], -0.57, p["z"])
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		p["node"] = inst
		_pads.append(p)


func _build_actors() -> void:
	var add_wander := func(id: int, x: float, z: float, speed: float, radius: float) -> void:
		_actors.append({
			"id": id, "x": x, "z": z, "a": _rng.randf() * TAU, "t": _rng.randf() * 5.0,
			"mode": "wander", "wait": _rng.randf() * 3.0, "speed": speed,
			"home": Vector2(x, z), "range": radius, "facing": 1, "anim": "",
			"frame_t": -1.0, "node": _make_billboard(id, 1.0),
		})
	add_wander.call(4, -1.6, -4.8, 1.3, 1.4)
	add_wander.call(43, -3.0, 2.5, 0.9, 2.5)
	add_wander.call(60, -2.0, 5.5, 1.0, 2.2)
	add_wander.call(54, POND_X - 4.0, POND_Z + 6.8, 1.1, 2.2)
	add_wander.call(25, 4.5, 8.0, 2.2, 3.0)
	add_wander.call(7, POND_X + 3.0, POND_Z + 7.0, 1.2, 2.5)
	add_wander.call(79, POND_X + 7.5, POND_Z + 6.0, 0.8, 2.2)
	add_wander.call(133, 15.0, 6.5, 1.9, 3.0)
	add_wander.call(1, 18.0, 1.5, 1.0, 3.0)

	_actors.append({"id": 118, "x": 1.0, "z": POND_Z + 3.0, "a": 0.0, "t": 0.0,
		"mode": "swim", "cx": 0.6, "cz": POND_Z + 3.2, "r": 1.6, "speed": 1.0, "s": 1.0,
		"facing": 1, "anim": "", "frame_t": -1.0, "node": _make_billboard(118, 1.0)})
	_actors.append({"id": 131, "x": POND_X, "z": POND_Z, "a": 0.0, "t": 0.0,
		"mode": "swim", "cx": POND_X - 0.3, "cz": POND_Z + 1.2, "r": 3.6,
		"speed": 0.55, "s": 1.55, "facing": 1, "anim": "", "frame_t": -1.0,
		"node": _make_billboard(131, 1.55)})
	_actors.append({"id": 12, "x": POND_X, "z": POND_Z, "a": 0.0, "t": 0.0,
		"mode": "fly", "cx": POND_X + 1.0, "cz": POND_Z + 2.0, "r": 4.5, "y": 3.2,
		"facing": 1, "anim": "", "frame_t": -1.0, "node": _make_billboard(12, 1.0)})
	_actors.append({"id": 49, "x": 0.0, "z": 0.0, "a": 0.0, "t": 7.0,
		"mode": "fly", "cx": -1.0, "cz": 0.0, "r": 4.0, "y": 2.6,
		"facing": 1, "anim": "", "frame_t": -1.0, "node": _make_billboard(49, 1.0)})

	for next_time in [1.5, 3.8, 6.2]:
		_actors.append({"id": 129, "x": POND_X, "z": POND_Z, "a": 0.0, "t": 0.0,
			"mode": "jump", "next": next_time, "jt": null, "from": null, "to": null,
			"facing": 1, "anim": "", "frame_t": -1.0, "node": _make_billboard(129, 1.0)})

	_actors.append({"id": 58, "x": 14.2, "z": -10.5, "a": 0.0, "t": 3.0,
		"mode": "perch", "facing": 1, "anim": "", "frame_t": -1.0,
		"node": _make_billboard(58, 1.35)})

	for id in [4, 43, 60, 54, 25, 7, 79, 133, 1, 118, 131, 12, 49, 129, 58]:
		PbVisuals.sheet(id)
	for actor in _actors:
		if str(actor["mode"]) == "jump":
			(actor["node"] as MeshInstance3D).visible = false


func _make_billboard(id: int, _scale: float) -> MeshInstance3D:
	# The web sprites are 1-unit quads scaled per-frame, so normalise the PMD quad
	# to one unit of *content* height; `_place_actor` applies the actor scale.
	var layout := PbVisuals.billboard_layout(id, "walk", 1.0)
	var content := maxf(float(layout.get("content_height", 1.0)), 0.001)
	var k := 1.0 / content
	var quad := QuadMesh.new()
	quad.size = (layout.get("size", Vector2(1, 1)) as Vector2) * k
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.render_priority = 6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	PbVisuals.apply_frame_texture(mat, PbVisuals.idle_frame_texture(id))
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.set_meta("lift", float(layout.get("lift", 0.0)) * k)
	add_child(inst)
	return inst


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PbWorldView.color_from_int(FOG_COLOR)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Emissive motes and waterfall splash, kept cheap (CPUParticles3D).
	for fall in _falls:
		var hit: Vector2 = fall["hit"]
		var bottom := float(fall["bottom"])
		_add_particles(hit, 40, 0.9, 5.5, 2.0, Color(0.85, 0.97, 1.0), false, bottom + 0.05)
		_add_particles(hit, 14, 2.4, 2.0, 8.0, Color(0.95, 0.99, 1.0), true, bottom)
	var motes := CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 70
	motes.lifetime = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(22.0, 4.0, 14.0)
	motes.position = Vector3(3.0, 3.0, -6.0)
	motes.direction = Vector3(1.0, 0.2, 0.0)
	motes.spread = 60.0
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.35
	motes.gravity = Vector3(0.0, 0.02, 0.0)
	motes.scale_amount_min = 0.04
	motes.scale_amount_max = 0.09
	motes.mesh = _point_quad(Color(1.0, 0.96, 0.66))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)


func _add_particles(pos: Vector2, amount: int, lifetime: float, velocity: float,
		size: float, color: Color, mist: bool = false, at_y: float = WATER_LEVEL + 0.1) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 if mist else 0.7
	p.position = Vector3(pos.x, at_y, pos.y)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 55.0 if not mist else 30.0
	p.initial_velocity_min = velocity * 0.5
	p.initial_velocity_max = velocity
	p.gravity = Vector3(0.0, -7.0 if not mist else -0.2, 0.0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color = color
	p.mesh = _point_quad(color, mist)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


func _point_quad(color: Color, soft: bool = false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	return q


# -------------------------------------------------------------------- helpers
func _pad_mesh(radius: float, segments: int, start: float, span: float) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	for i in segments + 1:
		var a := start + span * float(i) / float(segments)
		verts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	var idx := PackedInt32Array()
	for i in segments:
		idx.append_array(PackedInt32Array([0, i + 1, i + 2]))
	return _mesh(verts, uvs, idx)


func _pond_mesh(cx: float, cz: float, sx: float, sz: float, y: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(cx - sx * 0.5, y, cz - sz * 0.5),
		Vector3(cx + sx * 0.5, y, cz - sz * 0.5),
		Vector3(cx + sx * 0.5, y, cz + sz * 0.5),
		Vector3(cx - sx * 0.5, y, cz + sz * 0.5),
	])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	return _mesh(verts, uvs, idx)


func _strip_mesh(from: Vector2, to: Vector2, width: float, y: float) -> ArrayMesh:
	var dir := (to - from)
	var length := dir.length()
	var d := dir / maxf(length, 0.001)
	var n := Vector2(-d.y, d.x) * (width * 0.5)
	var a := from + n
	var b := to + n
	var c := to - n
	var e := from - n
	var verts := PackedVector3Array([Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
		Vector3(c.x, y, c.y), Vector3(e.x, y, e.y)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	return _mesh(verts, uvs, PackedInt32Array([0, 1, 2, 0, 2, 3]))


func _fall_mesh(width: float, height: float, reach: float, back: bool) -> ArrayMesh:
	var cols := 6
	var rows := 40
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		var v := float(j) / float(rows)
		var y := -height * 0.5 + v * height
		var a := clampf(1.0 - (y + height * 0.5) / height, 0.0, 1.0)
		var z := reach * sqrt(a) - (0.14 if back else 0.0)
		var scale := (1.0 + a * 0.22) * (0.94 if back else 1.0)
		for i in cols + 1:
			var u := float(i) / float(cols)
			verts.append(Vector3((u - 0.5) * width * scale, y, z))
			uvs.append(Vector2(u, v))
	for j in rows:
		for i in cols:
			var k := j * (cols + 1) + i
			idx.append_array(PackedInt32Array([k, k + 1, k + cols + 2, k, k + cols + 2, k + cols + 1]))
	return _mesh(verts, uvs, idx)


func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh(parent: Node, name: String, mesh: Mesh, mat: Material,
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var inst := MeshInstance3D.new()
	inst.name = name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = shadow
	parent.add_child(inst)


func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _hypot2(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


func _dist2(x: float, z: float, cx: float, cz: float) -> float:
	return _hypot2(x - cx, z - cz)


## Line projection: distance and distance along the line (web `lp`).
func _line_dist(x: float, z: float, a: Vector2, b: Vector2) -> float:
	var dx := b.x - a.x
	var dz := b.y - a.y
	var l2 := dx * dx + dz * dz
	var t := 0.0 if l2 == 0.0 else clampf(((x - a.x) * dx + (z - a.y) * dz) / l2, 0.0, 1.0)
	var px := a.x + dx * t
	var pz := a.y + dz * t
	return _hypot2(x - px, z - pz)


func _line_t(x: float, z: float, a: Vector2, b: Vector2) -> float:
	var dx := b.x - a.x
	var dz := b.y - a.y
	var l2 := dx * dx + dz * dz
	return 0.0 if l2 == 0.0 else clampf(((x - a.x) * dx + (z - a.y) * dz) / l2, 0.0, 1.0)


func _walkable(x: float, z: float) -> bool:
	if x < -6.0 or x > 21.0 or z < -6.0 or z > 9.5:
		return false
	var h := _height(x, z)
	if h < -0.25 or h > 1.6:
		return false
	if absf(_height(x + 0.8, z) - h) > 0.45 or absf(_height(x, z + 0.8) - h) > 0.45:
		return false
	return _dist2(x, z, CAM_POS.x, CAM_POS.z) > 14.0


func _pick_target(actor: Dictionary) -> void:
	for attempt in 30:
		var ang := _rng.randf() * TAU
		var rad := 2.0 + _rng.randf() * 7.0
		var x: float = actor["home"].x + cos(ang) * rad
		var z: float = actor["home"].y + sin(ang) * rad
		if _dist2(x, z, actor["home"].x, actor["home"].y) > float(actor["range"]):
			continue
		if not _walkable(x, z):
			continue
		var clash := false
		for other in _actors:
			if other == actor or str(other.get("mode", "")) != "wander":
				continue
			if _dist2(x, z, other["x"], other["z"]) < 1.6:
				clash = true
				break
		if clash:
			continue
		actor["tx"] = x
		actor["tz"] = z
		return
	actor["tx"] = actor["x"]
	actor["tz"] = actor["z"]


# --------------------------------------------------------------------- runtime
func _process(delta: float) -> void:
	_t += delta
	var r := sin(_t * 0.13) * 1.6
	var rise := sin(_t * 0.21) * 0.25
	_cam.position = Vector3(CAM_POS.x + r, CAM_POS.y + rise, CAM_POS.z - absf(r) * 0.2)
	_cam.look_at(Vector3(LOOK_AT.x + r * 0.35, LOOK_AT.y, LOOK_AT.z), Vector3.UP)
	_cam.fov = 50.0
	_view.tick(delta, Vector3(999, -999, 999), _cam)
	_sky_mat.set_shader_parameter("u_time", _t)
	for mat in _water_mats:
		mat.set_shader_parameter("u_time", _t)
		mat.set_shader_parameter("u_cam", _cam.global_position)
		mat.set_shader_parameter("u_cam_fwd", -_cam.global_transform.basis.z.normalized())
	for child in get_children():
		if child is MeshInstance3D and str(child.name).begins_with("Fall"):
			(child.material_override as ShaderMaterial).set_shader_parameter("u_time", _t)
	_update_pads()
	_update_actors(delta)


func _update_pads() -> void:
	for p in _pads:
		var node: MeshInstance3D = p["node"]
		var a: float = p["r"] + sin(_t * 0.3 + p["ph"]) * 0.15
		var bob := sin(_t * 1.3 + p["ph"]) * 0.015
		node.position = Vector3(p["x"] + sin(_t * 0.25 + p["ph"]) * 0.12, -0.57 + bob, p["z"])
		node.rotation.y = a


func _update_actors(delta: float) -> void:
	for actor in _actors:
		match str(actor["mode"]):
			"wander":
				_update_wander(actor, delta)
			"perch":
				_update_perch(actor, delta)
			"swim":
				_update_swim(actor, delta)
			"fly":
				_update_fly(actor, delta)
			"jump":
				_update_jump(actor, delta)


func _update_wander(actor: Dictionary, delta: float) -> void:
	actor["t"] += delta
	var moving := false
	if float(actor["wait"]) > 0.0:
		actor["wait"] -= delta
		if floorf(float(actor["t"]) / 2.5) != floorf((float(actor["t"]) - delta) / 2.5):
			actor["a"] += (_rng.randf() - 0.5) * 2.6
		if float(actor["wait"]) <= 0.0:
			_pick_target(actor)
	else:
		var dx: float = float(actor.get("tx", actor["x"])) - float(actor["x"])
		var dz: float = float(actor.get("tz", actor["z"])) - float(actor["z"])
		var dist := sqrt(dx * dx + dz * dz)
		var step := float(actor["speed"]) * delta
		if dist <= step:
			actor["x"] = actor.get("tx", actor["x"])
			actor["z"] = actor.get("tz", actor["z"])
			actor["wait"] = 1.2 + _rng.randf() * 4.0
		else:
			var nx := float(actor["x"]) + dx / dist * step
			var nz := float(actor["z"]) + dz / dist * step
			if _walkable(nx, nz) or not _walkable(float(actor["x"]), float(actor["z"])):
				actor["x"] = nx
				actor["z"] = nz
				actor["a"] = atan2(dz, dx)
				moving = true
			else:
				actor["wait"] = 0.4
	var ground := _height(actor["x"], actor["z"])
	var bob := absf(sin(float(actor["t"]) * 9.0)) * 0.12 if moving and float(actor["speed"]) > 1.8 else 0.0
	var facing := int(actor["facing"])
	if moving:
		facing = 1 if cos(float(actor["a"])) >= 0.0 else -1
	actor["facing"] = facing
	_place_actor(actor, float(actor["x"]), ground + bob, float(actor["z"]),
		"walk" if moving else "idle", facing)
	_update_shadow(actor, Vector3(actor["x"], ground + 0.04, actor["z"]), 1.1)


func _update_perch(actor: Dictionary, delta: float) -> void:
	actor["t"] += delta
	var turn := 0
	if sin(float(actor["t"]) * 0.23 + float(actor["x"])) > 0.8:
		turn = int(signf(sin(float(actor["t"]) * 0.05 + float(actor["z"]))))
	var facing: int = actor["facing"]
	if turn != 0:
		facing = turn
	actor["facing"] = facing
	var ground := _height(actor["x"], actor["z"])
	_place_actor(actor, float(actor["x"]), ground, float(actor["z"]), "idle", facing, 1.35)
	_update_shadow(actor, Vector3(actor["x"], ground + 0.04, actor["z"]), 1.2)


func _update_swim(actor: Dictionary, delta: float) -> void:
	actor["t"] += delta
	var speed: float = float(actor.get("speed", 1.0))
	var n := float(actor["t"]) * 0.18 * speed
	var s: float = float(actor.get("s", 1.0))
	var x: float = float(actor["cx"]) + cos(n) * float(actor["r"])
	var z: float = float(actor["cz"]) + sin(n) * float(actor["r"]) * 0.6
	actor["x"] = x
	actor["z"] = z
	var facing := 1 if -sin(n) >= 0.0 else -1
	actor["facing"] = facing
	var y := -0.72 - (s - 1.0) * 0.4 + sin(float(actor["t"]) * 2.0 / s) * 0.05
	_place_actor(actor, x, y, z, "walk", facing, s)


func _update_fly(actor: Dictionary, delta: float) -> void:
	actor["t"] += delta
	var n := float(actor["t"]) * 0.35
	var x: float = float(actor["cx"]) + sin(n) * float(actor["r"])
	var z: float = float(actor["cz"]) + sin(n * 2.0) * float(actor["r"]) * 0.45
	var under := _height(x, z)
	var y := (WATER_LEVEL + float(actor["y"])) if under < WATER_LEVEL else under + float(actor["y"])
	var facing := 1 if cos(n) >= 0.0 else -1
	actor["facing"] = facing
	_place_actor(actor, x, y + sin(float(actor["t"]) * 3.0) * 0.25, z, "idle", facing, 0.9)
	_update_shadow(actor, Vector3(x, maxf(WATER_LEVEL, under) + 0.04, z), 0.7)


func _update_jump(actor: Dictionary, delta: float) -> void:
	actor["t"] += delta
	actor["next"] -= delta
	if actor["jt"] == null and float(actor["next"]) <= 0.0:
		for attempt in 20:
			var ang := _rng.randf() * TAU
			var rad := _rng.randf() * 0.7
			var x := POND_X - 1.0 + cos(ang) * POND_RX * rad
			var z := POND_Z + 1.5 + sin(ang) * POND_RZ * rad * 0.6
			if _height(x, z) < -1.2:
				actor["from"] = Vector2(x, z)
				actor["to"] = Vector2(x + (_rng.randf() - 0.5) * 3.0,
					z + (_rng.randf() - 0.5) * 1.5)
				break
		if actor["from"] != null:
			actor["jt"] = 0.0
		actor["next"] = 4.0 + _rng.randf() * 6.0
	if actor["jt"] != null and actor["from"] != null and actor["to"] != null:
		actor["jt"] += delta / 1.1
		var n := minf(1.0, float(actor["jt"]))
		var x: float = actor["from"].x + (actor["to"].x - actor["from"].x) * n
		var z: float = actor["from"].y + (actor["to"].y - actor["from"].y) * n
		var y := -1.2 + sin(n * PI) * 3.2
		var facing := 1 if actor["to"].x - actor["from"].x >= 0.0 else -1
		actor["facing"] = facing
		_place_actor(actor, x, y, z, "hurt", facing, 1.0)
		(actor["node"] as MeshInstance3D).visible = true
		_update_shadow(actor, Vector3(x, WATER_LEVEL + 0.02, z), 0.4)
		if n >= 1.0:
			actor["jt"] = null
			actor["from"] = null
			actor["to"] = null
	else:
		# The web only draws the Magikarp while it is airborne.
		(actor["node"] as MeshInstance3D).visible = false
		var shadow := actor.get("shadow") as MeshInstance3D
		if shadow != null:
			shadow.visible = false


func _place_actor(actor: Dictionary, x: float, y: float, z: float, anim: String,
		facing: int, scale: float = 1.0) -> void:
	var node: MeshInstance3D = actor["node"]
	var lift: float = float(node.get_meta("lift", 0.0)) * scale
	node.position = Vector3(x, y + lift, z)
	node.scale = Vector3(scale, scale, scale)
	if actor["anim"] != anim or float(actor["t"]) - float(actor["frame_t"]) >= 0.083:
		actor["anim"] = anim
		actor["frame_t"] = actor["t"]
		var mat := node.material_override as StandardMaterial3D
		var tex := PbVisuals.frame_texture(int(actor["id"]), anim, float(actor["t"]), facing)
		if tex != null:
			PbVisuals.apply_frame_texture(mat, tex)


func _update_shadow(actor: Dictionary, pos: Vector3, size: float) -> void:
	var shadow: MeshInstance3D = actor.get("shadow")
	if shadow == null:
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 0.65)
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADOW_SHADER
		mat.shader = sh
		mat.render_priority = 1
		shadow = MeshInstance3D.new()
		shadow.mesh = q
		shadow.material_override = mat
		shadow.rotation_degrees = Vector3(-90, 0, 0)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadow)
		actor["shadow"] = shadow
	shadow.position = pos
	shadow.scale = Vector3(size, 1.0, size * 0.65)
	shadow.visible = true
