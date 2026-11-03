extends TextureRect
class_name PmdSprite
## Animated PMD sprite driven by data/sprites.json (see PbPmd for the sheet math).
##
## Replaces the site's <canvas class="pix"> sprites: same frame timings, same
## nearest-neighbour pixel look, and the same fallback chain (PMD sheet -> first
## frame of any sheet -> nothing) so a species without a sheet still renders.

var species_id := 1
var anim_name := "idle"
var facing := 1
var pixel_scale := 3.0
var elapsed := 0.0
var playing := true

var _anim_cache := {}


func setup(id: int, anim := "idle", scale_factor := 3.0, direction := 1) -> PmdSprite:
	species_id = id
	anim_name = anim
	pixel_scale = scale_factor
	facing = direction
	playing = true
	_refresh_size()
	_update(0.0)
	return self


func set_anim(anim: String, keep_time: bool = false) -> void:
	if anim_name == anim:
		return
	anim_name = anim
	if not keep_time:
		elapsed = 0.0
	_update(elapsed)


func set_facing(direction: int) -> void:
	facing = posmod(direction, maxi(1, int(PbPmd.anim(species_id, anim_name).get("rows", 1))))


func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	_update(elapsed)


func _update(t: float) -> void:
	var tex := PbVisuals.frame_texture(species_id, anim_name, t, facing)
	if tex != null:
		texture = tex


func _refresh_size() -> void:
	var a := PbPmd.anim(species_id, anim_name)
	var fw := float(a.get("fw", 40))
	var fh := float(a.get("fh", 40))
	custom_minimum_size = Vector2(fw, fh) * pixel_scale
	size = custom_minimum_size
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
