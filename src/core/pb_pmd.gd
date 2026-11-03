class_name PbPmd
extends RefCounted
## PMD sprite-sheet frame maths.
##
## data/sprites.json carries, per dex id, the sheet size and one entry per
## animation: {y, fw, fh, n, rows, d[]}. The frame layout was read off the UV code
## at bundle offset 133475:
##
##     frame b is at x = b*fw, and when rows > 1 the facing index selects the
##     sub-row: y = anim.y + facing*fh
##
## so each animation is a horizontal strip, repeated `rows` times vertically for
## the facing directions. Sheet durations (d) are milliseconds.
##
## TODO(verify): the facing order (0..rows-1) is assumed to be the classic PMD
## order (down, down-right, right, up-right, up, up-left, left, down-left).

const FALLBACK := {"y": 0.0, "fw": 96.0, "fh": 96.0, "n": 1.0, "rows": 1.0, "d": [60.0]}
const DIRECTIONS := 8


static func meta(species_id: int) -> Dictionary:
	return PbData.pmd_meta(species_id)


static func has_sheet(species_id: int) -> bool:
	return not meta(species_id).is_empty()


static func anim(species_id: int, name: String) -> Dictionary:
	var m := meta(species_id)
	if m.is_empty():
		return FALLBACK
	var anims := PbJson.as_dict(m.get("anims", {}))
	var a = anims.get(name, null)
	if a == null:
		a = anims.get("walk", null)
	if a == null:
		return {"y": 0.0, "fw": m.get("w", 96), "fh": m.get("h", 96), "n": 1, "rows": 1, "d": [60]}
	return PbJson.as_dict(a)


static func anim_names(species_id: int) -> Array:
	return PbJson.as_dict(meta(species_id).get("anims", {})).keys()


static func total_ms(a: Dictionary) -> float:
	var total := 0.0
	for v in PbJson.as_array(a.get("d", [])):
		total += float(v)
	return total if total > 0.0 else 1.0


## Frame index for elapsed time in seconds (the web build uses time*60 ms units).
static func frame_at(a: Dictionary, elapsed: float) -> int:
	var total := total_ms(a)
	var ms := int(floor(elapsed * 60.0))
	var y := posmod(ms, int(total))
	var durations: Array = PbJson.as_array(a.get("d", []))
	var frame := 0
	while frame < durations.size() - 1 and y >= int(durations[frame]):
		y -= int(durations[frame])
		frame += 1
	return frame


## Progress 0..1 -> frame index (used by UI thumbnails that loop once).
static func frame_at_progress(a: Dictionary, progress: float) -> int:
	var total := total_ms(a)
	var y := int(clampf(progress, 0.0, 0.999999) * total)
	var durations: Array = PbJson.as_array(a.get("d", []))
	var frame := 0
	while frame < durations.size() - 1 and y >= int(durations[frame]):
		y -= int(durations[frame])
		frame += 1
	return frame


static func facing_row(a: Dictionary, facing: int) -> int:
	return facing if int(a.get("rows", 1)) > 1 else 0


## Pixel rect of one frame inside the sheet.
static func frame_rect(species_id: int, anim_name: String, elapsed: float, facing: int = 1) -> Rect2:
	var a := anim(species_id, anim_name)
	var b := frame_at(a, elapsed)
	var fw := float(a.get("fw", 40))
	var fh := float(a.get("fh", 40))
	var row := facing_row(a, facing)
	return Rect2(b * fw, float(a.get("y", 0)) + row * fh, fw, fh)


static func sheet_size(species_id: int) -> Vector2i:
	var m := meta(species_id)
	if m.is_empty():
		return Vector2i(96, 96)
	return Vector2i(int(m.get("w", 96)), int(m.get("h", 96)))


## Normalised UVs, handy for shaders/meshes.
static func frame_uv(species_id: int, anim_name: String, elapsed: float, facing: int = 1) -> Array:
	var size := sheet_size(species_id)
	var r := frame_rect(species_id, anim_name, elapsed, facing)
	return [r.position.x / size.x, (r.position.x + r.size.x) / size.x,
		r.position.y / size.y, (r.position.y + r.size.y) / size.y]


static func texture_path(species_id: int) -> String:
	return "res://assets/pmd/%d.png" % species_id
