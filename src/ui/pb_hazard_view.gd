class_name PbHazardView
extends Node3D
## Draws the hostile terrain decals from `PbHazards` state.
##
## Web reference: `kw.spawn()` @1311420 builds a 18x18 plane, samples the
## terrain height per vertex (+.07), maps one 2x2 hazards.png cell and blinks /
## fades through `uAlpha`. Ring particles and ambient motes are cosmetic and not
## ported; the decal, atlas cell and alpha phases are.

const CELLS := 2
const SUBDIVIDE := 18

var _nodes := {}          # hazard id -> MeshInstance3D
var _atlas: Texture2D


func _ready() -> void:
	if ResourceLoader.exists(PbHazards.ATLAS_PATH):
		_atlas = load(PbHazards.ATLAS_PATH) as Texture2D


## Recreate/refresh the decals once per rendered frame.
func sync(state: Dictionary, terrain: PbTerrain) -> void:
	var alive := {}
	for entry in PbHazards.list(state):
		var hazard := PbJson.as_dict(entry)
		var id := int(hazard.get("id", 0))
		alive[id] = true
		var node: MeshInstance3D = _nodes.get(id)
		if node == null:
			node = _spawn_node(hazard, terrain)
			_nodes[id] = node
		var material := node.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(1.0, 1.0, 1.0,
				clampf(float(hazard.get("alpha", 0.0)), 0.0, 1.0))
	for id in _nodes.keys():
		if not alive.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)


func _spawn_node(hazard: Dictionary, terrain: PbTerrain) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var radius := float(hazard.get("r", 5.0))
	var cx := float(hazard.get("x", 0.0))
	var cz := float(hazard.get("z", 0.0))
	node.mesh = _build_mesh(cx, cz, radius, terrain)
	node.position = Vector3(cx, 0.0, cz)
	node.rotation.y = float(hazard.get("rot", 0.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = _cell_texture(int(PbHazards.def_of(
		str(hazard.get("kind", ""))).get("cell", 0)))
	node.material_override = material
	add_child(node)
	return node


## 18x18 grid conforming to the height field, UV 0..1 (the atlas region handles
## the cell remap; Godot's V axis is top-down, so row = floor(cell/2)).
func _build_mesh(cx: float, cz: float, radius: float, terrain: PbTerrain) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in SUBDIVIDE + 1:
		for i in SUBDIVIDE + 1:
			var u := float(i) / SUBDIVIDE
			var v := float(j) / SUBDIVIDE
			var x := cx - radius + radius * 2.0 * u
			var z := cz - radius + radius * 2.0 * v
			var y := (terrain.height(x, z) if terrain != null else 0.0) + 0.07
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(x, y, z))
	for j in SUBDIVIDE:
		for i in SUBDIVIDE:
			var a := j * (SUBDIVIDE + 1) + i
			var b := a + 1
			var c := a + SUBDIVIDE + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()


func _cell_texture(cell: int) -> AtlasTexture:
	if _atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = _atlas
	var size := Vector2(_atlas.get_width() / CELLS, _atlas.get_height() / CELLS)
	texture.region = Rect2(Vector2(cell % CELLS, floor(float(cell) / CELLS)) * size, size)
	return texture
