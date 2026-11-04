class_name PbActor
extends RefCounted
## The player's Pokemon, kept as a plain Dictionary so it can be saved, diffed
## and reused by the headless simulation without any scene dependency.
##
## Ported from the bundle class ``Ob`` (offset 834827) plus its methods
## addXp/heal/gainLevel/checkGrowth/recompute (offset 843511).

const MAX_MOVES := 4
const MOVE_MAX_LEVEL := 8

## Growth index handed to PbStats.stats_from_species(). Port of checkGrowth()
## (bundle @836543): the web client recomputes at level 24 and 44, so the index
## is the number of thresholds passed (0/1/2), not level-1.


static func create(species_id: int, lab_deltas: Dictionary = {}, level: int = 1) -> Dictionary:
	var data := PbData.species(species_id)
	if data.is_empty():
		push_error("PbActor: unknown species %d" % species_id)
		return {}
	var defaults := PbJson.as_dict(PbData.const_of("player_defaults", {}))
	var state := {
		"species_id": int(data.get("id", species_id)),
		"species_key": str(data.get("key", "")),
		"name": str(data.get("name", "")),
		"data": data,
		"types": PbJson.as_array(data.get("types", ["normal"])),
		"ability": _first_ability(data),
		"level": level,
		"xp": 0.0,
		"xpNext": PbXp.need(level),
		"hp": 100.0,
		"maxHp": 100.0,
		"shield": 0.0,
		"overheal": 0.0,
		"moveSlots": int(defaults.get("move_slots", 3)) + int(lab_deltas.get("moveSlots", 0)),
		"vitaminSlots": int(defaults.get("vitamin_slots", 3)) + int(lab_deltas.get("vitaminSlots", 0)),
		"moves": [],
		"items": {},
		"vitamins": {},
		"buffs": {},
		"status": {},
		"mods": [],
		"lab_deltas": lab_deltas,
		"dead": false,
		# Revivir Máximo charges (bundle Ob.revives @835451); the lab "revive"
		# upgrade grants the starting count, consumed on a lethal hit.
		"revives": int(lab_deltas.get("revive", lab_deltas.get("revives", 0))),
		"stats": {},
		"x": 0.0,
		"z": 0.0,
		"facing": 2,
		"iframes": 0.0,
		"noHitT": 0.0,
		"pendingLevels": 0,
	}
	for i in MAX_MOVES:
		state["moves"].append(null)
	recompute(state)
	state["hp"] = float(state["stats"].get("maxHp", 100))
	state["maxHp"] = float(state["stats"].get("maxHp", 100))
	auto_assign_moves(state)
	return state


static func _first_ability(data: Dictionary) -> String:
	var ids: Array = PbJson.as_array(data.get("abilities", []))
	if ids.is_empty():
		return ""
	var ab := PbData.ability(int(ids[0]))
	return str(ab.get("key", ""))


## Full stat block: species base stats * growth + lab + every collected card mod.
static func recompute(state: Dictionary) -> void:
	var species := PbJson.as_dict(state.get("data", {}))
	var growth := float(PbCombat.growth_index(int(state.get("level", 1))))
	var lab := PbJson.as_dict(state.get("lab_deltas", {}))
	var groups: Array = PbJson.as_array(state.get("mods", []))
	# Items add one mod group per copy (bundle recompute @838235:
	# `for n in count) applyMod(mods)`), and type items bump typeBoost by .3.
	var items := PbJson.as_dict(state.get("items", {}))
	for key in items.keys():
		var def := PbData.item_game(str(key))
		if def.is_empty():
			continue
		var count := int(float(items[key]))
		var mods := PbJson.as_array(def.get("mods", []))
		for n in count:
			groups.append(mods)
	var stats := PbStats.stats_for(species, growth, lab, groups)
	for key in items.keys():
		var def := PbData.item_game(str(key))
		if def.is_empty():
			continue
		var count := int(float(items[key]))
		for tag in PbJson.as_array(def.get("tags", [])):
			if str(tag).begins_with("type:"):
				var element := str(tag).substr(5)
				stats["typeBoost"][element] = float(
					PbJson.as_dict(stats["typeBoost"]).get(element, 1.0)) + 0.3 * float(count)
	var old_max := float(state.get("maxHp", 0.0))
	var old_hp := float(state.get("hp", 0.0))
	var new_max := float(stats.get("maxHp", old_max))
	stats["hp"] = old_hp
	state["stats"] = stats
	state["maxHp"] = new_max
	if old_max > 0.0 and new_max > old_max:
		# Growth heals by the amount the cap rose, like the web recompute.
		state["hp"] = minf(new_max, old_hp + (new_max - old_max))
	var ability := str(state.get("ability", ""))
	stats["adaptability"] = ability == "adaptability"


