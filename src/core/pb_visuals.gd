class_name PbVisuals
extends RefCounted
## Builds the visuals for a species: 3D avatar and 2D textures.
##
## The web build streams a .glb per species from the CDN (assets/models/<key>.glb).
## Those files are absent from pokebonk-web and unreachable here (see
## data/pb/missing_remote_assets.json), so avatars fall back in three steps --
## and each step is deliberate rather than a missing-resource error:
##
##   1. res://assets/models/<key>.glb        (real model, used as soon as it exists)
##   2. billboard quad textured with the species' PMD sheet frame (shipped)
##   3. billboard quad textured with the species' static portrait
##      (assets/portraits/<id>.png) -- mirrors the web build's `front/<id>.png`
##      fallback for species that have no PMD anims
##   4. tinted box from pokemon.json color/height/weight (always works)

const COLOR_NAMES := {
	"black": 0x2b2b2b, "blue": 0x4a90d9, "brown": 0x8b5a2b, "gray": 0x9aa0a6,
	"green": 0x4caf50, "pink": 0xf06292, "purple": 0x9575cd, "red": 0xe53935,
	"white": 0xeceff1, "yellow": 0xfdd835, "cyan": 0x4dd0e1,
}

static var _sheet_cache := {}
static var _frame_cache := {}


static func color_for(species: Dictionary) -> Color:
	var raw := String(species.get("color", "gray")).to_lower()
	if raw.begins_with("#"):
		return Color.from_string(raw, Color(0.6, 0.6, 0.6))
	var hex = COLOR_NAMES.get(raw, null)
	return Color(int(hex)) if hex != null else Color(0.6, 0.6, 0.7)


static func sheet(species_id: int) -> Texture2D:
	if _sheet_cache.has(species_id):
		return _sheet_cache[species_id]
	var path := PbPmd.texture_path(species_id)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_sheet_cache[species_id] = tex
	return tex


## AtlasTexture for one animated frame; keyed so repeated lookups are cheap.
static func frame_texture(species_id: int, anim_name: String, elapsed: float, facing: int = 1) -> Texture2D:
	var tex := sheet(species_id)
	if tex == null:
		return null
	var rect := PbPmd.frame_rect(species_id, anim_name, elapsed, facing)
	var key := "%d:%s:%d:%d" % [species_id, anim_name, int(elapsed * 12.0), facing]
	if _frame_cache.has(key):
		return _frame_cache[key]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = rect
	_frame_cache[key] = atlas
	if _frame_cache.size() > 4096:
		_frame_cache.clear()
	return atlas


static func idle_frame_texture(species_id: int) -> Texture2D:
	return frame_texture(species_id, "idle", 0.0, 1)


## A Node3D representing the species in the arena.
static func front_texture(species_id: int) -> Texture2D:
	## The web build falls back to `front/<id>.png` for species with no PMD anims;
	## this port ships that same static art as assets/portraits/<id>.png.
	var p := "res://assets/portraits/%d.png" % species_id
	return load(p) if ResourceLoader.exists(p) else null


## A Node3D representing the species in the arena.
static func avatar(species_id: int, key: String = "") -> Node3D:
	var species := PbData.species(species_id)
	var model_key := key if not key.is_empty() else String(species.get("key", ""))
	var glb_path := "res://assets/models/%s.glb" % model_key
	if ResourceLoader.exists(glb_path):
		var packed = load(glb_path)
		if packed is PackedScene:
			var instance: Node = packed.instantiate()
			if instance is Node3D:
				instance.set_meta("avatar_kind", "glb")
				return instance
			instance.free()
	var h := clampf(float(species.get("height", 10)) / 10.0, 0.5, 3.0)
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex := idle_frame_texture(species_id)
	var kind := "pmd-billboard"
	if tex == null:
		# Step 3 (mirrors re's front/<id>.png): static portrait when no PMD anims.
		tex = front_texture(species_id)
		kind = "front-billboard"
	var quad := MeshInstance3D.new()
	quad.name = "Avatar"
	if tex != null:
		material.albedo_texture = tex
		var mesh := QuadMesh.new()
		mesh.size = Vector2(h * 0.9, h)
		quad.mesh = mesh
	else:
		# Step 4: tinted box so the species is still visible and correctly sized.
		material.albedo_color = color_for(species)
		var box := BoxMesh.new()
		box.size = Vector3(h * 0.7, h, h * 0.7)
		quad.mesh = box
		kind = "color-box"
	quad.material_override = material
	quad.position = Vector3(0, h * 0.5, 0)
	quad.set_meta("avatar_kind", kind)
	quad.set_meta("height", h)
	return quad


static func clear_cache() -> void:
	_sheet_cache.clear()
	_frame_cache.clear()
