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
## The offer composition is `KS` @1097400: it pushes **2 candidates per owned
## move under cap**, **2 per owned vitamin under vitCap**, **.45 per unowned
## vitamin while a slot is free**, and its new-move block only exists while an
## empty move slot is open. kind_weights() reproduces those counts.

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
##
## KS() @1097230 only builds four card kinds -- `newMove`, `upMove`, `upVit`
## and `newVit`; there is no stat/type card in the level-up pool. Once every
## move is at capOf() and every vitamin slot is full/at vitCap, KS returns an
## empty list and doLevelUp() @1542070 falls back to its heal+gold reward.
static func roll(actor: Dictionary, exclude: Dictionary = {}, stage: int = 1) -> Dictionary:
	var weights := kind_weights(actor, exclude)
	if weights.is_empty():
		return {}
	var kind := str(PbRng.weighted(weights))
	match kind:
		"up_vit":
			return roll_vitamin(actor, exclude, false, stage)
		"new_vit":
			return roll_vitamin(actor, exclude, true, stage)
		"move_upgrade":
			return roll_move_upgrade(actor, exclude, stage)
		"new_move":
			return roll_new_move(actor, exclude)
	return {}


## `KS` candidate counts: [weight, kind]. The web builds a flat candidate list
## and shuffles it, so each kind's share is proportional to these counts.
static func kind_weights(actor: Dictionary, exclude: Dictionary = {}) -> Array:
	var entries := []
	var up_vit := _vitamin_candidates(actor, exclude, false).size()
	if up_vit > 0:
		entries.append([2.0 * float(up_vit), "up_vit"])
	var new_vit := _vitamin_candidates(actor, exclude, true).size()
	if new_vit > 0:
		entries.append([0.45 * float(new_vit), "new_vit"])
	var move_up := _upgradeable_slots(actor, exclude).size()
	if move_up > 0:
		entries.append([2.0 * float(move_up), "move_upgrade"])
	var move_new := new_move_weight(actor, exclude)
	if move_new > 0.0:
		entries.append([move_new, "new_move"])
	return entries


## `KS` @1097230 newMove candidates, counted exactly:
##   * 3 per roster-kit move (`c.kit.forEach(... for(let e=0;e<3;e++))`)
##   * 1 shortlist pick from `by(species)` whose learn level <= level*2.6+10
##     (always when there is no roster, 35% of the time when a roster exists)
##   * 1 at 50% from cross-species league moves (`d` set)
## The port has no roster/league, so only the species shortlist remains: **1**.
## The flat `o` fallback list only fills in when the rolled list is short; it is
## not a separate weight.
static func new_move_weight(actor: Dictionary, exclude: Dictionary = {}) -> float:
	if PbActor.free_slot(actor) < 0:
		return 0.0
	if _new_move_candidates(actor, exclude).is_empty():
		return 0.0
	return 1.0


## Vitamin card: `KS` @1099962 gives 2 upVit offers per owned vitamin below
## vitCap, and a .45 chance of a newVit per unowned one while a slot is free.
static func roll_vitamin(actor: Dictionary, exclude: Dictionary = {}, brand_new: bool = false,
		stage: int = 1) -> Dictionary:
	var candidates := _vitamin_candidates(actor, exclude, brand_new)
	if candidates.is_empty():
		return {}
	var key := str(PbRng.pick(candidates))
	var def := PbVitamins.def_of(key)
	var rarity := _roll_rarity(actor, stage)
	var value := float(RARITY_MULT[clampi(rarity, 0, RARITY_MULT.size() - 1)])
	var preview := PbVitamins.preview(actor, key, value)
	var current_level := PbVitamins.level_of(actor, key)
	return {
		"kind": "new_vit" if brand_new else "up_vit",
		"vit": key,
		"rarity": rarity,
		"level": current_level,
		"next_level": int(preview.get("level", 1)),
		"cap": int(preview.get("cap", PbVitamins.LEVEL_CAP)),
		"mods": PbJson.as_array(preview.get("mods", [])),
		"label": App.ui(str(def.get("name", key))),
		"icon": str(def.get("icon", "")),
		"estimated": false,
	}


## Owned vitamins under vitCap (upVit) or unowned ones while a slot is free
## (newVit). `KS` keys the banished set by `v`+vitamin key.
static func _vitamin_candidates(actor: Dictionary, exclude: Dictionary, brand_new: bool) -> Array:
	var owned := PbVitamins.entries(actor)
	var slot_open := PbVitamins.can_offer_new(actor)
	var out := []
	for key in PbVitamins.defs().keys():
		var key_s := str(key)
		if exclude.has("v" + key_s):
			continue
		var owned_entry := PbJson.as_dict(owned.get(key_s, {}))
		if not owned_entry.is_empty():
			if brand_new:
				continue
			# Owned vitamins stop being offered at the cap (vitCap, not 10).
			if int(owned_entry.get("level", 0)) >= PbVitamins.cap_for(actor):
				continue
			out.append(key_s)
		elif brand_new and slot_open:
			out.append(key_s)
	return out


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


