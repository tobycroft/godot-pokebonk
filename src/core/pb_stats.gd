class_name PbStats
extends RefCounted
## Stat derivation, card-modifier application and clamping.
##
## Ported from the bundle:
##   Qy(e,t,n) -> stats_from_species()   (bundle offset 812367)
##   $y(e,t)   -> apply_mod_groups()     (bundle offset 813284)
##   tb(e)     -> finalize()             (bundle offset 813284)
##   rb(e)     -> armor_mitigation()     (bundle offset 813284)
##
## PokeBonk does not use Pokemon's per-level stat formulas: a species' base-stat
## *share* drives every combat stat, and a growth index (level-ish) scales HP and
## overall damage together.

const STAT_KEYS := [
	"maxHp", "regen", "armor", "evasion", "shieldMax", "moveSpeed", "damage",
	"physical", "special", "attackSpeed", "projectiles", "area", "duration",
	"projSpeed", "critChance", "critDamage", "lifesteal", "thorns", "knockback",
	"pickupRange", "xpGain", "gold", "luck", "luckMult", "difficulty",
	"eliteDamage", "extraJumps", "jumpHeight", "statusChance", "statusDamage",
	"healing", "superEffective", "flinch", "bounces", "enemyAmount", "megaCrit",
	"overheal", "powerup", "eliteSpawn", "slam",
]


## species: a pokemon.json record; growth: level-ish index; deltas: extra adds
## (used by the lab / allies) applied additively on top of the derived values.
static func stats_from_species(species: Dictionary, growth: float = 0.0, deltas: Dictionary = {}) -> Dictionary:
	var base := _const("player_stats", {})
	var raw: Dictionary = species.get("stats", {})
	var hp := float(raw.get("hp", 50))
	var atk := float(raw.get("atk", 50))
	var def := float(raw.get("def", 50))
	var spa := float(raw.get("spa", 50))
	var spd := float(raw.get("spd", 50))
	var spe := float(raw.get("spe", 50))
	var bst := hp + atk + def + spa + spd + spe
	if bst <= 0.0:
		bst = 300.0
	var weight := func(v: float) -> float: return v / bst * float(base.get("weight_divisor", 6))
	var o := 1.0 + growth * float(base.get("growth_per_index", 0.12))

	var s := {
		"maxHp": int(round((float(base.get("hp_base", 70)) + float(base.get("hp_span", 45)) * weight.call(hp)) * o)),
		"regen": float(base.get("regen_base", 0.25)) + float(base.get("regen_span", 0.25)) * weight.call(hp),
		"armor": float(base.get("armor_def_weight", 6)) * weight.call(def) + float(base.get("armor_spd_weight", 3)) * weight.call(spd),
		"evasion": float(base.get("evasion_base", 0.02)) + float(base.get("evasion_span", 0.02)) * weight.call(spe),
		"shieldMax": 0,
		"moveSpeed": float(base.get("move_speed_base", 0.92)) + float(base.get("move_speed_span", 0.12)) * weight.call(spe),
		"damage": o,
		"physical": float(base.get("physical_base", 0.82)) + float(base.get("physical_span", 0.2)) * weight.call(atk),
		"special": float(base.get("special_base", 0.82)) + float(base.get("special_span", 0.2)) * weight.call(spa),
		"attackSpeed": 1, "projectiles": 0, "area": 1, "duration": 1, "projSpeed": 1,
		"critChance": float(base.get("crit_chance", 0.05)),
		"critDamage": float(base.get("crit_damage", 1.75)),
		"lifesteal": 0, "thorns": 0, "knockback": 1,
		"pickupRange": float(base.get("pickup_range", 6)),
		"xpGain": 1, "gold": 1, "luck": 0, "luckMult": 1, "difficulty": 1,
		"eliteDamage": 1, "extraJumps": 0, "jumpHeight": 1, "statusChance": 1,
		"statusDamage": 1, "healing": 1, "superEffective": 1, "flinch": 0,
		"bounces": 0, "enemyAmount": 1, "megaCrit": 0, "overheal": 0,
		"powerup": 1, "eliteSpawn": 1, "slam": 1,
		"typeBoost": {},
	}
	for key in deltas.keys():
		s[key] = float(s.get(key, 0)) + float(deltas[key])
	return s


## Port of $y(): mods is either a single Array of mods or an Array of Arrays.
## ``add`` is summed directly; ``mul`` >= 1 is accumulated then applied once per
## group (so two +10% cards give *1.2, not *1.21); ``mul`` < 1 applies at once.
static func apply_mod_groups(stats: Dictionary, mods_groups: Array) -> void:
	var groups := []
	for g in mods_groups:
		groups.append(g if typeof(g) == TYPE_ARRAY else [g])
	for group in groups:
		for mod in group:
			if mod.get("add") != null:
				var stat := str(mod["stat"])
				stats[stat] = float(stats.get(stat, 0)) + float(mod["add"])
	for group in groups:
		var pending := {}
		for mod in group:
			if mod.get("mul") == null:
				continue
			var stat := str(mod["stat"])
			var mul := float(mod["mul"])
			if mul < 1.0:
				stats[stat] = float(stats.get(stat, 0)) * mul
			else:
				pending[stat] = float(pending.get(stat, 0.0)) + mul - 1.0
		for stat in pending.keys():
			stats[stat] = float(stats.get(stat, 0)) * (1.0 + float(pending[stat]))


## Port of tb(): post-processing clamps that several systems rely on.
static func finalize(stats: Dictionary) -> void:
	stats["evasion"] = min(0.6, float(stats.get("evasion", 0)))
	var crit := float(stats.get("critChance", 0))
	stats["_critPreClamp"] = crit
	stats["megaCrit"] = clampf(crit - 1.0, 0.0, 1.0)
	stats["critChance"] = min(1.0, crit)
	stats["overheal"] = min(1.0, float(stats.get("overheal", 0)))
	stats["luckMult"] = 1.0 + float(stats.get("luck", 0)) / 100.0
	stats["attackSpeed"] = max(0.3, float(stats.get("attackSpeed", 1)))


## Port of rb(): armour is a soft cap, not flat reduction.
static func armor_mitigation(armor: float) -> float:
	if armor != armor:  # NaN guard, mirrors the bundle's e===e test
		return 0.0
	if armor >= float(0xe8d4a51000):
		return 0.99999
	return min(0.99999, armor / (armor + float(_const("armor_mitigation", {}).get("half_point", 45))))


static func stats_for(species: Dictionary, growth: float, lab_deltas: Dictionary, mod_groups: Array) -> Dictionary:
	var s := stats_from_species(species, growth, lab_deltas)
	apply_mod_groups(s, mod_groups)
	finalize(s)
	return s


static func _const(path: String, default: Variant) -> Variant:
	return PbData.const_of(path, default)
