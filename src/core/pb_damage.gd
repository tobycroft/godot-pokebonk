class_name PbDamage
extends RefCounted
## Damage maths: type effectiveness, per-hit instance numbers and the strike pipeline.
##
## Ported from the bundle with the offsets of the original code:
##   j.effectiveness   (offset 6232)   -> effectiveness()
##   Wv.strike         (offset 746724) -> strike()
##   player hurt path  (offset 846019) -> incoming_to_player()
##   yA / vA / bA / wA / My (offsets 1583829, 795869) -> move_instance()/expected_use()
##
## Constants recovered alongside: ky=0.12 (min cd), Ay=0.6 (min cd for fusions),
## jy=3.4 (fusion area ceiling), Iv=0.5 (mega-crit bonus factor) at offset 795862.

const MIN_CD := 0.12
const FUSION_MIN_CD := 0.6
const AREA_CEILING := 3.4
const MEGA_CRIT_FACTOR := 0.5
const STAB := 1.25
const STAB_ADAPTABILITY := 1.5625
const WEATHER_BOOST := 1.3
const WEATHER_NERF := 0.75
const INCOMING_EFF_MIN := 0.5
const INCOMING_EFF_MAX := 1.6


## PokeBonk compresses the Pokemon chart: 2x -> 1.35, immunity -> 0.5 (you still
## hit for half), 0.5x -> 0.8, and the product is clamped to [0.4, 1.8].
static func effectiveness(atk_type: String, def_types: Array) -> float:
	var idx := PbData.type_index(atk_type)
	if idx < 0:
		return 1.0
	var mult := 1.0
	for dt in def_types:
		var di := PbData.type_index(str(dt))
		if di < 0:
			continue
		var cell := PbData.chart_cell(atk_type, str(dt))
		if cell >= 2.0:
			mult *= 1.35
		elif cell == 0.0:
			mult *= 0.5
		elif cell <= 0.5:
			mult *= 0.8
		else:
			mult *= 1.0
	return clampf(mult, 0.4, 1.8)


## The player-hurt path clamps effectiveness differently (.5 .. 1.6).
static func incoming_effectiveness(atk_type: String, def_types: Array) -> float:
	return clampf(effectiveness(atk_type, def_types), INCOMING_EFF_MIN, INCOMING_EFF_MAX)


## vA(): default per-level modifier set for a move instance.
static func level_mods(level: int) -> Dictionary:
	return {
		"dmg": 1.0 + 0.08 * float(level - 1),
		"cd": 1.0, "count": 0, "area": 1.0, "speed": 1.0, "dur": 1.0,
		"pierce": 0, "crit": 0.0, "status": 1.0, "bounce": 0,
	}


## My(): fused moves scale their area with a soft ceiling.
static func fusion_area_scale(area: float) -> float:
	return minf(AREA_CEILING, 1.25 * pow(maxf(0.3, area if area == area else 1.0), 0.9))