## Ey() @794285: pick 2 distinct stats from the archetype's upgradeable list
## (3 when the rarity multiplier is >= 1.6, i.e. rarity 3/4). Each up carries
## the amount from Ey; the card shows one label per stat (wy @793150).
static func roll_move_upgrade(actor: Dictionary, exclude: Dictionary = {},
		stage: int = 1) -> Dictionary:
	var slots := _upgradeable_slots(actor, exclude)
	if slots.is_empty():
		return {}
	var slot := PbJson.as_dict(PbRng.pick(slots))
	var arch := str(slot.get("arch", "bolt"))
	var pool := _arch_stats(arch).duplicate()
	if pool.is_empty():
		return {}
	var rarity := _roll_rarity(actor, stage)
	var mult := float(RARITY_MULT[clampi(rarity, 0, RARITY_MULT.size() - 1)])
	var count := 3 if mult >= 1.6 else 2
	var ups := []
	var lines := []
	while ups.size() < count and not pool.is_empty():
		var stat := str(pool.pop_at(PbRng.randi_range(0, pool.size() - 1)))
		var mod := _move_up_mod(stat, mult)
		ups.append(mod)
		var value := float(mod["add"]) if mod.has("add") else 1.0 - float(mod.get("mul", 1.0))
		lines.append(_up_label(arch, stat, value))
	return {
		"kind": "move_upgrade",
		"move_key": str(slot["key"]),
		"slot": int(slot["slot"]),
		"stat": str(ups[0].get("stat", "")) if not ups.is_empty() else "",
		"rarity": rarity,
		"ups": ups,
		"mods": ups,
		"level": int(slot.get("level", 1)),
		"next_level": int(slot.get("level", 1)) + 1,
		"cap": int(slot.get("cap", PbActor.MOVE_MAX_LEVEL)),
		"label": "%s · %s" % [str(slot.get("name", "")), " / ".join(lines)],
		"estimated": false,
	}


## Ey()'s per-stat amounts. `mult` is Ot[rarity], not the rarity index.
static func _move_up_mod(stat: String, mult: float) -> Dictionary:
	match stat:
		"dmg":
			return {"stat": stat, "add": 0.22 * mult}
		"cd":
			return {"stat": stat, "mul": 1.0 - minf(0.25, 0.08 * mult)}
		"count":
			return {"stat": stat, "add": float(2 if mult >= 1.6 else 1)}
		"pierce", "bounce":
			return {"stat": stat, "add": float(maxi(1, int(round(mult))))}
		"area":
			return {"stat": stat, "add": 0.15 * mult}
		"speed":
			return {"stat": stat, "add": 0.15 * mult}
		"dur":
			return {"stat": stat, "add": 0.2 * mult}
		"crit":
			return {"stat": stat, "add": 0.05 * mult}
		"status":
			return {"stat": stat, "add": 0.25 * mult}
	return {"stat": stat, "add": 0.0}


## Cy()/wy() labels: count reads "+N golpes" on strike-like archetypes and
## "+N proyectiles" elsewhere; everything else is a percentage.
static func _up_label(arch: String, stat: String, value: float) -> String:
	match stat:
		"count":
			if arch in ["strike", "dash", "smite", "meteor"]:
				return App.ui("+{n} golpe", {"n": int(value)}) if int(value) == 1 \
					else App.ui("+{n} golpes", {"n": int(value)})
			return App.ui("+{n} proyectil", {"n": int(value)}) if int(value) == 1 \
				else App.ui("+{n} proyectiles", {"n": int(value)})
		"pierce":
			return App.ui("+{n} perforación", {"n": int(value)})
		"bounce":
			return App.ui("+{n} rebote", {"n": int(value)})
		"dmg":
			return App.ui("+{pct}% daño", {"pct": int(roundf(value * 100.0))})
		"cd":
			return App.ui("-{pct}% recarga", {"pct": int(roundf(value * 100.0))})
		"area":
			return App.ui("+{pct}% área", {"pct": int(roundf(value * 100.0))})
		"speed":
			return App.ui("+{pct}% velocidad", {"pct": int(roundf(value * 100.0))})
		"dur":
			return App.ui("+{pct}% duración", {"pct": int(roundf(value * 100.0))})
		"crit":
			return App.ui("+{pct}% crítico", {"pct": int(roundf(value * 100.0))})
		"status":
			return App.ui("+{pct}% prob. de estado", {"pct": int(roundf(value * 100.0))})
	return stat


static func _new_move_candidates(actor: Dictionary, exclude: Dictionary) -> Array:
	var species_id := int(actor.get("species_id", 1))
	var owned := _owned_move_ids(actor)
	# KS gates the species shortlist by `HS`'s minimum learn level:
	# `(s.get(e) ?? 0) <= n.level * BS + 10`, BS = 2.6 (@1095527).
	var gate := float(actor.get("level", 1)) * 2.6 + 10.0
	var levels := _learn_levels(species_id)
	var candidates := []
	for key in PbMoves.learnable_moves(species_id):
		if owned.has(key):
			continue
		if exclude.has("m:" + str(key)):
			continue
		if float(levels.get(str(key), 0.0)) > gate:
			continue
		if PbMoves.resolve(str(key)).is_empty():
			continue
		candidates.append(str(key))
	return candidates


