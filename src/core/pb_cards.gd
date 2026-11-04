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

## Card rarity (5 tiers): offer roll `GS` @1096835 and its multiplier table
## news `ie` (exported as `er`) = [1, 1.2, 1.45, 1.75, 2.1].
## The kind weights mirror the web offer composition in `KS` @1079932:
## new moves are pushed 3x, owned-move upgrades 2x, owned-vitamin upgrades 2x
## and brand-new vitamins get a .45 chance. The port's "stat"/"type" cards are
## its stand-ins for vitamin upgrades, so they inherit 2.0 / .45.
const RARITY_MULT := [1.0, 1.2, 1.45, 1.75, 2.1]

## Stats whose card form is additive rather than multiplicative.
const ADDITIVE_STATS := {
	"projectiles": 1, "bounces": 1, "extraJumps": 1, "luck": 1, "thorns": 1,
	"pickupRange": 1, "shieldMax": 1, "maxHp": 1, "armor": 1, "regen": 1,
	"evasion": 1, "critChance": 1, "critDamage": 1, "lifesteal": 1, "flinch": 1,
	"overheal": 1, "megaCrit": 1,
}

## Move-upgrade amounts: web `Ey(e,t)` @794294, where t is RARITY_MULT[r].
const ARCH_STAT_AMOUNTS := {
	"dmg": {"base": 0.22}, "cd": {"base": 0.08}, "count": {"base": 1},
	"area": {"base": 0.15}, "speed": {"base": 0.15}, "dur": {"base": 0.2},
	"pierce": {"base": 1}, "crit": {"base": 0.05}, "status": {"base": 0.25},
	"bounce": {"base": 1},
}


static func type_cards() -> Dictionary:
	return PbJson.as_dict(PbData.pb_table("type_cards"))