static func actor_for_damage(state: Dictionary) -> Dictionary:
	return {
		"stats": PbJson.as_dict(state.get("stats", {})),
		"types": PbJson.as_array(state.get("types", [])),
		"adaptability": str(state.get("ability", "")) == "adaptability",
		"items": PbJson.as_dict(state.get("items", {})),
		"ability": str(state.get("ability", "")),
		"species_id": int(state.get("species_id", 0)),
	}


## ---------------------------------------------------------------- moves
static func move_keys(state: Dictionary) -> Array:
	var out := []
	for m in PbJson.as_array(state.get("moves", [])):
		if m != null:
			out.append(str(PbJson.as_dict(m).get("def", {}).get("key", "")))
	return out


static func free_slot(state: Dictionary) -> int:
	var slots := int(state.get("moveSlots", 3))
	for i in mini(slots, MAX_MOVES):
		if PbJson.as_array(state["moves"])[i] == null:
			return i
	return -1


static func learn(state: Dictionary, move_key: String, slot: int = -1) -> bool:
	var def := PbMoves.resolve(move_key)
	if def.is_empty():
		return false
	var target := slot
	if target < 0:
		target = free_slot(state)
	if target < 0 or target >= MAX_MOVES:
		return false
	var existing = PbJson.as_array(state["moves"])[target]
	if existing != null and str(PbJson.as_dict(existing).get("def", {}).get("key", "")) == move_key:
		return level_up_move(state, target)
	PbJson.as_array(state["moves"])[target] = {
		"def": def,
		"level": 1,
		"mods": [],
		"parents": [],
		"cooldown": 0.0,
		"timer": 0.0,
	}
	return true


static func forget(state: Dictionary, slot: int) -> void:
	if slot >= 0 and slot < MAX_MOVES:
		PbJson.as_array(state["moves"])[slot] = null


static func level_up_move(state: Dictionary, slot: int) -> bool:
	var m = PbJson.as_array(state["moves"])[slot]
	if m == null:
		return false
	var inst := PbJson.as_dict(m)
	var lvl := int(inst.get("level", 1))
	if lvl >= MOVE_MAX_LEVEL:
		return false
	inst["level"] = lvl + 1
	return true


## A card that upgrades one stat of an owned move.
static func upgrade_move(state: Dictionary, slot: int, card: Dictionary) -> void:
	var m = PbJson.as_array(state["moves"])[slot]
	if m == null:
		return
	var inst := PbJson.as_dict(m)
	var mods: Array = PbJson.as_array(inst.get("mods", []))
	for mod in PbJson.as_array(card.get("mods", [])):
		mods.append(PbJson.as_dict(mod))
	inst["mods"] = mods


static func add_mods(state: Dictionary, mods: Array) -> void:
	var groups: Array = PbJson.as_array(state.get("mods", []))
	groups.append(mods)
	state["mods"] = groups
	recompute(state)


## Pick the moves the web client auto-assigns when a run starts.
static func auto_assign_moves(state: Dictionary) -> void:
	var species_id := int(state.get("species_id", 1))
	var slots := int(state.get("moveSlots", 3))
	if not move_keys(state).is_empty():
		return
	var first := PbMoves.best_move_for(species_id)
	var wanted := []
	if not first.is_empty():
		wanted.append(first)
	for key in PbMoves.learnable_moves(species_id):
		if wanted.size() >= slots:
			break
		if not wanted.has(key):
			wanted.append(str(key))
	for key in wanted:
		if free_slot(state) < 0:
			break
		learn(state, str(key))


## ---------------------------------------------------------------- resources
static func add_xp(state: Dictionary, amount: float, endless: bool = false) -> int:
	var gained := PbXp.grant(state, amount,
		float(PbJson.as_dict(state.get("stats", {})).get("xpGain", 1.0)),
		1.0, endless)
	if gained > 0:
		recompute(state)
		state["pendingLevels"] = int(state.get("pendingLevels", 0)) + gained
	return gained


## Port of Ob.heal() @843232: HP never exceeds maxHp. Any excess only fills the
## overheal pool, which is capped at maxHp * stats.overheal.
static func heal(state: Dictionary, amount: float, healing_mult: float = 1.0) -> float:
	if amount <= 0.0 or bool(state.get("dead", false)):
		return 0.0
	var stats := PbJson.as_dict(state.get("stats", {}))
	var max_hp := float(state.get("maxHp", 1.0))
	var before := float(state.get("hp", 0.0))
	var healing := amount * healing_mult * float(stats.get("healing", 1.0))
	var next := minf(max_hp, before + healing)
	state["hp"] = next
	var excess := healing - (next - before)
	if excess > 0.0 and float(stats.get("overheal", 0.0)) > 0.0:
		var cap := max_hp * float(stats.get("overheal", 0.0))
		state["overheal"] = minf(cap, float(state.get("overheal", 0.0)) + excess)
	return next - before