## yA(): turn a resolved move definition + an actor into the numbers an actual
## attack uses. actor keys: stats, types, adaptability, items (Dictionary key->power).
static func move_instance(movedef: Dictionary, actor: Dictionary, level: int = 1, mods: Dictionary = {}) -> Dictionary:
	var inst_mods := mods if not mods.is_empty() else level_mods(level)
	var stats: Dictionary = actor.get("stats", {})
	var arch := str(movedef.get("arch", "bolt"))
	var arch_stats := PbJson.as_array(movedef.get("stats", []))
	var types: Array = actor.get("types", [])
	var move_type := str(movedef.get("type", "normal"))
	var adaptability := bool(actor.get("adaptability", false))

	var base := float(movedef.get("dmg", 10)) * 1.3 * float(inst_mods.get("dmg", 1.0)) * (1.0 + float(level - 1) * 0.04)
	var stab := 1.0
	if types.has(move_type):
		stab = STAB_ADAPTABILITY if adaptability else STAB
	var real := base * float(stats.get("damage", 1.0)) \
		* (float(stats.get("physical", 1.0)) if str(movedef.get("cls", "physical")) == "physical" else float(stats.get("special", 1.0))) \
		* stab * float(PbJson.as_dict(stats.get("typeBoost", {})).get(move_type, 1.0))

	var count := maxi(1, int(float(movedef.get("count", 1)) + float(inst_mods.get("count", 0)) \
		+ (float(stats.get("projectiles", 0)) if arch_stats.has("count") else 0.0)))
	var floor_cd := FUSION_MIN_CD if movedef.get("fusion") != null else MIN_CD
	var cd := maxf(floor_cd, float(movedef.get("cd", 1.0)) * float(inst_mods.get("cd", 1.0)) / maxf(0.0001, float(stats.get("attackSpeed", 1.0))))
	var area := float(movedef.get("area", 1.0)) * fusion_area_scale(float(inst_mods.get("area", 1.0)) * float(stats.get("area", 1.0))) \
		if movedef.get("fusion") != null \
		else float(movedef.get("area", 1.0)) * float(inst_mods.get("area", 1.0)) * float(stats.get("area", 1.0))
	var speed := float(movedef.get("speed", 0.0)) * float(inst_mods.get("speed", 1.0)) * float(stats.get("projSpeed", 1.0))
	var dur := float(movedef.get("dur", 1.0)) * float(inst_mods.get("dur", 1.0)) * float(stats.get("duration", 1.0))
	var pierce := 99 if int(movedef.get("pierce", 0)) >= 99 else int(float(movedef.get("pierce", 0)) + float(inst_mods.get("pierce", 0)))
	var bounce := (int(inst_mods.get("bounce", 0)) + int(stats.get("bounces", 0))) if (arch == "bolt" or arch == "barrage") else 0
	var status_chance := 0.0
	if movedef.get("status") != null:
		status_chance = minf(1.0, float(movedef.get("statusChance", 0.0)) * float(inst_mods.get("status", 1.0)) * float(stats.get("statusChance", 1.0)))
	var crit := minf(1.0, float(stats.get("critChance", 0.0)) + float(movedef.get("critBonus", 0.0)) + float(inst_mods.get("crit", 0.0)))

	var out := {
		"level": level,
		"base": base,
		"real": real,
		"stab": stab,
		"cd": cd,
		"count": count,
		"pulses": int(movedef.get("pulses", 1)),
		"area": area,
		"dur": dur,
		"speed": speed,
		"pierce": pierce,
		"bounce": bounce,
		"statusChance": status_chance,
		"crit": crit,
		"reach": 0.0,
		"use": 0.0,
		"dps": 0.0,
	}
	match arch:
		"bolt", "drain", "homing", "orb", "boomerang", "barrage", "wave":
			out["reach"] = speed * dur
		"dash":
			out["reach"] = speed
		"beam":
			out["reach"] = 14.0 * sqrt(float(stats.get("area", 1.0))) * (1.0 + (float(inst_mods.get("area", 1.0)) - 1.0) * 0.5)
		"cone":
			out["reach"] = area
	out["use"] = expected_use(movedef, out)
	out["dps"] = (float(out["use"]) / cd) if cd > 0.0 and float(out["use"]) > 0.0 else 0.0
	return out


## bA(): expected damage of one activation -- the game's card-ranking heuristic.
static func expected_use(movedef: Dictionary, inst: Dictionary) -> float:
	var real := float(inst.get("real", 0.0))
	match str(movedef.get("arch", "")):
		"bolt", "drain", "homing", "orb", "lob", "barrage", "smite", "meteor", "strike":
			return real * float(inst.get("count", 1))
		"dash", "boomerang", "wave", "aura", "chain":
			return real
		"nova", "spin":
			return real * 0.4 * float(inst.get("pulses", 1)) if int(inst.get("pulses", 1)) > 1 else real
		"beam":
			return real * float(inst.get("dur", 1.0)) * (1.3 if float(movedef.get("power", 0)) >= 110.0 else 1.0) / 0.09
		"cone":
			return real * float(inst.get("dur", 1.0)) / 0.1
		"fusion":
			var fusion = movedef.get("fusion")
			return real * float(fusion["hits"]) if fusion != null else 0.0
	return 0.0


