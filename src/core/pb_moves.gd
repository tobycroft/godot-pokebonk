class_name PbMoves
extends RefCounted
## Resolves a moves.json record into the real-time move definition the game uses.
##
## Ported from the bundle:
##   _y(move)  -> archetype_for()   (offset 789750)
##   vy(key)   -> resolve()          (offset 791717)
##   by(species) -> learnable_moves() (offset 792596)
##   xy(species) -> best_move_for()   (offset 792596)
##
## Web original also attaches a `cast`/`sfx` VFX closure per move. Those are
## JavaScript bodies and cannot be represented as data, so behaviour here is
## driven by the archetype instead (see PbArchetypes). Recorded in
## data/pb/missing_remote_assets.json -> pokemon_3d_animation_clips.

static var _memo := {}
static var _arch_regex := []
static var _tables_loaded := false
static var _archetypes := {}
static var _type_status := {}
static var _type_arch := {}
static var _move_arch := {}
static var _move_overrides := {}
static var _weather_moves := {}
static var _buff_moves := {}
static var _hazard_moves := {}
static var _rules := []


static func _ensure_tables() -> void:
	if _tables_loaded:
		return
	_archetypes = PbJson.as_dict(PbData.pb_table("archetypes"))
	_type_status = PbJson.as_dict(PbData.pb_table("type_status"))
	_type_arch = PbJson.as_dict(PbData.pb_table("type_arch"))
	var rules := PbJson.as_dict(PbData.pb_table("arch_rules"))
	_weather_moves = PbJson.as_dict(rules.get("weather_moves", {}))
	_buff_moves = {}
	for key in rules.get("buff_moves", []):
		_buff_moves[str(key)] = true
	_hazard_moves = {}
	for key in rules.get("hazard_moves", []):
		_hazard_moves[str(key)] = true
	_rules = PbJson.as_array(rules.get("rules", []))
	_arch_regex.clear()
	for pair in _rules:
		var entry := PbJson.as_array(pair)
		if entry.size() < 2:
			continue
		var re := RegEx.create_from_string(str(entry[0]))
		if re != null:
			_arch_regex.append([re, str(entry[1])])
	_move_arch = PbJson.as_dict(PbData.pb_table("move_arch"))
	# qv (status/shape tweaks, offset 768229) and dy (projectile shape, offset 787515)
	# are merged into one override table in the web build (Object.assign(dy, ...));
	# dy is applied last so it wins where both name the same move.
	_move_overrides = {}
	for k in PbJson.as_dict(PbData.pb_table("move_status")).keys():
		_move_overrides[str(k)] = PbJson.as_dict(PbData.pb_table("move_status")[k])
	for k in PbJson.as_dict(PbData.pb_table("move_shape")).keys():
		_move_overrides[str(k)] = PbJson.as_dict(PbData.pb_table("move_shape")[k])
	_tables_loaded = true


## Uv(): normalise a Pokemon ailment name into PokeBonk's status vocabulary.
static func normalize_ailment(ailment: Variant) -> String:
	match PbJson.as_string(ailment):
		"burn":
			return "burn"
		"poison":
			return "poison"
		"paralysis":
			return "paralysis"
		"freeze":
			return "freeze"
		"sleep", "yawn":
			return "sleep"
		"confusion":
			return "confusion"
		"trap", "leech-seed":
			return "root"
		"heal-block", "embargo":
			return "healblock"
		"infatuation":
			return "charm"
		"nightmare":
			return "curse"
		_:
			return ""


static func archetype_for(move: Dictionary) -> String:
	_ensure_tables()
	var key := PbJson.as_string(move.get("key"), "")
	var cls := PbJson.as_string(move.get("cls", "physical"), "physical")
	var override := PbJson.as_string(_move_arch.get(key, ""), "")
	if cls == "status":
		if _weather_moves.has(key):
			return "weather"
		if _buff_moves.has(key):
			return "buff"
		if _hazard_moves.has(key):
			return "trap"
		return override
	if not override.is_empty():
		return override
	if PbJson.as_float(move.get("power"), 0.0) <= 0.0 and not key.contains("drain") and cls == "physical":
		return "strike"
	if PbJson.as_float(move.get("drain"), 0.0) > 0.0:
		return "drain"
	if PbJson.as_int(move.get("maxHits"), 1) >= 2:
		return "barrage"
	for pair in _arch_regex:
		if pair[0].search(key) != null:
			return pair[1]
	if move.get("accuracy") == null and cls == "special":
		return "homing"
	var pair := PbJson.as_array(_type_arch.get(PbJson.as_string(move.get("type"), "normal"), ["strike", "bolt"]))
	var fallback: Variant = "bolt" if pair.size() < 2 else (pair[0] if cls == "physical" else pair[1])
	return str(fallback)


