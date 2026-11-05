class_name PbEnemies
extends RefCounted
## Enemy pool, structure-of-arrays style like the web build.
##
## Layout mirrors the bundle's typed arrays (offset 346928). Spawn numbers come
## from `spawn()` (offset 346928) with the director multipliers from class `Ab`
## (offset 878271).
##
## Flag bits are the recovered ones (offset 346928): Elite=1, Alpha=2, Boss=4,
## Capture=128, Totem=4096, Summoner=8192, Treasure=16384. The port adds an
## internal Alive bit well outside that range.

const CAPACITY := 96

const Flag := {
	"Alive": 1 << 20,
	"Boss": 4,
	"Elite": 1,
	"Alpha": 2,
	"Flying": 16,
	"Totem": 4096,
	"Summoner": 8192,
	"Treasure": 16384,
	"Capture": 128,
	## Port-only bit for the eclipse event's shiny spawn (the web keeps a
	## separate capture/sprite flag that has no port counterpart).
	"Shiny": 1 << 21,
}

## Credit pool weight of a spawn card (offset 346928: `o`), 1 for singles.
const TIER_WEIGHT := {
	"wild": 1.0, "elite": 1.0, "alpha": 1.0, "boss": 1.0,
	"legendary": 1.0, "totem": 1.0, "summoner": 1.0, "treasure": 1.0,
}


static func create_pool() -> Dictionary:
	var pool := {}
	var floats := ["x", "z", "y", "hp", "maxHp", "dmg", "speed", "weight", "scale", "anim", "cd",
		"xp", "burnDps", "poisonDps", "hazSlow"]
	for key in floats:
		pool[key] = []
	for key in ["species", "tier", "flags", "typeA", "typeB", "gen"]:
		pool[key] = []
	for kind in PbStatus.KINDS:
		pool[kind] = []
	pool["poisonStacks"] = []
	pool["count"] = 0
	pool["free"] = []
	pool["live"] = []
	pool["serial"] = 0
	for i in CAPACITY:
		for key in pool.keys():
			if key == "count" or key == "free" or key == "live":
				continue
			if typeof(pool[key]) != TYPE_ARRAY:
				continue
			pool[key].append(0.0 if key in floats else 0)
		pool["free"].append(i)
	return pool


static func alive_count(pool: Dictionary) -> int:
	return int(pool.get("count", 0))


static func set_field(pool: Dictionary, key: String, index: int, value) -> void:
	PbJson.as_array(pool[key])[index] = value


static func get_field(pool: Dictionary, key: String, index: int):
	return PbJson.as_array(pool[key])[index]


## Indices that are currently alive -- hot loops use this instead of scanning
## the whole capacity.
static func live_indices(pool: Dictionary) -> Array:
	return PbJson.as_array(pool.get("live", []))


static func is_alive(pool: Dictionary, index: int) -> bool:
	if index < 0 or index >= CAPACITY:
		return false
	return int(get_field(pool, "flags", index)) & int(Flag["Alive"]) != 0


## Spawn one enemy of `species_id` at (x,z). Returns the slot or -1 when full.
##
## hp_mult / dmg_mult are the director multipliers (PbCombat.hp_mult/dmg_mult).
## When omitted they fall back to the stage-only curve, which keeps every legacy
## call site working.
static func spawn(pool: Dictionary, species_id: int, x: float, z: float, stage: int,
		diff: Dictionary, tier: String = "wild", hp_mult: float = -1.0,
		dmg_mult: float = -1.0, weight: float = 1.0, stage_t: float = 0.0) -> int:
	if PbJson.as_array(pool["free"]).is_empty():
		return -1
	var index: int = PbJson.as_array(pool["free"]).pop_back()
	var species := PbData.species(species_id)
	if species.is_empty():
		PbJson.as_array(pool["free"]).append(index)
		return -1
	if hp_mult < 0.0:
		hp_mult = PbCombat.hp_mult(stage, stage_t, diff)
	if dmg_mult < 0.0:
		dmg_mult = PbCombat.dmg_mult(stage, stage_t)
	var tough := PbCombat.toughness(PbCombat.eff_time(stage, stage_t))
	var numbers := PbCombat.enemy_numbers(species, tier, hp_mult, dmg_mult,
		weight, tough, PbCombat.speed_mult(stage, stage_t))
	set_field(pool, "x", index, x)
	set_field(pool, "z", index, z)
	set_field(pool, "y", index, 0.0)
	set_field(pool, "hp", index, float(numbers["hp"]))
	set_field(pool, "maxHp", index, float(numbers["hp"]))
	# `this.dmg[s] = ... * i * ...` (@346928) takes only the director's dmgMult;
	# `diff.enemyDamage` is applied once, when the player is hurt (@359832).
	set_field(pool, "dmg", index, float(numbers["dmg"]))
	set_field(pool, "speed", index, float(numbers["speed"]) * float(diff.get("enemySpeed", 1.0)))
	set_field(pool, "weight", index, weight)
	set_field(pool, "xp", index, float(numbers["xp"]))
	set_field(pool, "scale", index, clampf(float(species.get("height", 10)) / 10.0, 0.6, 3.0))
	set_field(pool, "cd", index, 0.0)
	set_field(pool, "hazSlow", index, 1.0)
	set_field(pool, "species", index, species_id)
	set_field(pool, "tier", index, tier)
	set_field(pool, "flags", index, int(Flag["Alive"]) | int(numbers["flags"]))
	# Spawn generation: the web Alpha keeps capture attempts per `n.gen[e]`
	# (Cg.throwBall @544603 / breakFree), so every spawn gets a serial.
	pool["serial"] = int(pool.get("serial", 0)) + 1
	set_field(pool, "gen", index, int(pool["serial"]))
	var types: Array = PbJson.as_array(species.get("types", ["normal"]))
	set_field(pool, "typeA", index, types[0] if types.size() > 0 else "normal")
	set_field(pool, "typeB", index, types[1] if types.size() > 1 else types[0] if types.size() > 0 else "normal")
	for kind in PbStatus.KINDS:
		set_field(pool, kind, index, 0.0)
	set_field(pool, "poisonStacks", index, 0)
	set_field(pool, "burnDps", index, 0.0)
	set_field(pool, "poisonDps", index, 0.0)
	pool["count"] = int(pool.get("count", 0)) + 1
	PbJson.as_array(pool["live"]).append(index)
	return index


