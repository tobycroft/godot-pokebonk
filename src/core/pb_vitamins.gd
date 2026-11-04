class_name PbVitamins
extends RefCounted
## Run vitamins, ported from the bundle's addVitamin() and the `de`/`ue`/`pe`
## helpers in the data chunk:
##   addVitamin() @839470  level/acc/extra/rolls bookkeeping
##   `de` (exported `ii`)   vitamin -> mods (dice rolls merge by stat)
##   `ue`                    per-level mod: add = per*acc, mul = 1+per*acc
##   `pe`                    loaded-dice roll: another vitamin's per*value*1.5
##
## The level cap stays 10; the max-ether item only raises the *offer* cap
## (`Ob.vitCap` @841200 = 10 + (max-ether ? 2 : 0)) because addVitamin()
## hard-codes `level >= 10` for the extra bucket.

const LEVEL_CAP := 10
const DICE_SCALE := 1.5

static var _defs: Dictionary = {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		for raw in PbJson.as_array(PbData.pb_table("vitamins")):
			var def := PbJson.as_dict(raw)
			_defs[str(def.get("key", ""))] = def
	return _defs


static func def_of(key: String) -> Dictionary:
	return PbJson.as_dict(defs().get(key, {}))


static func entries(actor: Dictionary) -> Dictionary:
	return PbJson.as_dict(actor.get("vitamins", {}))


static func entry_of(actor: Dictionary, key: String) -> Dictionary:
	return PbJson.as_dict(entries(actor).get(key, {}))


static func level_of(actor: Dictionary, key: String) -> int:
	return int(entry_of(actor, key).get("level", 0))


static func slots_for(actor: Dictionary) -> int:
	return int(actor.get("vitaminSlots", 3))


## Ob.vitCap: 10, or 12 with max-ether in the bag.
static func cap_for(actor: Dictionary) -> int:
	return LEVEL_CAP + (2 if int(PbActor.item_power(actor, "max-ether")) > 0 else 0)


static func can_offer_new(actor: Dictionary) -> bool:
	return entries(actor).size() < slots_for(actor)


## addVitamin(e,t): `value` is the card's rarity multiplier (Ot[rarity]).
static func add(actor: Dictionary, key: String, value: float) -> Dictionary:
	var def := def_of(key)
	if def.is_empty():
		return {}
	var map := entries(actor)
	var entry := PbJson.as_dict(map.get(key, {}))
	if not entry.is_empty():
		if int(entry.get("level", 0)) >= LEVEL_CAP:
			# Past the cap the web keeps a flat list of the rolled values.
			var extra := PbJson.as_array(entry.get("extra", []))
			extra.append(value)
			entry["extra"] = extra
		entry["level"] = int(entry.get("level", 0)) + 1
		entry["acc"] = float(entry.get("acc", 0.0)) + value
	else:
		entry = {"level": 1, "acc": value}
		map[key] = entry
	if bool(def.get("dice", false)):
		var rolls := PbJson.as_array(entry.get("rolls", []))
		rolls.append(_roll_dice(value))
		entry["rolls"] = rolls
	PbActor.recompute(actor)
	return entry


## `de(e,t)`: every vitamin contributes its level mod plus its side mods. Dice
## vitamins only expose their merged rolls (the web ignores extra/acc there).
static func mods_for(actor: Dictionary) -> Array:
	var out := []
	var map := entries(actor)
	for key in map.keys():
		var def := def_of(str(key))
		if def.is_empty():
			continue
		var entry := PbJson.as_dict(map[key])
		if bool(def.get("dice", false)):
			out.append_array(_dice_mods(entry))
			continue
		var acc := float(entry.get("acc", 0.0))
		out.append(_base_mod(def, acc))
		for raw in PbJson.as_array(def.get("extra", [])):
			var extra := PbJson.as_dict(raw)
			out.append({"stat": str(extra.get("stat", "")),
				"mul": 1.0 + float(extra.get("mul", 0.0)) * acc})
	return out


## Mods a card would add right now (the offer's tooltip numbers).
static func preview(actor: Dictionary, key: String, value: float) -> Dictionary:
	var def := def_of(key)
	if def.is_empty():
		return {}
	var current := entry_of(actor, key)
	var is_new := current.is_empty()
	var entry := current.duplicate(true)
	if is_new:
		entry = {"level": 1, "acc": value}
	else:
		entry["level"] = int(entry.get("level", 0)) + 1
		entry["acc"] = float(entry.get("acc", 0.0)) + value
	var mods := []
	if bool(def.get("dice", false)):
		var rolls := PbJson.as_array(entry.get("rolls", [])) + [_roll_dice(value)]
		mods = _dice_mods({"rolls": rolls})
	else:
		mods.append(_base_mod(def, float(entry.get("acc", 0.0))))
		for raw in PbJson.as_array(def.get("extra", [])):
			var extra := PbJson.as_dict(raw)
			mods.append({"stat": str(extra.get("stat", "")),
				"mul": 1.0 + float(extra.get("mul", 0.0)) * float(entry.get("acc", 0.0))})
	return {"mods": mods, "level": int(entry.get("level", 1)), "cap": cap_for(actor)}


## `ue`: add = per*acc, mul = 1+per*acc.
static func _base_mod(def: Dictionary, acc: float) -> Dictionary:
	var amount := float(def.get("per", 0.0)) * acc
	if str(def.get("kind", "mul")) == "add":
		return {"stat": str(def.get("stat", "")), "add": amount}
	return {"stat": str(def.get("stat", "")), "mul": 1.0 + amount}


## `pe(value, pick)`: a random non-dice vitamin without side mods, worth
## per*value*1.5 (loaded-dice never rolls overheal/powerup).
static func _roll_dice(value: float) -> Dictionary:
	var candidates := []
	for key in defs().keys():
		var def := PbJson.as_dict(defs()[key])
		if bool(def.get("dice", false)):
			continue
		if def.has("extra"):
			continue
		var stat := str(def.get("stat", ""))
		if stat == "overheal" or stat == "powerup":
			continue
		candidates.append(def)
	if candidates.is_empty():
		return {}
	var picked := PbJson.as_dict(PbRng.pick(candidates))
	var amount := float(picked.get("per", 0.0)) * value * DICE_SCALE
	if str(picked.get("kind", "mul")) == "add":
		return {"stat": str(picked.get("stat", "")), "add": amount}
	return {"stat": str(picked.get("stat", "")), "mul": 1.0 + amount}


## Merge loaded-dice rolls by stat (web: mul sums its (mul-1), add sums).
static func _dice_mods(entry: Dictionary) -> Array:
	var merged := {}
	var order := []
	for raw in PbJson.as_array(entry.get("rolls", [])):
		var mod := PbJson.as_dict(raw)
		var stat := str(mod.get("stat", ""))
		if merged.has(stat):
			var current := PbJson.as_dict(merged[stat])
			if mod.has("add"):
				current["add"] = float(current.get("add", 0.0)) + float(mod.get("add", 0.0))
			else:
				current["mul"] = float(current.get("mul", 1.0)) \
					+ (float(mod.get("mul", 1.0)) - 1.0)
			merged[stat] = current
		else:
			merged[stat] = mod.duplicate()
			order.append(stat)
	var out := []
	for stat in order:
		out.append(PbJson.as_dict(merged[stat]))
	return out
