class_name PbVisuals
extends RefCounted
## Builds the visuals for a species: 3D avatar and 2D textures.
##
## The web build renders species as PMD billboards; .glb is reserved for props,
## balls and terminals. Per-species models were never shipped (see
## data/pb/missing_remote_assets.json), so avatars fall back in four steps --
## each step is deliberate rather than a missing-resource error:
##
##   1. res://assets/models/<key>.glb, but ONLY for keys listed in
##      SPECIES_MODEL_KEYS. assets/models/ also holds world props (61 shipped
##      .glb: terminals, balls, altars...), and some prop names collide with
##      species keys (e.g. "porygon" is the event terminal, not #137). Never
##      infer a species model from the filename alone.
##   2. billboard quad textured with the species' PMD sheet frame (shipped)
##   3. billboard quad textured with the species' static front art
##      (assets/front/<id>.png) -- the web build's `front/<id>.png` fallback for
##      species that have no PMD anims; UI portraits are never used here
##   4. tinted box from pokemon.json color/height/weight (always works)
##
## SPECIES_MODEL_KEYS is therefore empty; add a key only when a real per-species
## model actually ships.

const SPECIES_MODEL_KEYS := {}   # species key -> true; empty by design

## World units per texture pixel. The web build pushes the PMD billboard as
## `fw * Bl, fh * Bl` (bundle @119245 with `Bl = .074`, and `Vl = .04` for the
## `front/<id>.png` fallback), so a 32x40 frame is ~2.4x3.0 units tall quads
## whose opaque body reads at human scale. Sizing the quad off `pokemon.json`
## height instead (the old `Vector2(h*0.9, h)`) drew 0.6 unit postage stamps.
const PMD_PIXEL_UNIT := 0.074
const FRONT_PIXEL_UNIT := 0.04

const COLOR_NAMES := {
	"black": 0x2b2b2b, "blue": 0x4a90d9, "brown": 0x8b5a2b, "gray": 0x9aa0a6,
	"green": 0x4caf50, "pink": 0xf06292, "purple": 0x9575cd, "red": 0xe53935,
	"white": 0xeceff1, "yellow": 0xfdd835, "cyan": 0x4dd0e1,
}

static var _sheet_cache := {}
static var _frame_cache := {}
static var _bounds_cache := {}


static func color_for(species: Dictionary) -> Color:
	var raw := str(species.get("color", "gray")).to_lower()
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


## Static "front" art for species with no PMD animation.
## Priority matches the web build: its `front/<id>.png` fallback is the shipped
## assets/front/<id>.png. The 40x40 assets/portraits crops are UI icons and must
## never be used as a billboard texture while the front art exists, so they are
## only the last resort here.
static func front_texture(species_id: int) -> Texture2D:
	var fallback := str(PbData.pmd_meta(species_id).get("fallback", ""))
	if not fallback.is_empty():
		var alt := "res://assets/%s" % fallback
		if ResourceLoader.exists(alt):
			return load(alt)
	var p := "res://assets/portraits/%d.png" % species_id
	if ResourceLoader.exists(p):
		return load(p)
	return null


## Assign a frame texture to a 3D material.
##
## A QuadMesh samples UV 0..1, and Godot's 3D materials do NOT resolve the
## region carried by an AtlasTexture -- the quad ends up sampling the whole
## 704x2112 sheet, which minifies the sheet into the quad and leaves a handful
## of stray texels (the "few pixel speckles" bug). Measured in-engine: the same
## billboard drawn with a baked 32x40 crop or with Sprite3D is correct, so the
## frame window is pushed into the material's UV transform here instead.
static func apply_frame_texture(mat: StandardMaterial3D, tex: Texture2D) -> void:
	if mat == null:
		return
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3.ONE
	mat.uv1_offset = Vector3.ZERO
	if tex is AtlasTexture:
		var atlas := tex as AtlasTexture
		var atlas_size := atlas.atlas.get_size()
		if atlas_size.x > 0.0 and atlas_size.y > 0.0:
			mat.uv1_scale = Vector3(atlas.region.size.x / atlas_size.x,
				atlas.region.size.y / atlas_size.y, 1.0)
			mat.uv1_offset = Vector3(atlas.region.position.x / atlas_size.x,
				atlas.region.position.y / atlas_size.y, 0.0)