## vy(): build the real-time definition. Returns {} for moves the game cannot use
## (unresolved archetype), exactly like the web code caching null.
static func resolve(move_key: String) -> Dictionary:
	_ensure_tables()
	if _memo.has(move_key):
		return _memo[move_key]
	var move := PbData.move_def(move_key)
	if move.is_empty():
		_memo[move_key] = {}
		return {}
	var arch := archetype_for(move)
	if arch.is_empty() or not _archetypes.has(arch):
		_memo[move_key] = {}
		return {}
	var base := PbJson.as_dict(_archetypes[arch])
	var power := PbJson.as_float(move.get("power"), 70.0)
	var dmg_mult := clampf(0.72 + power / 260.0, 0.85, 1.3)
	var cd_mult := clampf(0.88 + (power - 60.0) / 500.0, 0.85, 1.15) * (0.85 if PbJson.as_int(move.get("priority"), 0) > 0 else 1.0)

	var status := normalize_ailment(move.get("ailment", null))
	var chance := 0.0
	if status.is_empty():
		status = PbJson.as_string(_type_status.get(str(move.get("type", "")), ""), "")
		chance = 0.12
	else:
		chance = clampf(PbJson.as_float(move.get("ailmentChance"), 30.0) / 100.0 * 1.6, 0.15, 0.8)
	if PbJson.as_string(move.get("cls"), "") == "status":
		chance = 0.8

	var drain := PbJson.as_float(move.get("drain"), 0.0)
	var def := {
		"id": move.get("id", 0),
		"key": PbJson.as_string(move.get("key"), ""),
		"name": PbJson.as_string(move.get("name"), ""),
		"type": PbJson.as_string(move.get("type"), "normal"),
		"cls": "special" if PbJson.as_string(move.get("cls"), "") == "status" else PbJson.as_string(move.get("cls"), ""),
		"arch": arch,
		"dmg": float(base.get("dmg", 0)) * dmg_mult,
		"cd": float(base.get("cd", 1)) * cd_mult,
		"count": int(base.get("count", 1)),
		"area": float(base.get("area", 1)),
		"speed": float(base.get("speed", 0)),
		"dur": float(base.get("dur", 1)),
		"pierce": int(base.get("pierce", 0)),
		"status": status if not status.is_empty() else null,
		"statusChance": chance,
		"drain": clampf(drain / 100.0 * 0.3, 0.05, 0.25) if drain > 0.0 else (0.12 if arch == "drain" else 0.0),
		"critBonus": 0.15 if PbJson.as_int(move.get("crit"), 0) >= 1 else 0.0,
		"flinch": PbJson.as_float(move.get("flinch"), 0.0) / 100.0,
		"power": power,
		"weather": _weather_moves.get(move_key, null),
		"buff": move_key if _buff_moves.has(move_key) else null,
		"stats": PbJson.as_array(base.get("stats", [])),
		"archLabel": str(base.get("label", arch)),
		"archDesc": str(base.get("desc", "")),
		"desc": "",
	}
	if PbJson.as_string(move.get("cls"), "") == "status" and arch == "trap":
		def["dmg"] = float(base.get("dmg", 0)) * 0.9

	var shape := PbJson.as_dict(_move_overrides.get(move_key, {}))
	if not shape.is_empty():
		if shape.get("count") != null:
			def["count"] = int(shape["count"])
		if shape.get("spread") != null:
			def["spread"] = float(shape["spread"])
		if shape.get("pulses") != null:
			def["pulses"] = int(shape["pulses"])
		if shape.get("dmgMul") != null:
			def["dmg"] = float(def["dmg"]) * float(shape["dmgMul"])
		if shape.has("status"):
			def["status"] = shape["status"]
		if shape.get("statusChance") != null:
			def["statusChance"] = float(shape["statusChance"])

	def["desc"] = describe(def)
	_memo[move_key] = def
	return def


