class_name PbEnemies
extends RefCounted
## Enemy pool, structure-of-arrays style like the web build.
##
## The layout mirrors the bundle's typed arrays (offset 346928): positions, hp,
## per-status channels and a flag word per slot. Scaling uses the recovered
## stage factor `(1 + (stage-1)*0.35) * difficulty * enemyAmount` and the tier
## weight chain `f?60 : p?35 : d?25 : m?20 : u?6 : 1` (offset 346928/350290).
##
## Which flag each letter stands for was not fully resolvable from the minified
## source; the mapping below is the one consistent with the run stats
## (legendaries / alphas / elites / totems / summoners) and is marked TODO.

const CAPACITY := 96

const Flag := {
	"Alive": 1,
	"Boss": 2,
	"Elite": 4,
	"Legendary": 8,
	"Alpha": 16,
	"Totem": 32,
	"Summoner": 64,
	"Remote": 128,
	"Parked": 256,
}

## Tier -> weight used by the spawn director's credit pool.
const TIER_WEIGHT := {
	"boss": 12.0,       # tier multiplier applied by spawn(); also the credit weight
	"legendary": 60.0,   # TODO(verify): letter->tier mapping from the minified chain
	"alpha": 35.0,
	"elite": 25.0,
	"totem": 20.0,
	"summoner": 6.0,
	"wild": 1.0,
}


static func create_pool() -> Dictionary:
	var pool := {}
	for key in ["x", "z", "y", "hp", "maxHp", "dmg", "speed", "weight", "scale", "anim", "cd"]:
		pool[key] = []
	for key in ["species", "tier", "flags", "typeA", "typeB"]:
		pool[key] = []
	for kind in PbStatus.KINDS:
		pool[kind] = []
	pool["poisonStacks"] = []
	pool["count"] = 0
	pool["free"] = []
	pool["live"] = []
	for i in CAPACITY:
		for key in pool.keys():
			if key == "count" or key == "free" or key == "live":
				continue
			pool[key].append(0.0 if key in ["x", "z", "y", "hp", "maxHp", "dmg", "speed", "weight", "scale", "anim", "cd"] else 0)
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
static func spawn(pool: Dictionary, species_id: int, x: float, z: float, stage: int,
		diff: Dictionary, tier: String = "wild") -> int:
	if PbJson.as_array(pool["free"]).is_empty():
		return -1
	var index: int = PbJson.as_array(pool["free"]).pop_back()
	var species := PbData.species(species_id)
	if species.is_empty():
		PbJson.as_array(pool["free"]).append(index)
		return -1
	var difficulty := float(diff.get("enemyHp", 1.0))
	var amount := float(diff.get("enemyAmount", 1.0))
	## The web client scales wild HP through its own enemy tables (ft()/an()), which
	## live inside closures and could not be recovered as data. This substitute keys
	## off the species' base-stat total so tougher species stay tougher; the stage
	## factor itself is the recovered one. TODO(reverse): swap in the real table.
	var stats := PbStats.stats_from_species(species, 0.0)
	var bst := float(species.get("bst", 300))
	var stage_factor := 1.0 + float(stage - 1) * 0.35
	var hp := (8.0 + bst * 0.06) * stage_factor * difficulty * amount
	var tier_mult := 1.0
	match tier:
		"elite":
			tier_mult = 2.5
		"alpha":
			tier_mult = 3.5
		"legendary":
			tier_mult = 6.0
		"boss":
			tier_mult = 12.0
	hp *= tier_mult
	set_field(pool, "x", index, x)
	set_field(pool, "z", index, z)
	set_field(pool, "y", index, 0.0)
	set_field(pool, "hp", index, hp)
	set_field(pool, "maxHp", index, hp)
	set_field(pool, "dmg", index, (6.0 + 2.0 * float(stage)) * float(diff.get("enemyDamage", 1.0)))
	set_field(pool, "speed", index, float(stats.get("moveSpeed", 1.0)) * float(diff.get("enemySpeed", 1.0)))
	set_field(pool, "weight", index, float(TIER_WEIGHT.get(tier, 1.0)))
	set_field(pool, "scale", index, clampf(float(species.get("height", 10)) / 10.0, 0.6, 3.0))
	set_field(pool, "cd", index, 0.0)
	set_field(pool, "species", index, species_id)
	var flags := int(Flag["Alive"])
	if tier == "boss":
		flags |= int(Flag["Boss"])
	elif tier == "elite":
		flags |= int(Flag["Elite"])
	elif tier == "legendary":
		flags |= int(Flag["Legendary"])
	elif tier == "alpha":
		flags |= int(Flag["Alpha"])
	set_field(pool, "flags", index, flags)
	var types: Array = PbJson.as_array(species.get("types", ["normal"]))
	set_field(pool, "typeA", index, types[0] if types.size() > 0 else "normal")
	set_field(pool, "typeB", index, types[1] if types.size() > 1 else types[0] if types.size() > 0 else "normal")
	for kind in PbStatus.KINDS:
		set_field(pool, kind, index, 0.0)
	set_field(pool, "poisonStacks", index, 0)
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
	var was_legendary := (int(get_field(pool, "flags", index)) & int(Flag["Legendary"])) != 0
	var was_elite := is_elite(pool, index)
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
		"legendary": was_legendary}


## Apply damage; when HP reaches 0 the slot is released and the kill payload is
## returned so callers do not have to race the alive flag.
## {"dealt": float, "died": bool, "info": Dictionary|null}
static func damage(pool: Dictionary, index: int, amount: float) -> Dictionary:
	if not is_alive(pool, index):
		return {"dealt": 0.0, "died": false, "info": null}
	var hp := maxf(0.0, float(get_field(pool, "hp", index)) - amount)
	set_field(pool, "hp", index, hp)
	if hp <= 0.0:
		return {"dealt": amount, "died": true, "info": kill(pool, index)}
	return {"dealt": amount, "died": false, "info": null}


static func types_of(pool: Dictionary, index: int) -> Array:
	var out: Array = [String(get_field(pool, "typeA", index))]
	var second := String(get_field(pool, "typeB", index))
	if not second.is_empty() and second != out[0]:
		out.append(second)
	return out


static func nearest(pool: Dictionary, x: float, z: float, max_dist: float = 1.0e30) -> int:
	var best := -1
	var best_d := max_dist
	for entry in live_indices(pool):
		var i := int(entry)
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


static func apply_status(pool: Dictionary, index: int, kind: String) -> void:
	if kind.is_empty() or not PbStatus.exists(kind):
		return
	set_field(pool, kind, index, PbStatus.duration(kind))
	if kind == "poison":
		set_field(pool, "poisonStacks", index, mini(5, int(get_field(pool, "poisonStacks", index)) + 1))


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
			var ratio := PbStatus.dps_ratio(kind)
			if ratio > 0.0:
				var stacks := 1.0
				if kind == "poison":
					stacks = maxf(1.0, float(get_field(pool, "poisonStacks", i)))
				var res := damage(pool, i, float(get_field(pool, "maxHp", i)) * ratio * dt * stacks)
				total += float(res["dealt"])
				if bool(res["died"]):
					pool["dot_kills"] = PbJson.as_array(pool.get("dot_kills", [])) + [res["info"]]
	return total


static func flags(pool: Dictionary, index: int) -> int:
	return int(get_field(pool, "flags", index))


static func is_boss(pool: Dictionary, index: int) -> bool:
	return flags(pool, index) & int(Flag["Boss"]) != 0


static func is_elite(pool: Dictionary, index: int) -> bool:
	return flags(pool, index) & (int(Flag["Elite"]) | int(Flag["Boss"])) != 0
