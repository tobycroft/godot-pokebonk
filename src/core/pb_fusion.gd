class_name PbFusion
extends RefCounted
## The fused-move system ("Bill's machine"): recipe catalogue, lookup rules and
## the fused move definition.
##
## Ported from the bundle:
##   Fw assembly + normalisation (offset 1278535) -> data/pb/fusion_catalog.json
##   gw / yw / Sw factories                       -> data/pb/fusion_extras.json
##   Uw(a,b) recipe lookup            (offset ~1278700) -> recipe_for()
##   JC(recipe,id) fused move def     (offset 1113565)  -> fused_def()
##   Gw(run) available offers         (offset ~1278900) -> offers()
##   Kw(run,offer) perform the fusion (offset ~1279100) -> apply()
##   Hw(def) fusion eligibility                        -> is_eligible()

const MOVE_MAX_LEVEL := 8        # "{name} Nv. {lv}/8" -- both moves must be maxed
const FUSION_PLACEHOLDER_ID_BASE := 900000
const INHERIT_TIMER := 1.2

static var _entries: Array = []
static var _by_key := {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_entries.clear()
	_by_key.clear()
	for table in ["fusion_catalog", "fusion_extras"]:
		var raw := PbJson.as_dict(PbData.pb_table(table))
		for e in PbJson.as_array(raw.get("entries", [])):
			var entry := PbJson.as_dict(e)
			var key := String(entry.get("key", ""))
			if key.is_empty() or _by_key.has(key):
				continue
			_by_key[key] = entry
			_entries.append(entry)
	_loaded = true


static func count() -> int:
	_ensure()
	return _entries.size()


static func by_key(key: String) -> Dictionary:
	_ensure()
	return _by_key.get(key, {})


static func all_recipes() -> Array:
	_ensure()
	return _entries.duplicate()


static func recipe_id(key: String) -> int:
	## The web build numbers fused moves from an internal base (VC). The port keeps
	## its own block above the moves.json id range so fused moves never collide.
	_ensure()
	var index := 0
	for e in _entries:
		if String(e["key"]) == key:
			return FUSION_PLACEHOLDER_ID_BASE + index
		index += 1
	return -1


## Hw(): weather/buff/fusion moves cannot be fused.
static func is_eligible(movedef: Dictionary) -> bool:
	var arch := String(movedef.get("arch", ""))
	return arch != "weather" and arch != "buff" and arch != "fusion"


## Uw(): pick the recipe for two move definitions.
static func recipe_for(a: Dictionary, b: Dictionary) -> Dictionary:
	_ensure()
	var a_key := String(a.get("key", ""))
	var b_key := String(b.get("key", ""))
	for r in _entries:
		if String(r.get("kind", "")) != "signature":
			continue
		var moves: Array = PbJson.as_array(r.get("moves", []))
		if moves.size() < 2:
			continue
		if (String(moves[0]) == a_key and String(moves[1]) == b_key) \
				or (String(moves[0]) == b_key and String(moves[1]) == a_key):
			return r
	var a_type := String(a.get("type", ""))
	var b_type := String(b.get("type", ""))
	for r in _entries:
		if String(r.get("kind", "")) != "reaction":
			continue
		var pair: Array = PbJson.as_array(r.get("pair", []))
		if pair.size() < 2:
			continue
		var left := PbJson.as_array(pair[0])
		var right := PbJson.as_array(pair[1])
		if (left.has(a_type) and right.has(b_type)) or (left.has(b_type) and right.has(a_type)):
			return r
	if a_type == b_type:
		for r in _entries:
			if String(r.get("kind", "")) == "type" and String(r.get("type", "")) == a_type:
				return r
	for r in _entries:
		if String(r.get("kind", "")) == "glitch":
			return r
	return {}


## JC(): build the real-time fused move definition from a recipe.
static func fused_def(recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {}
	var archetype := PbJson.as_dict(PbData.pb_table("archetypes"))
	var fusion_base := PbJson.as_dict(archetype.get("fusion", {}))
	var status = recipe.get("status")
	var def := {
		"id": recipe_id(String(recipe.get("key", ""))),
		"key": String(recipe.get("key", "")),
		"name": String(recipe.get("name", "")),
		"type": String(recipe.get("type", "normal")),
		"type2": recipe.get("type2"),
		"cls": String(recipe.get("cls", "special")),
		"arch": "fusion",
		"dmg": float(fusion_base.get("dmg", 17)) * float(recipe.get("power", 1)),
		"cd": float(recipe.get("cd", 3)),
		"count": 0,
		"area": 5,
		"speed": 1,
		"dur": 1,
		"pierce": 99,
		"status": status,
		"statusChance": 0.5 if status != null else 0.0,
		"drain": 0.0,
		"critBonus": 0.0,
		"flinch": 0.0,
		"power": 100,
		"desc": String(recipe.get("desc", "")),
		"stats": PbJson.as_array(fusion_base.get("stats", [])),
		"archLabel": String(fusion_base.get("label", "Fusión")),
		"archDesc": String(fusion_base.get("desc", "")),
		"fusion": {
			"key": String(recipe.get("key", "")),
			"hits": float(recipe.get("hits", 1)),
			"repeats": bool(recipe.get("repeats", false)),
			"kind": String(recipe.get("kind", "generic")),
			"members": PbJson.as_array(recipe.get("moves", [])),
			"range": float(recipe.get("range", 0)),
		},
	}
	return def


## Gw(): every fusion the current move list allows, with what is still missing.
static func offers(moves: Array) -> Array:
	var out := []
	var eligible := []
	for i in moves.size():
		var slot = moves[i]
		if slot == null:
			continue
		var inst := PbJson.as_dict(slot)
		if not is_eligible(PbJson.as_dict(inst.get("def", {}))):
			continue
		eligible.append([i, inst])
	for x in eligible.size():
		for y in range(x + 1, eligible.size()):
			var ia: Array = eligible[x]
			var ib: Array = eligible[y]
			var da: Dictionary = PbJson.as_dict(ia[1].get("def", {}))
			var db: Dictionary = PbJson.as_dict(ib[1].get("def", {}))
			var recipe := recipe_for(da, db)
			if recipe.is_empty():
				continue
			var need := []
			if int(ia[1].get("level", 1)) < MOVE_MAX_LEVEL:
				need.append("%s Nv. %d/%d" % [da.get("name", "?"), int(ia[1].get("level", 1)), MOVE_MAX_LEVEL])
			if int(ib[1].get("level", 1)) < MOVE_MAX_LEVEL:
				need.append("%s Nv. %d/%d" % [db.get("name", "?"), int(ib[1].get("level", 1)), MOVE_MAX_LEVEL])
			out.append({
				"recipe": recipe,
				"a": int(ia[0]),
				"b": int(ib[0]),
				"names": [da.get("name", ""), db.get("name", "")],
				"types": [da.get("type", ""), db.get("type", "")],
				"ready": need.is_empty(),
				"need": need,
			})
	var rank := {"signature": 0, "reaction": 1, "type": 2, "glitch": 3}
	out.sort_custom(func(p, q): return _before(p, q, rank))
	return out


static func _before(p: Dictionary, q: Dictionary, rank: Dictionary) -> bool:
	var pr := 1 if bool(p.get("ready", false)) else 0
	var qr := 1 if bool(q.get("ready", false)) else 0
	if pr != qr:
		return pr > qr
	var pk := int(rank.get(String(PbJson.as_dict(p.get("recipe", {})).get("kind", "")), 9))
	var qk := int(rank.get(String(PbJson.as_dict(q.get("recipe", {})).get("kind", "")), 9))
	return pk < qk


## Kw(): perform the fusion -- merge mods, remember parents, free the other slot.
static func apply(moves: Array, offer: Dictionary) -> Dictionary:
	var a = moves[int(offer["a"])]
	var b = moves[int(offer["b"])]
	if a == null or b == null:
		return {}
	var recipe := PbJson.as_dict(offer.get("recipe", {}))
	var fused := fused_def(recipe)
	if fused.is_empty():
		return {}
	var merged_mods := _merge_mods(PbJson.as_dict(a).get("mods", []), PbJson.as_dict(b).get("mods", []))
	var parents := []
	parents.append_array([PbJson.as_dict(a).get("def", {}).get("id", 0), PbJson.as_dict(b).get("def", {}).get("id", 0)])
	parents.append_array(PbJson.as_array(PbJson.as_dict(a).get("parents", [])))
	parents.append_array(PbJson.as_array(PbJson.as_dict(b).get("parents", [])))
	var inst := {
		"def": fused,
		"level": 1,
		"mods": merged_mods,
		"parents": parents,
		"timer": INHERIT_TIMER,
		"cooldown": 0.0,
		"fused_from": [String(PbJson.as_dict(a).get("def", {}).get("key", "")), String(PbJson.as_dict(b).get("def", {}).get("key", ""))],
	}
	var target := mini(int(offer["a"]), int(offer["b"]))
	moves[int(offer["a"])] = null
	moves[int(offer["b"])] = null
	moves[target] = inst
	return inst


static func _merge_mods(left: Variant, right: Variant) -> Array:
	## UC(a.mods, b.mods): a fused move inherits the upgrade cards of both parents.
	var out: Array = []
	for src in [left, right]:
		for m in PbJson.as_array(src):
			out.append(PbJson.as_dict(m))
	return out