## yy(): rebuild the player-facing description from archetype + traits.
## The web strings were baked into the Spanish build; kept verbatim so the port
## stays comparable, and localised later through data/i18n when keys exist.
static func describe(def: Dictionary) -> String:
	var arch := str(def.get("arch", ""))
	var text := str(def.get("archDesc", ""))
	if def.get("weather") != null:
		text = {
			"rain": "Invoca lluvia: potencia Agua y Eléctrico, moja a los enemigos.",
			"sun": "Invoca sol: potencia Fuego y Planta.",
			"sand": "Tormenta de arena: daña a los enemigos y potencia Roca/Tierra.",
			"hail": "Granizo: daña y congela poco a poco a los enemigos.",
		}.get(str(def["weather"]), text)
	if def.get("buff") != null:
		text = "Te potencia: +daño, +velocidad de ataque y +velocidad durante unos segundos."
	if arch == "random":
		return App.ui(text)
	if def.get("pulses") != null and int(def["pulses"]) > 1:
		text = App.ui("Libera {n} ondas expansivas seguidas a tu alrededor.", {"n": int(def["pulses"])})
	if int(def.get("count", 1)) > 1 and arch == "boomerang":
		text = App.ui("Lanza {n} proyectiles en abanico que van y vuelven atravesando enemigos.", {"n": int(def["count"])})
	if def.get("status") != null and float(def.get("statusChance", 0)) >= 0.12 and arch != "weather" and arch != "buff":
		text += " " + App.ui("Puede causar {status}.", {"status": App.ui(_status_label(str(def["status"])))})
	if float(def.get("drain", 0)) > 0.0 and arch != "drain":
		text += " " + App.ui("Roba vida.")
	if float(def.get("critBonus", 0)) > 0.0:
		text += " " + App.ui("Crítico elevado.")
	return App.ui(text)


## Web Hv: the status keys used by `Puede causar {status}.`.
static func _status_label(status: String) -> String:
	var labels := {
		"burn": "Quemado", "poison": "Envenenado", "paralysis": "Paralizado",
		"freeze": "Congelado", "sleep": "Dormido", "confusion": "Confuso",
		"wet": "Mojado", "curse": "Maldito", "healblock": "Anticura",
		"charm": "Encantado", "root": "Enraizado", "knock": "Retroceso", "stun": "Aturdido",
	}
	return str(labels.get(status, status))


## by(): every move key the species' evolution line can learn that resolves to a
## usable real-time definition.
static func learnable_moves(species_id: int) -> Array:
	var seen := {}
	var out := []
	var current_id := species_id
	var guard := 0
	while current_id > 0 and guard < 12:
		guard += 1
		for entry in PbData.learnset(current_id):
			var pair := PbJson.as_array(entry)
			if pair.is_empty():
				continue
			var move := PbData.move_by_id(int(pair[0]))
			if move.is_empty():
				continue
			var mk := PbJson.as_string(move.get("key"), "")
			if seen.has(mk):
				continue
			if resolve(mk).is_empty():
				continue
			seen[mk] = true
			out.append(mk)
		var spec := PbData.species(current_id)
		if spec.get("evoFrom") == null:
			break
		current_id = int(spec["evoFrom"])
	return out


## xy(): pick the signature-ish move the game would auto-assign to a species.
static func best_move_for(species_id: int) -> String:
	var spec := PbData.species(species_id)
	var types := PbJson.as_array(spec.get("types", []))
	var entries := []
	var current_id := species_id
	var guard := 0
	while current_id > 0 and guard < 12:
		guard += 1
		for entry in PbData.learnset(current_id):
			entries.append(entry)
		var s2 := PbData.species(current_id)
		if s2.get("evoFrom") == null:
			break
		current_id = int(s2["evoFrom"])

	var best_key := ""
	var best_score := -1.0e30
	for entry in entries:
		var pair := PbJson.as_array(entry)
		if pair.size() < 2:
			continue
		var move := PbData.move_by_id(int(pair[0]))
		if move.is_empty():
			continue
		var mk := PbJson.as_string(move.get("key"), "")
		var rt := resolve(mk)
		if rt.is_empty():
			continue
		var arch := str(rt["arch"])
		if arch in ["weather", "buff", "trap"]:
			continue
		var score := (100.0 if types.has(PbJson.as_string(move.get("type"), "")) else 0.0) \
			- float(pair[1]) * 1.5 + PbJson.as_float(move.get("power"), 40.0) * 0.2
		if PbJson.as_string(move.get("type"), "") == "normal" and not types.has("normal"):
			score -= 40.0
		if score > best_score:
			best_score = score
			best_key = mk
	return best_key


static func reset_cache() -> void:
	_memo.clear()
	_arch_regex.clear()
	_tables_loaded = false
