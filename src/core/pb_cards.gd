class_name PbCards
extends RefCounted
## Level-up rewards ("power-ups"): stat cards, type cards, move upgrades and new
## moves, plus the reroll / skip / banish loop.
##
## Verified from the bundle:
##   card shape ``{label, mods:[{stat, add|mul}]}``  (offset 541981, table bg)
##   per-archetype upgradeable stats ``stats:[...]``  (offset 773555, table oy)
##   mod application semantics                       (PbStats.apply_mod_groups)
##   lab-gated reroll/skip/banish counts              (api-core.js LAB table)
##
## The *amounts* on stat cards live inside the offer-rolling closures, which were
## not recoverable as a data table; they are tiered estimates here and every one
## of them is tagged ``estimated: true`` so a later pass can replace them.

const STAT_POOL := [
	"damage", "physical", "special", "attackSpeed", "moveSpeed", "maxHp", "regen",
	"armor", "evasion", "projectiles", "area", "duration", "projSpeed",
	"critChance", "critDamage", "lifesteal", "thorns", "knockback", "pickupRange",
	"xpGain", "gold", "luck", "statusChance", "statusDamage", "healing",
	"superEffective", "flinch", "bounces", "eliteDamage", "megaCrit", "overheal",
	"powerup", "eliteSpawn", "slam",
]

## Estimated tiers; TODO(reverse): confirm against the offer-rolling code.
const TIERS := [
	{"mul": 1.08, "add_scale": 1.0, "weight": 3.0},
	{"mul": 1.15, "add_scale": 1.6, "weight": 2.0},
	{"mul": 1.25, "add_scale": 2.5, "weight": 1.0},
]

## Stats whose card form is additive rather than multiplicative.
const ADDITIVE_STATS := {
	"projectiles": 1, "bounces": 1, "extraJumps": 1, "luck": 1, "thorns": 1,
	"pickupRange": 1, "shieldMax": 1, "maxHp": 1, "armor": 1, "regen": 1,
	"evasion": 1, "critChance": 1, "critDamage": 1, "lifesteal": 1, "flinch": 1,
	"overheal": 1, "megaCrit": 1,
}

const ARCH_STAT_AMOUNTS := {
	"dmg": {"mul": 1.12}, "cd": {"mul": 0.92}, "count": {"add": 1},
	"area": {"mul": 1.1}, "speed": {"mul": 1.1}, "dur": {"mul": 1.12},
	"pierce": {"add": 1}, "crit": {"add": 0.04}, "status": {"mul": 1.15},
	"bounce": {"add": 1},
}


static func type_cards() -> Dictionary:
	return PbJson.as_dict(PbData.pb_table("type_cards"))