## Wv.strike(): the outgoing damage pipeline. Returns the applied damage plus the
## flags the HUD/VFX need (crit, megaCrit, effectiveness, status to apply).
##
## ctx keys:
##   movedef, inst (from move_instance), actor (stats/types/adaptability/items),
##   def_types (Array), weather, elite (bool), status_count (int), boss (bool),
##   exhaust (float), curse (int), veil (int), frozen (int), paralysed (int),
##   asleep (int), shield (float), scope (float), fixed (bool)
static func strike(ctx: Dictionary) -> Dictionary:
	var movedef := PbJson.as_dict(ctx.get("movedef", {}))
	var inst := PbJson.as_dict(ctx.get("inst", {}))
	var actor := PbJson.as_dict(ctx.get("actor", {}))
	var stats := PbJson.as_dict(actor.get("stats", {}))
	var items := PbJson.as_dict(actor.get("items", {}))
	var def_types: Array = PbJson.as_array(ctx.get("def_types", []))
	var fixed := bool(ctx.get("fixed", false))

	var dmg := float(inst.get("real", 0.0))
	var eff := 1.0
	var crit := false
	var mega := false
	if fixed:
		dmg = float(ctx.get("base_damage", dmg))

	if not fixed:
		# STAB and typeBoost are already inside inst.real (see move_instance), so the
		# strike stage only adds the layers that depend on the *defender* or the run.
		if str(movedef.get("cls", "")) == "physical" and items.has("thick-club"):
			dmg *= 1.0 + minf(0.5, maxf(0.0, float(stats.get("armor", 0.0))) / 200.0) * float(items["thick-club"])
		eff = effectiveness(str(movedef.get("type", "")), def_types)
		dmg *= eff
		if eff > 1.01:
			dmg *= float(stats.get("superEffective", 1.0))
		var w := PbWeather.of(str(ctx.get("weather", "clear")))
		if w.boosts.has(str(movedef.get("type", ""))):
			dmg *= WEATHER_BOOST
		if w.nerfs.has(str(movedef.get("type", ""))):
			dmg *= WEATHER_NERF
		# Ob.bonusDamageMult() (offset 841430) sits right after the weather layer.
		dmg *= float(ctx.get("bonusDamage", 1.0))
		# Flags: Elite | 12290 (Alpha|Totem|Summoner) | Boss all take eliteDamage.
		var flags := int(ctx.get("flags", 0))
		if flags != 0:
			if flags & (PbCombat.FLAG_ELITE | PbCombat.ELITE_FAMILY | PbCombat.FLAG_BOSS) != 0:
				dmg *= float(stats.get("eliteDamage", 1.0))
		elif bool(ctx.get("elite", false)) or bool(ctx.get("boss", false)):
			dmg *= float(stats.get("eliteDamage", 1.0))
		if items.has("binding-band"):
			var cc := int(ctx.get("stunned", 0)) + int(ctx.get("rooted", 0)) + int(ctx.get("paralysed", 0)) \
				+ int(ctx.get("frozen", 0)) + int(ctx.get("asleep", 0))
			if cc > 0:
				dmg *= 1.0 + 0.2 * float(items["binding-band"])
		if items.has("full-heal"):
			dmg *= 1.0 + minf(0.3, 0.06 * int(ctx.get("status_count", 0))) * float(items["full-heal"])
		dmg *= float(ctx.get("scope", 1.0))
		# Av(ability).hitMul (offset 743016): ability-specific multipliers.
		dmg *= PbCombat.ability_hit_mul(str(actor.get("ability", "")), movedef, actor, flags)

		# Crit roll: critChance + megaCrit + move critBonus + pickup's gold synergy.
		var pickup_bonus := minf(0.15, float(stats.get("gold", 0.0)) / 10000.0) \
			if str(actor.get("ability", "")) == "pickup" else 0.0
		var chance := float(stats.get("critChance", 0.0)) + float(stats.get("megaCrit", 0.0)) \
			+ float(movedef.get("critBonus", 0.0)) + pickup_bonus + float(inst.get("critBonusOnly", 0.0)) \
			+ PbCombat.ability_crit_add(str(actor.get("ability", "")), movedef)
		if PbRng.chance(chance):
			crit = true
			dmg *= float(stats.get("critDamage", 1.75))
			if chance > 1.0 and PbRng.chance(chance - 1.0):
				mega = true
				dmg *= 1.0 + MEGA_CRIT_FACTOR * (float(stats.get("critDamage", 1.75)) - 1.0)
		if items.has("stick") and float(items["stick"]) > 0.0 and PbRng.chance(0.03 * float(items["stick"])):
			dmg *= 8.0
		# Endless siege (offset 749555): only while the player camps/idles and the
		# stage has run for more than 300s.
		if not bool(ctx.get("boss", false)) and (flags & PbCombat.FLAG_BOSS) == 0:
			dmg *= float(ctx.get("siege", 1.0))

	if bool(ctx.get("boss", false)):
		var exhaust := float(ctx.get("exhaust", 1.0))
		if exhaust > 0.0:
			dmg *= exhaust
	if int(ctx.get("curse", 0)) > 0:
		dmg *= float(PbStatus.VERIFIED["curse_damage_taken"])
	if int(ctx.get("veil", 0)) == 1:
		dmg *= float(PbStatus.VERIFIED["veil_damage_taken"])
	var frozen := int(ctx.get("frozen", 0))
	if frozen > 0:
		dmg *= float(PbStatus.VERIFIED["frozen_damage_taken"])
		# Ice-heal shatter (offset 749118): each extra freeze stack 1.6 + .3*(n-1).
		if bool(ctx.get("ice_heal", false)):
			dmg *= 1.6 + 0.3 * float(maxi(0, frozen - 1))
	if int(ctx.get("paralysed", 0)) > 0 and str(actor.get("ability", "")) == "beacon":
		dmg *= float(PbStatus.VERIFIED["paralysis_beacon_bonus"])
	if int(ctx.get("poison_stacks", 0)) > 0 and str(actor.get("ability", "")) == "venom-sting":
		dmg *= float(PbStatus.VERIFIED["poison_venom_sting"])
	if str(actor.get("ability", "")) == "effect-spore":
		dmg *= 1.2
	if str(actor.get("ability", "")) == "compound-eyes":
		dmg *= 1.25
	if str(actor.get("ability", "")) == "carnivore":
		dmg *= 1.15
	if int(ctx.get("asleep", 0)) > 0:
		dmg *= float(PbStatus.VERIFIED["asleep_damage_taken"])
		if str(movedef.get("type", "")) in ["ghost", "dark"]:
			dmg *= float(PbStatus.VERIFIED["asleep_ghost_dark_bonus"])

	# Web clamps the hit to 1e30 before shield/HP application (offset 749000).
	if dmg >= 1.0e30:
		dmg = 1.0e30

	var absorbed := 0.0
	var shield := float(ctx.get("shield", 0.0))
	if shield > 0.0:
		var breaker := 3.0 if str(movedef.get("type", "")) == "fighting" else 1.0
		absorbed = minf(shield, dmg * breaker)
		shield -= absorbed
		dmg = maxf(0.0, dmg - absorbed / breaker)

	return {
		"damage": dmg,
		"crit": crit,
		"mega": mega,
		"effectiveness": eff,
		"shield": shield,
		"absorbed": absorbed,
		"status": movedef.get("status"),
		"statusChance": float(inst.get("statusChance", 0.0)),
		"drain": float(movedef.get("drain", 0.0)),
	}