static func kill(pool: Dictionary, index: int) -> Variant:
	if not is_alive(pool, index):
		return null
	var species := int(get_field(pool, "species", index))
	var tier_weight := float(get_field(pool, "weight", index))
	var hp := float(get_field(pool, "hp", index))
	var maxhp := float(get_field(pool, "maxHp", index))
	var pos_x := float(get_field(pool, "x", index))
	var pos_z := float(get_field(pool, "z", index))
	var was_boss := is_boss(pool, index)
	var tier_name := str(get_field(pool, "tier", index))
	var was_legendary := tier_name == "legendary"
	var was_elite := is_elite(pool, index)
	var xp := float(get_field(pool, "xp", index))
	set_field(pool, "flags", index, 0)
	set_field(pool, "hp", index, 0.0)
	PbJson.as_array(pool["free"]).append(index)
	var live: Array = pool["live"]
	var at := live.find(index)
	if at >= 0:
		live.remove_at(at)
	pool["count"] = maxi(0, int(pool.get("count", 0)) - 1)
	return {"species": species, "weight": tier_weight, "hp": hp, "maxHp": maxhp,
		"x": pos_x, "z": pos_z, "boss": was_boss, "elite": was_elite,
		"legendary": was_legendary, "tier": tier_name, "xp": xp}


## Apply damage; when HP reaches 0 the slot is released and the kill payload is
## returned so callers do not have to race the alive flag.
## {"dealt": float, "died": bool, "info": Dictionary|null}
static func damage(pool: Dictionary, index: int, amount: float) -> Dictionary:
	if not is_alive(pool, index):
		return {"dealt": 0.0, "died": false, "info": null}
	var before := float(get_field(pool, "hp", index))
	# The active capture encounter is never killed: damage to zero leaves it at
	# 1 % HP so the player can throw a ball (bundle kS.onDefeated @1082804).
	if index == int(pool.get("capture_index", -1)):
		var floor_hp := float(get_field(pool, "maxHp", index)) * 0.01
		if before - amount <= floor_hp:
			set_field(pool, "hp", index, floor_hp)
			return {"dealt": maxf(0.0, before - floor_hp), "died": false, "info": null,
				"capture": true}
	# Alpha lethal hits open `Cg.intercept` instead of killing (@544603): HP is
	# floored at 1 % for the 8 s down window.
	if flags(pool, index) & int(Flag["Alpha"]) != 0:
		var alpha_floor := float(get_field(pool, "maxHp", index)) * 0.01
		if before - amount <= alpha_floor:
			set_field(pool, "hp", index, alpha_floor)
			return {"dealt": maxf(0.0, before - alpha_floor), "died": false, "info": null,
				"alpha": true}
	var hp := maxf(0.0, before - amount)
	set_field(pool, "hp", index, hp)
	if hp <= 0.0:
		return {"dealt": amount, "died": true, "info": kill(pool, index)}
	return {"dealt": amount, "died": false, "info": null}


static func types_of(pool: Dictionary, index: int) -> Array:
	var out: Array = [str(get_field(pool, "typeA", index))]
	var second := str(get_field(pool, "typeB", index))
	if not second.is_empty() and second != out[0]:
		out.append(second)
	return out