## One random card from the pool; exclude keys lets the caller avoid duplicates
## and the run's banished set.
static func roll(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var kind := PbRng.weighted([[3.0, "stat"], [1.4, "type"], [2.4, "move_upgrade"], [1.2, "new_move"]])
	match String(kind):
		"type":
			return roll_type_card(exclude)
		"move_upgrade":
			var up := roll_move_upgrade(actor, exclude)
			if not up.is_empty():
				return up
		"new_move":
			var nm := roll_new_move(actor, exclude)
			if not nm.is_empty():
				return nm
	return roll_stat_card(exclude)


static func roll_stat_card(exclude: Dictionary = {}) -> Dictionary:
	var stat := String(PbRng.pick(STAT_POOL))
	var tier := PbRng.weighted(TIERS.map(func(t): return [float(t["weight"]), t]))
	var mod := {}
	if ADDITIVE_STATS.has(stat):
		var base := _add_base(stat)
		mod = {"stat": stat, "add": float(base) * float(tier["add_scale"])}
	else:
		mod = {"stat": stat, "mul": float(tier["mul"])}
	return {
		"kind": "stat",
		"stat": stat,
		"mods": [mod],
		"label": "%s %s" % [_label(stat), _fmt(mod)],
		"estimated": true,
	}


static func roll_type_card(exclude: Dictionary = {}) -> Dictionary:
	var cards := type_cards()
	var keys := cards.keys().filter(func(k): return not exclude.has("type:" + String(k)))
	if keys.is_empty():
		keys = cards.keys()
	var pick_type := String(PbRng.pick(keys))
	var card := PbJson.as_dict(cards.get(pick_type, {}))
	return {
		"kind": "type",
		"type": pick_type,
		"mods": PbJson.as_array(card.get("mods", [])),
		"label": String(card.get("label", pick_type)),
		"estimated": false,
	}


static func roll_move_upgrade(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var slots := _owned_slots(actor)
	slots = slots.filter(func(s): return not exclude.has("mv:" + String(s["key"])))
	if slots.is_empty():
		return {}
	var slot := PbJson.as_dict(PbRng.pick(slots))
	var arch := String(slot.get("arch", "bolt"))
	var stats := _arch_stats(arch)
	if stats.is_empty():
		return {}
	var stat := String(PbRng.pick(stats))
	var amount := PbJson.as_dict(ARCH_STAT_AMOUNTS.get(stat, {"mul": 1.1}))
	var mod := amount.duplicate(true)
	mod["stat"] = stat
	if stat == "count" or stat == "pierce" or stat == "bounce":
		mod["add"] = 1
	return {
		"kind": "move_upgrade",
		"move_key": String(slot["key"]),
		"slot": int(slot["slot"]),
		"stat": stat,
		"mods": [mod],
		"label": "%s · %s" % [String(slot.get("name", "")), stat],
		"estimated": true,
	}


static func roll_new_move(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var species_id := int(actor.get("species_id", 1))
	var owned := PbActor.move_keys(actor)
	var candidates := []
	for key in PbMoves.learnable_moves(species_id):
		if owned.has(key):
			continue
		if exclude.has("new:" + String(key)):
			continue
		var def := PbMoves.resolve(String(key))
		if def.is_empty():
			continue
		candidates.append(String(key))
	if candidates.is_empty():
		return {}
	var pick_key := String(PbRng.pick(candidates))
	var def := PbMoves.resolve(pick_key)
	return {
		"kind": "new_move",
		"move_key": pick_key,
		"mods": [],
		"label": String(def.get("name", pick_key)),
		"estimated": false,
	}


static func offer(actor: Dictionary, count: int = 3, banished: Dictionary = {}) -> Array:
	var out := []
	var used := banished.duplicate(true)
	var guard := 0
	while out.size() < count and guard < 40:
		guard += 1
		var card := roll(actor, used)
		if card.is_empty():
			break
		used[String(card.get("kind", "")) + ":" + String(card.get("stat", card.get("type", card.get("move_key", guard))))] = true
		out.append(card)
	return out


## Applies a chosen card to the actor; returns a human-readable result line.
static func take(actor: Dictionary, card: Dictionary) -> String:
	match String(card.get("kind", "")):
		"new_move":
			var ok := PbActor.learn(actor, String(card["move_key"]), PbActor.free_slot(actor))
			return "learned" if ok else "no free slot"
		"move_upgrade":
			PbActor.upgrade_move(actor, int(card["slot"]), card)
			return "move upgraded"
		_:
			PbActor.add_mods(actor, PbJson.as_array(card.get("mods", [])))
			return "stats"
	return ""


static func _owned_slots(actor: Dictionary) -> Array:
	var out := []
	var moves: Array = PbJson.as_array(actor.get("moves", []))
	for i in moves.size():
		var m = moves[i]
		if m == null:
			continue
		var def := PbJson.as_dict(PbJson.as_dict(m).get("def", {}))
		if def.is_empty():
			continue
		out.append({"slot": i, "key": String(def.get("key", "")), "name": String(def.get("name", "")),
			"arch": String(def.get("arch", ""))})
	return out


static func _arch_stats(arch: String) -> Array:
	var table := PbJson.as_dict(PbData.pb_table("archetypes"))
	return PbJson.as_array(PbJson.as_dict(table.get(arch, {})).get("stats", []))


static func _add_base(stat: String) -> float:
	match stat:
		"maxHp":
			return 20.0
		"armor":
			return 4.0
		"regen":
			return 0.25
		"evasion", "critChance", "flinch", "lifesteal", "overheal", "megaCrit":
			return 0.03
		"critDamage":
			return 0.15
		"luck":
			return 6.0
		"pickupRange":
			return 1.0
		_:
			return 1.0


static func _label(stat: String) -> String:
	var labels := {
		"damage": "Daño", "physical": "Daño físico", "special": "Daño especial",
		"attackSpeed": "Vel. de ataque", "moveSpeed": "Velocidad", "maxHp": "PS máx.",
		"projectiles": "Proyectiles", "area": "Área", "duration": "Duración",
		"critChance": "Prob. crítico", "critDamage": "Daño crítico", "gold": "Pokédólares",
		"xpGain": "Experiencia", "luck": "Suerte", "armor": "Armadura", "regen": "Regeneración",
		"eliteDamage": "Daño a élites", "healing": "Curación", "evasion": "Evasión",
	}
	return String(labels.get(stat, stat))


static func _fmt(mod: Dictionary) -> String:
	if mod.has("add"):
		var v := float(mod["add"])
		if absf(v) < 1.0:
			return "+%d%%" % int(round(v * 100.0))
		return "+%s" % str(v)
	return "+%d%%" % int(round((float(mod.get("mul", 1.0)) - 1.0) * 100.0))