## Port of Ob.hurt() tail @846019: overheal absorbs first, then shield, then HP.
static func damage(state: Dictionary, amount: float) -> float:
	if amount <= 0.0 or bool(state.get("dead", false)):
		return 0.0
	var left := amount
	var overheal := maxf(0.0, float(state.get("overheal", 0.0)))
	if overheal > 0.0:
		var used := minf(overheal, left)
		state["overheal"] = overheal - used
		left -= used
	if left > 0.0:
		var shield := maxf(0.0, float(state.get("shield", 0.0)))
		if shield > 0.0:
			var used := minf(shield, left)
			state["shield"] = shield - used
			left -= used
	if left > 0.0:
		var hp := float(state.get("hp", 0.0))
		hp = maxf(0.0, hp - left)
		state["hp"] = hp
		if hp <= 0.0:
			state["dead"] = true
	state["noHitT"] = 0.0
	return amount


static func item_power(state: Dictionary, key: String) -> float:
	return float(PbJson.as_dict(state.get("items", {})).get(key, 0.0))


static func give_item(state: Dictionary, key: String, power: float = 1.0) -> void:
	PbJson.as_dict(state["items"])[key] = power


## ---------------------------------------------------------------- statuses
static func apply_status(state: Dictionary, kind: String, amount: float = 0.0) -> void:
	if kind.is_empty() or not PbStatus.exists(kind):
		return
	var table := PbJson.as_dict(state["status"])
	var stats := PbJson.as_dict(state.get("stats", {}))
	var seconds := PbCombat.status_seconds(kind, float(stats.get("duration", 1.0)), 1.0)
	table[kind] = maxf(float(table.get(kind, 0.0)), seconds)
	if kind == "poison":
		table["poisonStacks"] = mini(PbCombat.POISON_STACK_CAP, int(table.get("poisonStacks", 0)) + 1)


static func has_status(state: Dictionary, kind: String) -> bool:
	return float(PbJson.as_dict(state.get("status", {})).get(kind, 0.0)) > 0.0


## Per-second upkeep: regen, status ticks and expiries.
static func tick(state: Dictionary, dt: float) -> void:
	if bool(state.get("dead", false)):
		return
	var stats := PbJson.as_dict(state.get("stats", {}))
	var table := PbJson.as_dict(state.get("status", {}))
	var max_hp := float(state.get("maxHp", 1.0))
	var no_hit := float(state.get("noHitT", 0.0))
	state["noHitT"] = no_hit + dt
	if not has_status(state, "healblock") and float(state.get("hp", 0.0)) < max_hp:
		# Ob.tick @865542: regen is HP/second and only runs while below maxHp.
		heal(state, float(stats.get("regen", 0.0)) * dt)
	# Ob.tick: overheal drains at 1% of maxHp per second.
	state["overheal"] = maxf(0.0, minf(max_hp * float(stats.get("overheal", 0.0)),
		float(state.get("overheal", 0.0)) - max_hp * 0.01 * dt))
	# Ob.tick: shields refill at 25%/s of shieldMax after 3s without a hit.
	if float(stats.get("shieldMax", 0.0)) > 0.0 and no_hit > 3.0:
		state["shield"] = minf(float(stats.get("shieldMax", 0.0)),
			float(state.get("shield", 0.0)) + float(stats.get("shieldMax", 0.0)) * 0.25 * dt)
	for kind in PbStatus.KINDS:
		var t := float(table.get(kind, 0.0))
		if t <= 0.0:
			continue
		t = maxf(0.0, t - dt)
		table[kind] = t
		if kind == "burn" or kind == "poison":
			var ratio := PbStatus.dps_ratio(kind)
			var stacks := 1.0 if kind != "poison" else maxf(1.0, float(table.get("poisonStacks", 1)))
			damage(state, max_hp * ratio * dt * stacks)
	for key in ["cooldown"]:
		if state.has(key):
			state[key] = maxf(0.0, float(state[key]) - dt)
	state["iframes"] = maxf(0.0, float(state.get("iframes", 0.0)) - dt)


static func summary(state: Dictionary) -> String:
	var stats := PbJson.as_dict(state.get("stats", {}))
	return "%s Lv%d  HP %d/%d  DMGx%.2f  ARM %.1f  CRIT %.0f%%  %d moves" % [
		str(state.get("name", "?")), int(state.get("level", 1)),
		int(state.get("hp", 0)), int(state.get("maxHp", 0)),
		float(stats.get("damage", 1.0)), float(stats.get("armor", 0.0)),
		float(stats.get("critChance", 0.0)) * 100.0, move_keys(state).size(),
	]