## Player-hurt path (offset 846019): effectiveness clamp, armour, ability branches.
## `flags` lets the caller add the 12290/boss status resist; `level` feeds the
## battle-armour hurtMod.
static func incoming_to_player(raw: float, atk_type: String, def_types: Array, stats: Dictionary, special: bool, ability: String, level: int = 1) -> float:
	var dmg := raw
	if dmg != dmg:  # Number.isFinite guard in the web build
		dmg = 1.0e300
	dmg *= maxf(INCOMING_EFF_MIN, minf(INCOMING_EFF_MAX, effectiveness(atk_type, def_types)))
	dmg *= 1.0 - PbStats.armor_mitigation(float(stats.get("armor", 0.0)))
	if ability == "magic-guard" and special:
		dmg *= 0.7
	if ability == "multiscale" and float(stats.get("hp", -1.0)) >= float(stats.get("maxHp", 0.0)) - 0.5:
		dmg *= 0.5
	dmg *= PbCombat.dmg_taken(ability)
	# Av(ability).hurtMod (offset 743016): battle-armor.
	dmg = PbCombat.ability_hurt_mod(ability, dmg, level)
	return maxf(0.0, dmg)


## Ob.hurt() floor/cap block (offset 846019): applied after all multipliers and
## before the tm-iron buff / overheal / shield / HP absorption.
static func apply_incoming_floor_cap(dmg: float, raw: float, max_hp: float, floor: float, cap: float) -> float:
	var out := dmg
	if floor > 0.0:
		# max(dmg, maxHp*floor*(1-.35*(1-min(1,dmg/raw)))
		var ratio := 1.0 if raw <= 0.0 else minf(1.0, out / raw)
		out = maxf(out, max_hp * floor * (1.0 - 0.35 * (1.0 - ratio)))
	if cap > 0.0:
		out = minf(out, max_hp * cap)
	return out
