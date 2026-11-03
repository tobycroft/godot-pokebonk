class_name PbWorldView
extends Node3D
## Renders a PbTerrain the way the web client does: a toon height-field mesh, atlas prop
## billboards with wind sway and baked ground shadows, water/ice/lava, and the biome's
## sky/fog/sun "look".
##
## Everything visual is driven by the tables recovered from the offline mirror
## (data/pb/world_*.json) plus the shader ports in src/ui/pb_*.gdshader, so the arena reads
## like the reference instead of a flat tiled plane.

const WATER_SHADER := "res://src/ui/pb_water.gdshader"
const TERRAIN_SHADER := "res://src/ui/pb_terrain.gdshader"
const PROPS_SHADER := "res://src/ui/pb_props.gdshader"

## The reference draws prop shadows with a tiny inline material; kept here as source code.
const SHADOW_SHADER := """
shader_type spatial;
// Prop shadows: flat ellipses just above the ground (the reference draws these as instanced
// quads with no depth write, so they never fight the height field).
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.08, 0.06, 0.2);
	ALPHA = smoothstep(1.0, 0.25, d) * 0.32;
}
"""

## Sky: the two-tone vertical gradient the client composites behind the world. The dome is
## authored in world space and centred on the origin, so plain VERTEX is enough.
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;
uniform vec3 u_top;
uniform vec3 u_bottom;
varying float v_h;
void vertex() {
	// The dome geometry is placed around the origin; world height comes straight from VERTEX.
	v_h = clamp((VERTEX.y + 20.0) / 260.0, 0.0, 1.0);
}
void fragment() {
	ALBEDO = mix(u_bottom, u_top, pow(v_h, 0.85));
}
"""


var terrain: PbTerrain
var biome: Dictionary = {}
var pack: Dictionary = {}
var palette: Dictionary = {}
var fx: Dictionary = {}

var terrain_mat: ShaderMaterial
var prop_mat: ShaderMaterial
var water_mat: ShaderMaterial
var sky_mat: ShaderMaterial

var _mesh_root: Node3D
var _water_root: Node3D
var _height_tex: ImageTexture
var _shade_tex: ImageTexture
var _look := {}
var _look_target := {}
var _time := 0.0
var _wind := 1.0


## Build the world for `t`. `biome`, `pack`, `palette` and `fx` come from PbData.
func setup(t: PbTerrain, biome_dict: Dictionary, pack_dict: Dictionary,
		palette_dict: Dictionary, fx_dict: Dictionary) -> void:
	terrain = t
	biome = biome_dict
	pack = pack_dict
	palette = palette_dict
	fx = fx_dict
	_mesh_root = Node3D.new()
	_mesh_root.name = "Terrain"
	add_child(_mesh_root)
	_water_root = Node3D.new()
	_water_root.name = "Water"
	add_child(_water_root)
	_build_height_texture()
	_build_shade_texture()
	_build_terrain_mesh()
	_build_props()
	_build_water()
	_build_sky()
	# Neutral starting look: the biome's own sky/fog/lights.
	_look = _look_from_biome()
	_look_target = _look.duplicate()
	apply_look()


# ------------------------------------------------------------------- textures
func _build_height_texture() -> void:
	var n := terrain.res + 1
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	var h := terrain.heights
	for gz in n:
		for gx in n:
			img.set_pixel(gx, gz, Color(h[gz * n + gx], 0, 0, 1))
	_height_tex = ImageTexture.create_from_image(img)


func _build_shade_texture() -> void:
	var size := PbTerrain.js_roundf(terrain.world * 2.0)
	var mask := terrain.shade_mask(terrain.props)
	var img := Image.create(size, size, false, Image.FORMAT_R8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, Color(float(mask[y * size + x]) / 255.0, 0, 0, 1))
	_shade_tex = ImageTexture.create_from_image(img)


func _env_texture(path: String, fallback: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	push_warning("WorldView: texture missing %s" % path)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(fallback)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------- terrain mesh
func _build_terrain_mesh() -> void:
	var n := terrain.res + 1
	var count := n * n
	var half := terrain.world / 2.0
	var attrs := terrain.vertex_attributes()
	var verts := PackedVector3Array()
	verts.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var uv2 := PackedVector2Array()
	uv2.resize(count)
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
	var uv := PackedVector2Array()
	uv.resize(count)
	var cells := (n - 1) * (n - 1) * 6
	var indices := PackedInt32Array()
	indices.resize(cells)
	for gz in n:
		for gx in n:
			var i := gz * n + gx
			verts[i] = Vector3(float(gx) * terrain.cell - half, terrain.heights[i], float(gz) * terrain.cell - half)
			uv2[i] = Vector2(attrs["path"][i], attrs["var"][i])
			tangents[i * 4] = attrs["cliff_max"][i]
			tangents[i * 4 + 1] = attrs["cliff_min"][i]
			tangents[i * 4 + 2] = 0.0
			tangents[i * 4 + 3] = 0.0
			uv[i] = Vector2.ZERO
	# Normals: accumulate face normals over shared vertices, like computeVertexNormals().
	var accum := PackedVector3Array()
	accum.resize(count)
	var w := 0
	for gz in terrain.res:
		for gx in terrain.res:
			var a := gz * n + gx
			var b := a + 1
			var c := a + n
			var d := c + 1
			var p0 := verts[a]
			var p1 := verts[b]
			var p2 := verts[c]
			var p3 := verts[d]
			# Two triangles per cell; the winding matches the reference plane (-90 deg X).
			var n1 := (p2 - p0).cross(p1 - p0)
			var n2 := (p1 - p3).cross(p2 - p3)
			for idxv in [a, b, c]:
				accum[idxv] += n1
			for idxv in [b, c, d]:
				accum[idxv] += n2
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = c
			indices[w + 4] = b
			indices[w + 5] = d
			w += 6
	for i in count:
		var v := accum[i]
		if v.length_squared() <= 0.0:
			v = Vector3.UP
		normals[i] = v.normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = "Ground"
	inst.mesh = mesh
	inst.material_override = _terrain_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_root.add_child(inst)


## Godot's Color has no from_hex(); the tables store packed 24-bit sRGB ints, and the shaders
## work in linear space (three.js did the same before its colorspace_fragment pass).
static func color_from_int(value: int) -> Color:
	var col := Color()
	col.r8 = (value >> 16) & 0xFF
	col.g8 = (value >> 8) & 0xFF
	col.b8 = value & 0xFF
	col.a = 1.0
	return col


func _hex_color(value: Variant, fallback: int = 0xffffff) -> Color:
	return color_from_int(int(PbJson.as_int(value, fallback))).srgb_to_linear()


func _detail_index() -> int:
	match String(palette.get("ground", "")):
		"sand":
			return 1
		"snow":
			return 2
		"beach":
			return 3
	return 0


func _terrain_material() -> ShaderMaterial:
	var shader := load(TERRAIN_SHADER) as Shader
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = shader
	var biome_id := String(biome.get("id", "forest"))
	var light := PbJson.as_float(biome.get("light"), 1.0)
	var block: Array = PbJson.as_array(palette.get("block"))
	var shore: Array = PbJson.as_array(palette.get("shore"))
	var u := {
		"t_ground": _env_texture("res://assets/env/%s/ground.png" % biome_id, Color(0.4, 0.5, 0.4)),
		"t_path": _env_texture("res://assets/env/%s/path.png" % biome_id, Color(0.6, 0.55, 0.45)),
		"t_rock": _env_texture("res://assets/env/%s/cliff.png" % biome_id, Color(0.45, 0.45, 0.5)),
		"t_sand": _env_texture("res://assets/env/%s/path.png" % biome_id, Color(0.9, 0.85, 0.7)),
		"t_shade": _shade_tex,
		"u_ra": _hex_triple(palette.get("a")),
		"u_rb": _hex_triple(palette.get("b")),
		"u_rl": _hex_triple(palette.get("light")),
		"u_rd": _hex_triple(palette.get("dark")),
		"u_rk": _hex_triple(palette.get("ink")),
		"u_ma": _hex_triple(palette.get("mossA")),
		"u_mb": _hex_triple(palette.get("mossB")),
		"u_band": _hex_triple(palette.get("band")),
		"u_moss": PbJson.as_float(palette.get("moss"), 0.64),
		"u_block_a": PbJson.as_float(block[0], 0.9) if block.size() > 0 else 0.9,
		"u_block_b": PbJson.as_float(block[1], 1.5) if block.size() > 1 else 1.5,
		"u_band_on": 1.0 if palette.has("band") else 0.0,
		"u_has_shore": 1.0 if shore.size() >= 3 else 0.0,
		"u_detail": _detail_index(),
		"u_toon": 1 if not palette.is_empty() else 0,
		"u_no_shore": 1 if terrain.frozen else 0,
		"u_world": terrain.world,
		"u_px": PbTerrain.PIXELS_PER_UNIT,
		"u_tex_scale": 4.0,
		"u_grass_scale": 128.0 / PbTerrain.PIXELS_PER_UNIT,
		"u_water": terrain.water_level if terrain.has_water else -999.0,
		"u_lava": 1.0 if terrain.is_lava else 0.0,
		"u_shore_h": 1.2 if (biome_id == "coast") else 0.6,
		"u_shore_col": Color(shore[0], shore[1], shore[2]) if shore.size() >= 3 else Color(0.9, 0.85, 0.7),
		"u_sun_col": _hex_color(biome.get("sun")) * (1.05 * light),
		"u_shadow_col": _shadow_tint(biome_id) * (0.72 * light + 0.08),
		"u_fog_col": _hex_color(biome.get("fog")),
		"u_fog_near": PbJson.as_float(biome.get("fogNear"), 45.0),
		"u_fog_far": PbJson.as_float(biome.get("fogFar"), 170.0),
		"u_sun_dir": Vector3(0.45, 0.8, 0.35),
	}
	for key in u:
		terrain_mat.set_shader_parameter(key, u[key])
	return terrain_mat


## Shadow colour: the reference hard-codes volcano/graveyard tints and a neutral otherwise.
func _shadow_tint(biome_id: String) -> Color:
	var hex := 8030408
	if biome_id == "volcano":
		hex = 8011872
	elif biome_id == "graveyard":
		hex = 5917322
	return color_from_int(hex).srgb_to_linear()


## Palette entries ship as [r,g,b] triples in the 0..1 sRGB range.
func _hex_triple(value: Variant) -> Vector3:
	var arr := PbJson.as_array(value)
	if arr.size() < 3:
		return Vector3(0.5, 0.5, 0.5)
	return Vector3(PbJson.as_float(arr[0], 0.5), PbJson.as_float(arr[1], 0.5), PbJson.as_float(arr[2], 0.5))


# ------------------------------------------------------------------- props
func _build_props() -> void:
	var atlas: Dictionary = PbJson.as_dict(pack.get("atlas"))
	var sprites: Dictionary = PbJson.as_dict(atlas.get("sprites"))
	var atlas_w := PbJson.as_float(atlas.get("w"), 2048.0)
	var atlas_h := PbJson.as_float(atlas.get("h"), 128.0)
	var biome_id := String(biome.get("id", "forest"))
	var tex := _env_texture("res://assets/env/%s/atlas.png" % biome_id, Color(1, 1, 1, 0))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var per_uv2 := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var shadow_verts := PackedVector3Array()
	var shadow_uvs := PackedVector2Array()
	var shadow_indices := PackedInt32Array()
	var light := PbJson.as_float(biome.get("light"), 1.0)
	for p in terrain.props:
		var kind: Dictionary = p["kind"]
		var name := String(kind.get("name", ""))
		if kind.has("model"):
			continue          # real .glb props are placed by _build_models()
		var rect: Dictionary = PbJson.as_dict(sprites.get(name))
		if rect.is_empty():
			continue
		var s := PbJson.as_float(kind.get("scale"), 0.05) * PbJson.as_float(p["s"], 1.0)
		var w := PbJson.as_float(rect.get("w"), 0.0) * s
		var h := PbJson.as_float(rect.get("h"), 0.0) * s
		var x := float(p["x"])
		var y := float(p["y"])
		var z := float(p["z"])
		var u0 := PbJson.as_float(rect.get("x"), 0.0) / atlas_w
		var u1 := (PbJson.as_float(rect.get("x"), 0.0) + w / s) / atlas_w
		if bool(p["flip"]):
			var tmp := u0
			u0 = u1
			u1 = tmp
		# Godot samples v=0 at the first row of the image, so the sprite's top edge is y/H.
		var v_top := PbJson.as_float(rect.get("y"), 0.0) / atlas_h
		var v_bottom := (PbJson.as_float(rect.get("y"), 0.0) + h / s) / atlas_h
		var offset := 0.22 if name.begins_with("tree") else (0.1 if PbJson.as_float(kind.get("collider")) > 0.0 else 0.0)
		var base := verts.size()
		# A unit quad: x spans the sprite width, y is the relative height wind bends from.
		verts.append(Vector3(-0.5, 0.0, 0.0))
		verts.append(Vector3(0.5, 0.0, 0.0))
		verts.append(Vector3(-0.5, 1.0, 0.0))
		verts.append(Vector3(0.5, 1.0, 0.0))
		uvs.append(Vector2(u0, v_bottom))
		uvs.append(Vector2(u1, v_bottom))
		uvs.append(Vector2(u0, v_top))
		uvs.append(Vector2(u1, v_top))
		for _c in 4:
			colors.append(Color(w, h, PbJson.as_float(kind.get("sway")), 0.0))
			tangents.append_array(PackedFloat32Array([x, y, z, 0.0]))
			per_uv2.append(Vector2(s, offset))
			normals.append(Vector3(0.0, 0.0, 1.0))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 2, base + 1, base + 3]))
		var shadow := PbJson.as_float(kind.get("shadow"))
		if shadow > 0.0:
			var r := shadow * PbJson.as_float(p["s"], 1.0)
			var sb := shadow_verts.size()
			shadow_verts.append(Vector3(x - r * 0.5, y + 0.05, z))
			shadow_verts.append(Vector3(x + r * 0.5, y + 0.05, z))
			shadow_verts.append(Vector3(x, y + 0.05, z - r * 0.35))
			shadow_verts.append(Vector3(x, y + 0.05, z + r * 0.35))
			shadow_uvs.append(Vector2(0, 0.5))
			shadow_uvs.append(Vector2(1, 0.5))
			shadow_uvs.append(Vector2(0.5, 0))
			shadow_uvs.append(Vector2(0.5, 1))
			shadow_indices.append_array(PackedInt32Array([sb, sb + 1, sb + 3, sb, sb + 3, sb + 2]))
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = per_uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = "Props"
	inst.mesh = mesh
	inst.material_override = _props_material(tex)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Billboards are computed per vertex, so frustum culling on the whole mesh is useless.
	inst.custom_aabb = AABB(Vector3(-terrain.world, -10, -terrain.world), Vector3(terrain.world * 2, 80, terrain.world * 2))
	_mesh_root.add_child(inst)

	if not shadow_verts.is_empty():
		var sa := []
		sa.resize(Mesh.ARRAY_MAX)
		sa[Mesh.ARRAY_VERTEX] = shadow_verts
		sa[Mesh.ARRAY_TEX_UV] = shadow_uvs
		sa[Mesh.ARRAY_INDEX] = shadow_indices
		var sm := ArrayMesh.new()
		sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
		var si := MeshInstance3D.new()
		si.name = "PropShadows"
		si.mesh = sm
		var sh := Shader.new()
		sh.code = SHADOW_SHADER
		var shm := ShaderMaterial.new()
		shm.shader = sh
		si.material_override = shm
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_root.add_child(si)


func _props_material(tex: Texture2D) -> ShaderMaterial:
	var sh := load(PROPS_SHADER) as Shader
	prop_mat = ShaderMaterial.new()
	prop_mat.shader = sh
	var light := PbJson.as_float(biome.get("light"), 1.0)
	var tint := Color(1, 1, 1).lerp(_hex_color(biome.get("sun")), 0.25) * (0.95 + 0.1 * light)
	prop_mat.set_shader_parameter("map", tex)
	prop_mat.set_shader_parameter("u_tint", tint)
	prop_mat.set_shader_parameter("u_fog_col", _hex_color(biome.get("fog")))
	prop_mat.set_shader_parameter("u_fog_near", PbJson.as_float(biome.get("fogNear"), 45.0))
	prop_mat.set_shader_parameter("u_fog_far", PbJson.as_float(biome.get("fogFar"), 170.0))
	prop_mat.set_shader_parameter("u_wind", _wind)
	prop_mat.set_shader_parameter("u_time", _time)
	prop_mat.set_shader_parameter("u_player", Vector3(0, -999, 0))
	return prop_mat


# ------------------------------------------------------------------- water
func _build_water() -> void:
	if not terrain.has_water:
		return
	var sh := load(WATER_SHADER) as Shader
	water_mat = ShaderMaterial.new()
	water_mat.shader = sh
	var lava := terrain.is_lava
	var deep := _hex_color(12068874 if lava else biome.get("waterColor")) * (1.0 if lava else 0.55)
	var shallow := color_from_int(16752672 if lava else 7008480).srgb_to_linear()
	water_mat.set_shader_parameter("t_h", _height_tex)
	water_mat.set_shader_parameter("u_scale", 0.2 if terrain.has_relief else 1.0)
	water_mat.set_shader_parameter("u_world", terrain.world)
	water_mat.set_shader_parameter("u_level", terrain.water_level)
	water_mat.set_shader_parameter("u_lava", 1.0 if lava else 0.0)
	water_mat.set_shader_parameter("u_ice", 1.0 if terrain.frozen else 0.0)
	water_mat.set_shader_parameter("u_deep", deep)
	water_mat.set_shader_parameter("u_shallow", shallow)
	water_mat.set_shader_parameter("u_fog_col", _hex_color(biome.get("fog")))
	water_mat.set_shader_parameter("u_fog_near", PbJson.as_float(biome.get("fogNear"), 45.0))
	water_mat.set_shader_parameter("u_fog_far", PbJson.as_float(biome.get("fogFar"), 170.0))
	if terrain.ponds.is_empty():
		var plane := PlaneMesh.new()
		plane.size = Vector2(terrain.world, terrain.world)
		var inst := MeshInstance3D.new()
		inst.name = "Water"
		inst.mesh = plane
		inst.material_override = water_mat
		inst.position = Vector3(0, terrain.water_level, 0)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_root.add_child(inst)
	else:
		# One disc per pond, radius r*1.3, at that pond's level.
		for p in terrain.ponds:
			var disc := _circle_mesh(float(p["r"]) * 1.3)
			var inst := MeshInstance3D.new()
			inst.name = "Pond"
			inst.mesh = disc
			var mat := water_mat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("u_level", float(p["level"]))
			inst.material_override = mat
			inst.position = Vector3(float(p["x"]), float(p["level"]), float(p["z"]))
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_water_root.add_child(inst)


func _circle_mesh(radius: float, segments: int = 32) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	uvs.append(Vector2(0.5, 0.5))
	normals.append(Vector3(0, 1, 0))
	for i in segments:
		var a := float(i) / float(segments) * TAU
		verts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
		normals.append(Vector3(0, 1, 0))
	for i in range(1, segments):
		indices.append_array(PackedInt32Array([0, i, i + 1]))
	indices.append_array(PackedInt32Array([0, segments, 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_sky() -> void:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	var sky := PbJson.as_array(biome.get("sky"))
	sky_mat.set_shader_parameter("u_top", _hex_color(sky[0] if sky.size() > 0 else 3838207))
	sky_mat.set_shader_parameter("u_bottom", _hex_color(sky[1] if sky.size() > 1 else 11066623))
	var dome := MeshInstance3D.new()
	dome.name = "SkyDome"
	var sphere := SphereMesh.new()
	sphere.radius = 420.0
	sphere.height = 840.0
	sphere.radial_segments = 24
	sphere.rings = 12
	dome.mesh = sphere
	dome.material_override = sky_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	_dome = dome


# ------------------------------------------------------------------- look & animation
func _look_from_biome() -> Dictionary:
	var sky := PbJson.as_array(biome.get("sky"))
	return {
		"top": float(sky[0]) if sky.size() > 0 else 3838207.0,
		"bottom": float(sky[1]) if sky.size() > 1 else 11066623.0,
		"fog": PbJson.as_float(biome.get("fog"), 10409215.0),
		"near": PbJson.as_float(biome.get("fogNear"), 45.0),
		"far": PbJson.as_float(biome.get("fogFar"), 170.0),
		"light": PbJson.as_float(biome.get("light"), 1.0),
		"sun": PbJson.as_float(biome.get("sun"), 16773590.0),
	}


## Zone / weather overrides (`look` blocks in world_fx.json) go through here.
func set_look(overrides: Dictionary) -> void:
	_look_target = _look_from_biome()
	for key in overrides:
		_look_target[key] = overrides[key]


func blend_look(weight: float) -> void:
	for key in _look_target:
		_look[key] = lerpf(float(_look.get(key, 0.0)), float(_look_target[key]), clampf(weight, 0.0, 1.0))
	apply_look()


func apply_look() -> void:
	if terrain_mat == null:
		return
	var light := float(_look.get("light", 1.0))
	var fog := color_from_int(int(_look.get("fog", 10409215))).srgb_to_linear()
	var sun := color_from_int(int(_look.get("sun", 16773590))).srgb_to_linear() * (1.05 * light)
	terrain_mat.set_shader_parameter("u_fog_col", fog)
	terrain_mat.set_shader_parameter("u_fog_near", float(_look.get("near", 45.0)))
	terrain_mat.set_shader_parameter("u_fog_far", float(_look.get("far", 170.0)))
	terrain_mat.set_shader_parameter("u_sun_col", sun)
	terrain_mat.set_shader_parameter("u_shadow_col", _shadow_tint(String(biome.get("id", ""))) * (0.72 * light + 0.08))
	if prop_mat != null:
		prop_mat.set_shader_parameter("u_fog_col", fog)
		prop_mat.set_shader_parameter("u_fog_near", float(_look.get("near", 45.0)))
		prop_mat.set_shader_parameter("u_fog_far", float(_look.get("far", 170.0)))
	if water_mat != null:
		water_mat.set_shader_parameter("u_fog_col", fog)
		water_mat.set_shader_parameter("u_fog_near", float(_look.get("near", 45.0)))
		water_mat.set_shader_parameter("u_fog_far", float(_look.get("far", 170.0)))
	if sky_mat != null:
		sky_mat.set_shader_parameter("u_top", color_from_int(int(_look.get("top", 3838207))).srgb_to_linear())
		sky_mat.set_shader_parameter("u_bottom", color_from_int(int(_look.get("bottom", 11066623))).srgb_to_linear())


func set_sun_dir(dir: Vector3) -> void:
	if dir.length_squared() <= 0.0001:
		return
	if terrain_mat != null:
		terrain_mat.set_shader_parameter("u_sun_dir", dir.normalized())


func set_wind(value: float) -> void:
	_wind = clampf(value, 0.0, 3.0)
	if prop_mat != null:
		prop_mat.set_shader_parameter("u_wind", _wind)


## Per-frame uniforms: the shared clock and the player position used by the prop fade.
var _dome: MeshInstance3D


func tick(delta: float, player_pos: Vector3, cam: Camera3D = null) -> void:
	_time += delta
	var cam_pos := Vector3.ZERO
	var cam_fwd := Vector3(0.0, 0.0, -1.0)
	var cam_right := Vector3(1.0, 0.0, 0.0)
	if cam != null:
		cam_pos = cam.global_position
		cam_fwd = -cam.global_transform.basis.z.normalized()
		cam_right = cam.global_transform.basis.x.normalized()
	for mat in [terrain_mat, prop_mat, water_mat]:
		if mat != null:
			mat.set_shader_parameter("u_cam", cam_pos)
			mat.set_shader_parameter("u_cam_fwd", cam_fwd)
			if mat == prop_mat:
				mat.set_shader_parameter("u_cam_right", cam_right)
	if prop_mat != null:
		prop_mat.set_shader_parameter("u_time", _time)
		prop_mat.set_shader_parameter("u_player", player_pos)
		prop_mat.set_shader_parameter("u_cam", cam_pos)
	if water_mat != null:
		water_mat.set_shader_parameter("u_time", _time)
	if terrain_mat != null:
		terrain_mat.set_shader_parameter("u_time_g", _time)


## Real props the mirror ships as .glb (desert hoodoos, glacier spires, ruins columns...).
## The reference swaps these in for prop kinds that carry a `model` name.
func place_models() -> int:
	var placed := 0
	for p in terrain.props:
		var kind: Dictionary = p["kind"]
		if not kind.has("model"):
			continue
		var path := "res://assets/models/%s.glb" % String(kind["model"])
		if not ResourceLoader.exists(path):
			continue
		var packed = load(path)
		if not (packed is PackedScene):
			continue
		var node: Node = (packed as PackedScene).instantiate()
		if node is Node3D:
			var n3 := node as Node3D
			n3.position = Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
			var scale_v := PbJson.as_float(kind.get("scale"), 1.0) * PbJson.as_float(p["s"], 1.0)
			n3.scale = Vector3.ONE * scale_v
			_mesh_root.add_child(n3)
			placed += 1
	return placed