static func nearest(pool: Dictionary, x: float, z: float, max_dist: float = 1.0e30,
		skip_index: int = -1) -> int:
	var best := -1
	var best_d := max_dist
	for entry in live_indices(pool):
		var i := int(entry)
		if i == skip_index:
			continue
		var d := sqrt(pow(float(get_field(pool, "x", i)) - x, 2.0) + pow(float(get_field(pool, "z", i)) - z, 2.0))
		if d < best_d:
			best_d = d
			best = i
	return best


static func within(pool: Dictionary, x: float, z: float, radius: float) -> Array:
	var out := []
	for entry in live_indices(pool):
		var i := int(entry)
		var dx := float(get_field(pool, "x", i)) - x
		var dz := float(get_field(pool, "z", i)) - z
		if dx * dx + dz * dz <= radius * radius:
			out.append(i)
	return out


## Apply one status exactly like Wv.strike's status block (offset 746900).
## `duration_stat` is the attacker's stats.duration; `hit` is the damage of the
## hit that applied it (burn/poison DoT scale with that, not with maxHp).
static func apply_status(pool: Dictionary, index: int, kind: String, duration_stat: float = 1.0,
		hit: float = 0.0, status_damage: float = 1.0) -> void:
	if kind.is_empty() or not PbStatus.exists(kind):
		return
	var resist := PbCombat.status_resist(flags(pool, index))
	var seconds := PbCombat.status_seconds(kind, duration_stat, resist, false)
	set_field(pool, kind, index, maxf(float(get_field(pool, kind, index)), seconds))
	if kind == "poison":
		set_field(pool, "poisonStacks", index,
			mini(PbCombat.POISON_STACK_CAP, int(get_field(pool, "poisonStacks", index)) + 1))
		set_field(pool, "poisonDps", index,
			maxf(float(get_field(pool, "poisonDps", index)),
				hit * PbCombat.POISON_DPS_RATIO * status_damage))
		set_field(pool, "healblock", index,
			maxf(float(get_field(pool, "healblock", index)), 5.0 * duration_stat))
	elif kind == "burn":
		set_field(pool, "burnDps", index,
			maxf(float(get_field(pool, "burnDps", index)),
				hit * PbCombat.BURN_DPS_RATIO * status_damage))


## Status upkeep for every live slot; returns total damage dealt by DoTs.
static func tick_statuses(pool: Dictionary, dt: float) -> float:
	var total := 0.0
	# Copy: killing inside the loop mutates the live list.
	var snapshot := live_indices(pool).duplicate()
	for entry in snapshot:
		var i := int(entry)
		if not is_alive(pool, i):
			continue
		for kind in PbStatus.KINDS:
			var t := float(get_field(pool, kind, i))
			if t <= 0.0:
				continue
			set_field(pool, kind, i, maxf(0.0, t - dt))
		# Ob.tick @758500: burn ticks flat, poison scales with its stack count.
		var burn := float(get_field(pool, "burnDps", i))
		if burn > 0.0:
			var burn_res := damage(pool, i, burn * dt)
			total += float(burn_res["dealt"])
			if bool(burn_res["died"]):
				pool["dot_kills"] = PbJson.as_array(pool.get("dot_kills", [])) + [burn_res["info"]]
				continue
			_note_floor_hit(pool, i, burn_res)
		var poison := float(get_field(pool, "poisonDps", i))
		if poison > 0.0:
			var stacks := maxf(1.0, float(get_field(pool, "poisonStacks", i)))
			var poison_res := damage(pool, i, poison * (0.6 + 0.2 * stacks) * dt)
			total += float(poison_res["dealt"])
			if bool(poison_res["died"]):
				pool["dot_kills"] = PbJson.as_array(pool.get("dot_kills", [])) + [poison_res["info"]]
				continue
			_note_floor_hit(pool, i, poison_res)
	return total


## A DoT that lands on the 1 % capture floor still has to open the weak/down
## window, exactly like a direct hit.
static func _note_floor_hit(pool: Dictionary, index: int, res: Dictionary) -> void:
	if bool(res.get("capture", false)):
		var listed := PbJson.as_array(pool.get("dot_capture", []))
		if not listed.has(index):
			pool["dot_capture"] = listed + [index]
	elif bool(res.get("alpha", false)):
		var alphas := PbJson.as_array(pool.get("dot_alpha", []))
		if not alphas.has(index):
			pool["dot_alpha"] = alphas + [index]


static func flags(pool: Dictionary, index: int) -> int:
	return int(get_field(pool, "flags", index))


static func is_boss(pool: Dictionary, index: int) -> bool:
	return flags(pool, index) & int(Flag["Boss"]) != 0


static func is_elite(pool: Dictionary, index: int) -> bool:
	return flags(pool, index) & (int(Flag["Elite"]) | int(Flag["Boss"])) != 0