## `HS()` @1095541: min learn level per move over the evolution chain.
static func _learn_levels(species_id: int) -> Dictionary:
	var out := {}
	var current_id := species_id
	var guard := 0
	while current_id > 0 and guard < 12:
		guard += 1
		for entry in PbData.learnset(current_id):
			var pair := PbJson.as_array(entry)
			if pair.size() < 2:
				continue
			var move := PbData.move_by_id(int(pair[0]))
			var key := str(move.get("key", ""))
			if key.is_empty():
				continue
			out[key] = mini(int(out.get(key, 999)), int(pair[1]))
		var spec := PbData.species(current_id)
		if spec.get("evoFrom") == null:
			break
		current_id = int(spec["evoFrom"])
	return out


static func roll_new_move(actor: Dictionary, exclude: Dictionary = {}) -> Dictionary:
	var candidates := _new_move_candidates(actor, exclude)
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


static func offer(actor: Dictionary, count: int = 3, banished: Dictionary = {},
		stage: int = 1) -> Array:
	var out := []
	var used := banished.duplicate(true)
	var guard := 0
	while out.size() < count and guard < 40:
		guard += 1
		var card := roll(actor, used, stage)
		if card.is_empty():
			break
		used[_card_key(card, out.size())] = true
		out.append(card)
	return out


## Dedupe key for one offered card, matching the exclude keys roll_* consume.
static func _card_key(card: Dictionary, fallback: int) -> String:
	var kind := str(card.get("kind", ""))
	match kind:
		"new_vit", "up_vit":
			return "v" + str(card.get("vit", ""))
		"new_move", "move_upgrade":
			# The web tags both pools with the same `m`+move.id key, so a
			# banish hit removes the move from upgrades *and* new-move rolls.
			return "m:" + str(card.get("move_key", ""))
		"type":
			return "type:" + str(card.get("type", ""))
	return "stat:" + str(card.get("stat", fallback))


## Applies a chosen card to the actor; returns a human-readable result line.
static func take(actor: Dictionary, card: Dictionary) -> String:
	match str(card.get("kind", "")):
		"new_move":
			var ok := PbActor.learn(actor, str(card["move_key"]), PbActor.free_slot(actor))
			return "learned" if ok else "no free slot"
		"move_upgrade":
			PbActor.upgrade_move(actor, int(card["slot"]), card)
			return "move upgraded"
		"new_vit", "up_vit":
			PbVitamins.add(actor, str(card.get("vit", "")),
				float(RARITY_MULT[clampi(int(card.get("rarity", 0)), 0, RARITY_MULT.size() - 1)]))
			return "vitamin"
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
		var inst := PbJson.as_dict(m)
		var def := PbJson.as_dict(inst.get("def", {}))
		if def.is_empty():
			continue
		out.append({"slot": i, "key": str(def.get("key", "")), "name": str(def.get("name", "")),
			"arch": str(def.get("arch", "")), "level": int(inst.get("level", 1)),
			"cap": PbActor.move_cap(actor, inst)})
	return out


## Owned moves the web still offers upgrades for (level below capOf, not banned).
static func _upgradeable_slots(actor: Dictionary, exclude: Dictionary = {}) -> Array:
	var out := []
	for slot in _owned_slots(actor):
		if int(slot.get("level", 1)) >= int(slot.get("cap", PbActor.MOVE_MAX_LEVEL)):
			continue
		if exclude.has("m:" + str(slot["key"])):
			continue
		out.append(slot)
	return out


## Ob.ownedMoveIds(): owns a move by its key or by either fusion parent. The
## bundle stores parents as move **ids** (`parents.append_array([a.def.id,
## b.def.id])`), so both id and key spellings have to be honoured.
static func _owned_move_ids(actor: Dictionary) -> Array:
	var out := PbActor.move_keys(actor)
	for raw in PbJson.as_array(actor.get("moves", [])):
		if raw == null:
			continue
		for parent in PbJson.as_array(PbJson.as_dict(raw).get("parents", [])):
			if typeof(parent) == TYPE_INT or typeof(parent) == TYPE_FLOAT:
				var def := PbData.move_by_id(int(parent))
				var id_key := str(def.get("key", ""))
				if not id_key.is_empty():
					out.append(id_key)
				continue
			var p := PbJson.as_dict(parent)
			var key := str(p.get("key", p.get("move_key", "")))
			if key.is_empty() and typeof(parent) == TYPE_STRING:
				key = str(parent)
			if not key.is_empty():
				out.append(key)
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
		"difficulty": "Dificultad",
	}
	return App.ui(str(labels.get(stat, stat)))


static func _fmt(mod: Dictionary) -> String:
	if mod.has("add"):
		var v := float(mod["add"])
		if absf(v) < 1.0:
			return "+%d%%" % int(round(v * 100.0))
		return "+%s" % str(v)
	return "+%d%%" % int(round((float(mod.get("mul", 1.0)) - 1.0) * 100.0))