## One random card from the pool; exclude keys lets the caller avoid duplicates
## and the run's banished set.
static func roll(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var kind := PbRng.weighted([[2.0, "stat"], [0.45, "type"], [2.0, "move_upgrade"],
		[3.0, "new_move"]])
	match str(kind):
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
	return roll_stat_card(exclude, actor)


static func roll_stat_card(exclude: Dictionary = {}, actor: Dictionary = {}) -> Dictionary:
	var stat := str(PbRng.pick(STAT_POOL))
	var rarity := _roll_rarity(actor)
	var mult := float(RARITY_MULT[rarity])
	var mod := {}
	if ADDITIVE_STATS.has(stat):
		mod = {"stat": stat, "add": _add_base(stat) * mult}
	else:
		# Multiplicative vitamins are "1 + per*rarity": the port keeps its base
		# +8% as the rarity-0 anchor until the vitamin `per` table is located.
		mod = {"stat": stat, "mul": 1.0 + 0.08 * mult}
	return {
		"kind": "stat",
		"stat": stat,
		"rarity": rarity,
		"mods": [mod],
		"label": "%s %s" % [_label(stat), _fmt(mod)],
		"estimated": true,
	}


## `GS(e,t,n,r)` @1096835: a = luck/100, o = level + luck/8 + (stage-1)*12,
## weights = [70/(1+a), 24*(1+.5a), 5*(1+a)^2*c3, .9*(1+a)^3*c8, .12*(1+a)^4*c14]
## where cX = clamp((o-X)/(2X-? )) -- see clamps below (3..10, 8..18, 14..26).
static func _roll_rarity(actor: Dictionary, stage: int = 1) -> int:
	var stats := PbJson.as_dict(actor.get("stats", {}))
	var luck := maxf(0.0, float(stats.get("luck", 0.0)))
	var a := luck / 100.0
	var o := float(actor.get("level", 1)) + luck / 8.0 + float(stage - 1) * 12.0
	var weights := [
		70.0 / (1.0 + a),
		24.0 * (1.0 + 0.5 * a),
		5.0 * pow(1.0 + a, 2.0) * clampf((o - 3.0) / 7.0, 0.0, 1.0),
		0.9 * pow(1.0 + a, 3.0) * clampf((o - 8.0) / 10.0, 0.0, 1.0),
		0.12 * pow(1.0 + a, 4.0) * clampf((o - 14.0) / 12.0, 0.0, 1.0),
	]
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := PbRng.randf_range(0.0, total)
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return 0


static func roll_type_card(exclude: Dictionary = {}) -> Dictionary:
	var cards := type_cards()
	var keys := cards.keys().filter(func(k): return not exclude.has("type:" + str(k)))
	if keys.is_empty():
		keys = cards.keys()
	var pick_type := str(PbRng.pick(keys))
	var card := PbJson.as_dict(cards.get(pick_type, {}))
	return {
		"kind": "type",
		"type": pick_type,
		"mods": PbJson.as_array(card.get("mods", [])),
		"label": str(card.get("label", pick_type)),
		"estimated": false,
	}


static func roll_move_upgrade(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var slots := _owned_slots(actor)
	slots = slots.filter(func(s): return not exclude.has("mv:" + str(s["key"])))
	if slots.is_empty():
		return {}
	var slot := PbJson.as_dict(PbRng.pick(slots))
	var arch := str(slot.get("arch", "bolt"))
	var stats := _arch_stats(arch)
	if stats.is_empty():
		return {}
	var stat := str(PbRng.pick(stats))
	var rarity := _roll_rarity(actor)
	var mult := float(RARITY_MULT[rarity])
	var base := float(PbJson.as_dict(ARCH_STAT_AMOUNTS.get(stat, {"base": 0.1}))["base"])
	var mod := {"stat": stat}
	match stat:
		"count":
			mod["add"] = 2 if mult >= 1.6 else 1
		"pierce", "bounce":
			mod["add"] = maxi(1, int(round(mult)))
		"cd":
			mod["mul"] = 1.0 - minf(0.25, base * mult)
		"crit":
			mod["add"] = base * mult
		_:
			mod["mul"] = 1.0 + base * mult
	return {
		"kind": "move_upgrade",
		"move_key": str(slot["key"]),
		"slot": int(slot["slot"]),
		"stat": stat,
		"rarity": rarity,
		"mods": [mod],
		"label": "%s · %s" % [str(slot.get("name", "")), stat],
		"estimated": false,
	}


static func roll_new_move(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var species_id := int(actor.get("species_id", 1))
	var owned := PbActor.move_keys(actor)
	var candidates := []
	for key in PbMoves.learnable_moves(species_id):
		if owned.has(key):
			continue
		if exclude.has("new:" + str(key)):
			continue
		var def := PbMoves.resolve(str(key))
		if def.is_empty():
			continue
		candidates.append(str(key))
	if candidates.is_empty():
		return {}
	var pick_key := str(PbRng.pick(candidates))
	var def := PbMoves.resolve(pick_key)
	return {
		"kind": "new_move",
		"move_key": pick_key,
		"mods": [],
		"label": App.t("moves", int(def.get("id", 0)), str(def.get("name", pick_key))),
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
		used[str(card.get("kind", "")) + ":" + str(card.get("stat", card.get("type", card.get("move_key", guard))))] = true
		out.append(card)
	return out


## Applies a chosen card to the actor; returns a human-readable result line.
static func take(actor: Dictionary, card: Dictionary) -> String:
	match str(card.get("kind", "")):
		"new_move":
			var ok := PbActor.learn(actor, str(card["move_key"]), PbActor.free_slot(actor))
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
		out.append({"slot": i, "key": str(def.get("key", "")), "name": str(def.get("name", "")),
			"arch": str(def.get("arch", ""))})
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
	return App.ui(str(labels.get(stat, stat)))


static func _fmt(mod: Dictionary) -> String:
	if mod.has("add"):
		var v := float(mod["add"])
		if absf(v) < 1.0:
			return "+%d%%" % int(round(v * 100.0))
		return "+%s" % str(v)
	return "+%d%%" % int(round((float(mod.get("mul", 1.0)) - 1.0) * 100.0))