## Opaque pixel padding of one frame: how much empty pixel rows sit above/below
## the body. The web build scans the same thing (`foot.top`/`foot.foot`, bundle
## @132133) to stand the sprite's feet on the ground instead of its quad's edge.
static func frame_bounds(species_id: int, anim_name: String, facing: int = 1) -> Dictionary:
	var key := "%d:%s:%d" % [species_id, anim_name, facing]
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var tex := sheet(species_id)
	var rect := PbPmd.frame_rect(species_id, anim_name, 0.0, facing)
	var result := {"top_pad": 0.0, "bottom_pad": 0.0, "content_h": rect.size.y, "width": rect.size.x}
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		var area := Rect2i(Vector2i(rect.position), Vector2i(rect.size)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size()))
		if area.size.x > 0 and area.size.y > 0:
			var top := _first_opaque_row(img, area, false)
			var bottom := _first_opaque_row(img, area, true)
			if top >= 0 and bottom >= 0 and bottom >= top:
				result = {
					"top_pad": float(top - area.position.y),
					"bottom_pad": float(area.end.y - 1 - bottom),
					"content_h": float(bottom - top + 1),
					"width": float(area.size.x),
				}
	_bounds_cache[key] = result
	return result


static func _first_opaque_row(img: Image, area: Rect2i, from_bottom: bool) -> int:
	var y := area.end.y - 1
	var stop := area.position.y - 1
	var step := -1
	if not from_bottom:
		y = area.position.y
		stop = area.end.y
		step = 1
	while y != stop:
		for x in range(area.position.x, area.end.x):
			if img.get_pixel(x, y).a > 0.5:
				return y
		y += step
	return -1


## Quad size and centre height for a species billboard. `lift` is how far above
## the actor's ground point the quad centre must sit so the sprite's opaque feet
## land on the ground (PMD frames carry empty rows under the body).
static func billboard_layout(species_id: int, anim_name: String = "walk", scale: float = 1.0) -> Dictionary:
	var unit := FRONT_PIXEL_UNIT
	var w := 96.0
	var hgt := 96.0
	var bottom_pad := 0.0
	var content_px := 96.0
	if sheet(species_id) != null:
		unit = PMD_PIXEL_UNIT
		var anim := PbPmd.anim(species_id, anim_name)
		w = float(anim.get("fw", 40))
		hgt = float(anim.get("fh", 40))
		var bounds := frame_bounds(species_id, anim_name, 1)
		bottom_pad = float(bounds.get("bottom_pad", 0.0))
		content_px = float(bounds.get("content_h", hgt))
	else:
		var front := front_texture(species_id)
		if front != null:
			w = float(front.get_width())
			hgt = float(front.get_height())
			var img := front.get_image()
			if img != null:
				var top := _first_opaque_row(img, Rect2i(Vector2i.ZERO, img.get_size()), false)
				var bottom := _first_opaque_row(img, Rect2i(Vector2i.ZERO, img.get_size()), true)
				if top >= 0 and bottom >= top:
					bottom_pad = float(img.get_height() - 1 - bottom)
					content_px = float(bottom - top + 1)
	var size := Vector2(w, hgt) * unit * scale
	return {
		"size": size,
		"lift": size.y * 0.5 - bottom_pad * unit * scale,
		"content_height": content_px * unit * scale,
	}


## A Node3D representing the species in the arena.
static func avatar(species_id: int, key: String = "") -> Node3D:
	var species := PbData.species(species_id)
	var model_key := key if not key.is_empty() else str(species.get("key", ""))
	var glb_path := "res://assets/models/%s.glb" % model_key
	if SPECIES_MODEL_KEYS.has(model_key) and ResourceLoader.exists(glb_path):
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
	var layout := billboard_layout(species_id, "idle")
	if tex != null:
		apply_frame_texture(material, tex)
		var mesh := QuadMesh.new()
		mesh.size = layout["size"]
		quad.mesh = mesh
		quad.position = Vector3(0, float(layout["lift"]), 0)
		quad.set_meta("world_height", float(layout["content_height"]))
	else:
		# Step 4: tinted box so the species is still visible and correctly sized.
		material.albedo_color = color_for(species)
		var box := BoxMesh.new()
		box.size = Vector3(h * 0.7, h, h * 0.7)
		quad.mesh = box
		quad.position = Vector3(0, h * 0.5, 0)
		quad.set_meta("world_height", h)
		kind = "color-box"
	quad.material_override = material
	quad.set_meta("avatar_kind", kind)
	quad.set_meta("height", h)
	return quad


static func clear_cache() -> void:
	_sheet_cache.clear()
	_frame_cache.clear()
	_bounds_cache.clear()
