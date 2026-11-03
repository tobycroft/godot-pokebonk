class_name PbRun
extends RefCounted
## The run ("partida") director: stages, spawn credits, attacks, pickups,
## level-ups, fusion machine and the settlement record.
##
## Structure follows the bundle's run class (offset 1506673: stage/timers/
## pendingLevels/bossSpawned/stageCleared/splits/fusions/banished/rerolls/skips)
## and the horde director (offset 346928):
##
##     credits += weight * rate * difficulty * enemyAmount      (cap: weight*2 + 10*weight)
##     spawnAllowance = min(MAX_SPAWNS_PER_SEC*0.1, spawnAllowance + MAX_SPAWNS_PER_SEC*dt)
##
## Numbers marked "estimated" are ours; everything else is the recovered formula.

const STAGE_TIME := 60.0            # TODO(reverse): exact stage duration lives in the timer code
const STAGES := 5
const MAX_SPAWNS_PER_SEC := 14.0    # e.MAX_SPAWNS_PER_SEC (estimated magnitude)
const XP_PER_WEIGHT := 3.0          # estimated candy value scaling with tier weight
const GOLD_PER_KILL := 1.5          # estimated


static func create(species_id: int, biome: String = "forest", seed_value: int = 0,
		lab_deltas: Dictionary = {}, mode: String = "standard") -> Dictionary:
	PbRng.seed(seed_value if seed_value != 0 else 12345)
	var actor := PbActor.create(species_id, lab_deltas)
	if actor.is_empty():
		return {}
	var diff := PbJson.as_dict(PbData.const_of("run_difficulty_defaults", {}))
	var state := {
		"seed": seed_value,
		"mode": mode,
		"biome": biome,
		"player": actor,
		"enemies": PbEnemies.create_pool(),
		"diff": diff,
		"stage": 1,
		"stageT": 0.0,
		"time": 0.0,
		"state": "play",
		"aimMode": "auto",
		"credits": 0.0,
		"spawnAllowance": 0.0,
		"pendingLevels": 0,
		"offers": [],
		"bossSpawned": false,
		"bossIndex": -1,
		"stageCleared": false,
		"weather": "clear",
		"weatherT": 0.0,
		"victory": false,
		"endHow": null,
		"gold": 0.0,
		"stats": {"kills": 0, "damage": 0.0, "damageTaken": 0.0, "hits": 0,
			"dodges": 0, "crits": 0, "megaCrits": 0, "bosses": 0, "legendaries": 0,
			"powerUps": 0, "movesLearned": 0, "evolutions": 0, "captures": [],
			"newSeen": [], "killsBy": {}, "splits": []},
		"splits": [],
		"fusions": [],
		"banished": {},
		"rerolls": 0,
		"skips": 0,
		"banishes": 0,
		"orbs": [],
		"messages": [],
	}
	state["player"]["pendingLevels"] = 0
	# The run's growth index follows the player's level (estimated mapping).
	_apply_lab(state, lab_deltas)
	return state


static func _apply_lab(state: Dictionary, lab: Dictionary) -> void:
	state["rerolls"] = int(lab.get("reroll", 0))
	state["skips"] = int(lab.get("skip", 0))
	state["banishes"] = int(lab.get("banish", 0))


## ------------------------------------------------------------------ tick
static func tick(state: Dictionary, dt: float) -> void:
	if String(state.get("state", "play")) != "play":
		return
	var player: Dictionary = state["player"]
	state["time"] = float(state["time"]) + dt
	state["stageT"] = float(state["stageT"]) + dt
	_tick_director(state, dt)
	_tick_player(state, dt)
	_tick_enemies(state, dt)
	_tick_orbs(state, dt)
	PbActor.tick(player, dt)
	var dot_total := PbEnemies.tick_statuses(state["enemies"], dt)
	if dot_total > 0.0:
		state["stats"]["damage"] = float(state["stats"]["damage"]) + dot_total
	var dot_kills: Array = PbJson.as_array(state["enemies"].get("dot_kills", []))
	if not dot_kills.is_empty():
		for k in dot_kills:
			_on_kill_info(state, PbJson.as_dict(k))
		state["enemies"]["dot_kills"] = []
	if float(player.get("hp", 0.0)) <= 0.0 or bool(player.get("dead", false)):
		state["state"] = "over"
		state["endHow"] = "defeat"
	elif int(state["stage"]) > STAGES:
		state["state"] = "over"
		state["endHow"] = "victory"
		state["victory"] = true
	if int(state["pendingLevels"]) > 0 and PbJson.as_array(state["offers"]).is_empty():
		open_offers(state)


static func _tick_director(state: Dictionary, dt: float) -> void:
	var diff: Dictionary = state["diff"]
	var pool: Dictionary = state["enemies"]
	var weight_cap := 0.0
	for entry in PbEnemies.live_indices(pool):
		weight_cap += float(PbEnemies.get_field(pool, "weight", int(entry)))
	var rate := 1.0
	var credits := float(state["credits"]) + weight_cap * rate * dt * float(diff.get("difficulty", 1.0)) \
		* float(diff.get("enemyAmount", 1.0))
	credits = minf(credits, weight_cap * 2.0 + 10.0 * maxf(1.0, weight_cap))
	state["credits"] = credits
	var allowance := minf(MAX_SPAWNS_PER_SEC * 0.1, float(state["spawnAllowance"]) + MAX_SPAWNS_PER_SEC * dt)
	var alive := PbEnemies.alive_count(pool)
	var cap := 24 + 8 * int(state["stage"])
	while allowance >= 1.0 and credits >= 1.0 and alive < cap:
		allowance -= 1.0
		var weight := _pick_wild_weight(state)
		credits -= weight
		var species := _pick_wild_species(state)
		var tier := "wild"
		if PbRng.chance(0.05 + 0.02 * float(state["stage"])):
			tier = "elite"
		elif PbRng.chance(0.01):
			tier = "legendary"
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(14.0, 22.0)
		var px := Vector3.ZERO
		var index := PbEnemies.spawn(pool, species, cos(angle) * dist + player_x(state), sin(angle) * dist + player_z(state),
			int(state["stage"]), diff, tier)
		if index >= 0:
			alive += 1
		state["_last_spawn_species"] = species
	state["spawnAllowance"] = allowance
	credits = maxf(0.0, credits)
	state["credits"] = credits

	if float(state["stageT"]) >= STAGE_TIME and not bool(state["bossSpawned"]):
		spawn_boss(state)
	if bool(state["bossSpawned"]) and not PbEnemies.is_alive(pool, int(state["bossIndex"])) and not bool(state["stageCleared"]):
		state["stageCleared"] = true
		state["splits"].append({"stage": int(state["stage"]), "time": float(state["time"]),
			"kills": int(state["stats"]["kills"]), "level": int(state["player"].get("level", 1))})
		state["stage"] = int(state["stage"]) + 1
		state["stageT"] = 0.0
		state["bossSpawned"] = false
		state["bossIndex"] = -1
		state["stageCleared"] = false
		_message(state, "stage %d" % int(state["stage"]))


static func player_x(state: Dictionary) -> float:
	return float(PbJson.as_dict(state["player"]).get("x", 0.0))


static func player_z(state: Dictionary) -> float:
	return float(PbJson.as_dict(state["player"]).get("z", 0.0))


static func _pick_wild_weight(state: Dictionary) -> float:
	var table := PbJson.as_dict(PbData.const_of("stage_weight_credits", {}))
	var base := 1.0
	if PbRng.chance(0.06):
		base = 6.0
	elif PbRng.chance(0.04):
		base = 2.0
	return base * (1.0 + 0.35 * float(int(state["stage"]) - 1))


static func _pick_wild_species(state: Dictionary) -> int:
	## TODO(port): the web build filters wild spawns by biome and research level;
	## that table was not recoverable, so gen-1 species are sampled uniformly.
	var ids := PbData.dex_ids(1)
	if ids.is_empty():
		return 1
	return int(PbRng.pick(ids))


static func spawn_boss(state: Dictionary) -> void:
	var pool: Dictionary = state["enemies"]
	var diff: Dictionary = state["diff"]
	var legendary := _legendary_for_stage(state)
	var index := PbEnemies.spawn(pool, legendary, player_x(state) + 8.0, player_z(state),
		int(state["stage"]), diff, "boss")
	if index >= 0:
		state["bossSpawned"] = true
		state["bossIndex"] = index
		PbEnemies.set_field(pool, "flags", index, int(PbEnemies.get_field(pool, "flags", index)) | int(PbEnemies.Flag["Boss"]))
		_message(state, "boss! species %d" % legendary)


static func _legendary_for_stage(state: Dictionary) -> int:
	var candidates := []
	for p in PbData.pokemon_list():
		if bool(p.get("legendary", false)) and int(p.get("gen", 1)) == 1:
			candidates.append(int(p["id"]))
	if candidates.is_empty():
		return 150
	return int(candidates[mini(int(state["stage"]) - 1, candidates.size() - 1)])


## ------------------------------------------------------------------ combat
static func _tick_player(state: Dictionary, dt: float) -> void:
	var player: Dictionary = state["player"]
	var moves: Array = PbJson.as_array(player.get("moves", []))
	var actor := PbActor.actor_for_damage(player)
	for i in moves.size():
		var m = moves[i]
		if m == null:
			continue
		var inst := PbJson.as_dict(m)
		var def := PbJson.as_dict(inst.get("def", {}))
		if def.is_empty():
			continue
		var mods := _move_mods(inst, player)
		var built := PbDamage.move_instance(def, actor, int(inst.get("level", 1)), mods)
		inst["computed"] = built
		var cd := float(inst.get("cooldown", 0.0)) - dt
		if cd > 0.0:
			inst["cooldown"] = cd
			continue
		# aimMode 'auto' (the web default) lets every move snap to the closest
		# target within reach; 'manual' restricts acquisition to the move's own reach.
		var radius := maxf(9.0, float(built.get("reach", 0.0))) \
			if String(state.get("aimMode", "auto")) == "auto" else maxf(1.0, float(built.get("reach", 0.0)))
		var target := PbEnemies.nearest(pool_of(state), player_x(state), player_z(state), radius)
		if target < 0:
			inst["cooldown"] = 0.0
			continue
		inst["cooldown"] = float(built.get("cd", 1.0))
		_fire(state, def, built, target)
	# burn the accumulated pending level-ups into offers when idle
	if int(state["pendingLevels"]) > 0 and PbJson.as_array(state["offers"]).is_empty():
		open_offers(state)


static func pool_of(state: Dictionary) -> Dictionary:
	return PbJson.as_dict(state.get("enemies", {}))


static func _move_mods(inst: Dictionary, player: Dictionary) -> Dictionary:
	## vA(level) plus the card mods collected on this move.
	var level := int(inst.get("level", 1))
	var mods := PbDamage.level_mods(level)
	for raw in PbJson.as_array(inst.get("mods", [])):
		var mod := PbJson.as_dict(raw)
		var stat := String(mod.get("stat", ""))
		if stat.is_empty():
			continue
		if mod.has("add"):
			mods[stat] = float(mods.get(stat, 0)) + float(mod["add"])
		elif mod.has("mul"):
			mods[stat] = float(mods.get(stat, 1)) * float(mod["mul"])
	return mods


static func _fire(state: Dictionary, def: Dictionary, built: Dictionary, target: int) -> void:
	var pool := pool_of(state)
	var player: Dictionary = state["player"]
	var count := maxi(1, int(built.get("count", 1)))
	var stats := PbJson.as_dict(player.get("stats", {}))
	for hit in count:
		var ctx := {
			"movedef": def,
			"inst": built,
			"actor": PbActor.actor_for_damage(player),
			"def_types": PbEnemies.types_of(pool, target),
			"weather": String(state.get("weather", "clear")),
			"elite": PbEnemies.is_elite(pool, target),
			"boss": PbEnemies.is_boss(pool, target),
			"exhaust": 1.0,
			"curse": 0,
			"veil": 0,
			"frozen": int(PbEnemies.get_field(pool, "freeze", target) > 0.0),
			"paralysed": int(PbEnemies.get_field(pool, "paralysis", target) > 0.0),
			"asleep": int(PbEnemies.get_field(pool, "sleep", target) > 0.0),
			"shield": 0.0,
			"scope": 1.0,
			"status_count": 0,
		}
		var out := PbDamage.strike(ctx)
		var dmg := float(out["damage"])
		if dmg <= 0.0:
			continue
		var hit_res := PbEnemies.damage(pool, target, dmg)
		var dealt := float(hit_res["dealt"])
		state["stats"]["damage"] = float(state["stats"]["damage"]) + dealt
		state["stats"]["hits"] = int(state["stats"].get("hits", 0)) + 1
		if bool(out["crit"]):
			state["stats"]["crits"] = int(state["stats"].get("crits", 0)) + 1
		if bool(out["mega"]):
			state["stats"]["megaCrits"] = int(state["stats"].get("megaCrits", 0)) + 1
		if out["status"] != null and PbStatus.roll(out["status"], float(out["statusChance"])):
			PbEnemies.apply_status(pool, target, String(out["status"]))
		var drain := float(out["drain"])
		if drain > 0.0:
			PbActor.heal(player, dealt * drain)
		var lifesteal := float(stats.get("lifesteal", 0.0))
		if lifesteal > 0.0:
			PbActor.heal(player, dealt * lifesteal)
		if bool(hit_res["died"]):
			_on_kill_info(state, PbJson.as_dict(hit_res["info"]))
			if hit + 1 < count:
				target = PbEnemies.nearest(pool, player_x(state), player_z(state), 22.0)
				if target < 0:
					return


## Consume a kill payload (from a hit or a damage-over-time tick).
static func _on_kill_info(state: Dictionary, info: Dictionary) -> void:
	if info.is_empty():
		return
	var species := int(info["species"])
	var weight := float(info["weight"])
	var stats: Dictionary = state["stats"]
	stats["kills"] = int(stats["kills"]) + 1
	var kills_by: Dictionary = stats.get("killsBy", {})
	kills_by[species] = int(kills_by.get(species, 0)) + 1
	stats["killsBy"] = kills_by
	if bool(info.get("boss", false)):
		stats["bosses"] = int(stats["bosses"]) + 1
	if bool(info.get("legendary", false)):
		stats["legendaries"] = int(stats["legendaries"]) + 1
	var gold_mult := float(PbJson.as_dict(state["player"].get("stats", {})).get("gold", 1.0))
	state["gold"] = float(state["gold"]) + GOLD_PER_KILL * weight * gold_mult
	_drop_orb(state, weight, float(info["x"]), float(info["z"]))
	var captures: Array = stats.get("captures", [])
	if not captures.has(species):
		captures.append(species)
	stats["captures"] = captures
	var seen: Array = stats.get("newSeen", [])
	if not seen.has(species):
		seen.append(species)
	stats["newSeen"] = seen


## XP candies: the web build drops collectible orbs; the run simulates them as
## pending XP that is collected when the player is close enough.
static func _drop_orb(state: Dictionary, weight: float, x: float, z: float) -> void:
	var value := maxf(1.0, roundf(weight * XP_PER_WEIGHT * (1.0 + 0.25 * float(int(state["stage"]) - 1))))
	state["orbs"].append({
		"x": x,
		"z": z,
		"xp": value,
		"kind": "xp",
		"life": 12.0,
	})


static func _tick_orbs(state: Dictionary, dt: float) -> void:
	var player: Dictionary = state["player"]
	var px := player_x(state)
	var pz := player_z(state)
	var pickup := float(PbJson.as_dict(player.get("stats", {})).get("pickupRange", 6.0))
	var kept := []
	for raw in PbJson.as_array(state["orbs"]):
		var orb := PbJson.as_dict(raw)
		orb["life"] = float(orb["life"]) - dt
		var d := sqrt(pow(float(orb["x"]) - px, 2.0) + pow(float(orb["z"]) - pz, 2.0))
		if d <= pickup:
			if String(orb.get("kind", "xp")) == "xp":
				add_xp(state, float(orb["xp"]))
		elif float(orb["life"]) > 0.0:
			kept.append(orb)
	state["orbs"] = kept


static func add_xp(state: Dictionary, amount: float) -> int:
	var player: Dictionary = state["player"]
	var diff: Dictionary = state["diff"]
	var gained := PbXp.grant(player, amount,
		float(PbJson.as_dict(player.get("stats", {})).get("xpGain", 1.0)),
		float(diff.get("xpMult", 1.0)), String(state.get("mode", "")) == "endless")
	if gained > 0:
		PbActor.recompute(player)
		state["pendingLevels"] = int(state["pendingLevels"]) + gained
	return gained


## ------------------------------------------------------------------ level ups
static func open_offers(state: Dictionary) -> void:
	if int(state["pendingLevels"]) <= 0:
		state["offers"] = []
		state["state"] = "play"
		return
	var player: Dictionary = state["player"]
	state["offers"] = PbCards.offer(player, 3, state["banished"])
	state["state"] = "modal"


static func choose_offer(state: Dictionary, index: int) -> bool:
	var offers: Array = PbJson.as_array(state.get("offers", []))
	if index < 0 or index >= offers.size():
		return false
	var card := PbJson.as_dict(offers[index])
	var player: Dictionary = state["player"]
	PbCards.take(player, card)
	state["stats"]["powerUps"] = int(state["stats"]["powerUps"]) + 1
	state["pendingLevels"] = maxi(0, int(state["pendingLevels"]) - 1)
	state["offers"] = []
	state["state"] = "play"
	if int(state["pendingLevels"]) > 0:
		open_offers(state)
	return true


static func reroll(state: Dictionary) -> bool:
	if int(state["rerolls"]) <= 0:
		return false
	state["rerolls"] = int(state["rerolls"]) - 1
	open_offers(state)
	return true


static func skip(state: Dictionary) -> bool:
	if int(state["skips"]) <= 0:
		return false
	state["skips"] = int(state["skips"]) - 1
	state["offers"] = []
	state["pendingLevels"] = maxi(0, int(state["pendingLevels"]) - 1)
	state["state"] = "play"
	return true


static func banish(state: Dictionary, index: int) -> bool:
	if int(state["banishes"]) <= 0:
		return false
	var offers: Array = PbJson.as_array(state.get("offers", []))
	if index < 0 or index >= offers.size():
		return false
	var card := PbJson.as_dict(offers[index])
	var tag := "%s:%s" % [String(card.get("kind", "")), String(card.get("stat", card.get("type", card.get("move_key", ""))))]
	state["banished"][tag] = true
	state["banishes"] = int(state["banishes"]) - 1
	open_offers(state)
	return true


## ------------------------------------------------------------------ fusion
static func fusion_offers(state: Dictionary) -> Array:
	return PbFusion.offers(PbJson.as_array(PbJson.as_dict(state.get("player", {})).get("moves", [])))


static func fuse(state: Dictionary, offer: Dictionary) -> Dictionary:
	var player: Dictionary = state["player"]
	var inst := PbFusion.apply(PbJson.as_array(player.get("moves", [])), offer)
	if not inst.is_empty():
		state["fusions"].append(String(PbJson.as_dict(offer.get("recipe", {})).get("key", "")))
		_message(state, "fused %s" % String(inst.get("def", {}).get("name", "?")))
	return inst


## ------------------------------------------------------------------ enemies
static func _tick_enemies(state: Dictionary, dt: float) -> void:
	var pool := pool_of(state)
	var player: Dictionary = state["player"]
	var px := player_x(state)
	var pz := player_z(state)
	var stats := PbJson.as_dict(player.get("stats", {}))
	for entry in PbEnemies.live_indices(pool).duplicate():
		var i := int(entry)
		if not PbEnemies.is_alive(pool, i):
			continue
		var dx := px - float(PbEnemies.get_field(pool, "x", i))
		var dz := pz - float(PbEnemies.get_field(pool, "z", i))
		var dist := sqrt(dx * dx + dz * dz)
		if dist > 0.0001:
			var speed := float(PbEnemies.get_field(pool, "speed", i))
			if PbEnemies.get_field(pool, "paralysis", i) > 0.0:
				speed *= 0.5
			if PbEnemies.get_field(pool, "sleep", i) > 0.0 or PbEnemies.get_field(pool, "freeze", i) > 0.0:
				speed = 0.0
			PbEnemies.set_field(pool, "x", i, float(PbEnemies.get_field(pool, "x", i)) + dx / dist * speed * dt)
			PbEnemies.set_field(pool, "z", i, float(PbEnemies.get_field(pool, "z", i)) + dz / dist * speed * dt)
		if dist < 1.4:
			var cd := float(PbEnemies.get_field(pool, "cd", i)) - dt
			if cd <= 0.0:
				PbEnemies.set_field(pool, "cd", i, 1.0)
				# Player invulnerability frames (the bundle tracks Ob.iframes) keep a
				# horde from deleting the player in one overlap cluster.
				if float(player.get("iframes", 0.0)) > 0.0:
					continue
				var raw := float(PbEnemies.get_field(pool, "dmg", i))
				var types: Array = [String(PbEnemies.get_field(pool, "typeA", i))]
				var taken := PbDamage.incoming_to_player(raw, types[0],
					PbJson.as_array(player.get("types", [])), stats, false, String(player.get("ability", "")))
				# evasion
				if PbRng.chance(float(stats.get("evasion", 0.0))):
					state["stats"]["dodges"] = int(state["stats"].get("dodges", 0)) + 1
					continue
				taken = maxf(0.0, taken * float(state["diff"].get("enemyDamage", 1.0)))
				var applied := PbActor.damage(player, taken)
				player["iframes"] = 0.45
				state["stats"]["damageTaken"] = float(state["stats"]["damageTaken"]) + applied
			else:
				PbEnemies.set_field(pool, "cd", i, cd)


## ------------------------------------------------------------------ settle
static func finish(state: Dictionary, how: String = "exit") -> Dictionary:
	state["state"] = "over"
	if state.get("endHow") == null:
		state["endHow"] = how
	return result(state)


## The payload POST /runs/<id>/finish receives; field-for-field what
## api-core.js applyRunResult() reads.
static func result(state: Dictionary) -> Dictionary:
	var player: Dictionary = PbJson.as_dict(state.get("player", {}))
	var moves := []
	for raw in PbJson.as_array(player.get("moves", [])):
		if raw == null:
			continue
		var inst := PbJson.as_dict(raw)
		moves.append({"id": PbJson.as_dict(inst.get("def", {})).get("id", 0),
			"level": int(inst.get("level", 1))})
	var stats := PbJson.as_dict(state.get("stats", {}))
	return {
		"id": "run-%x" % int(state.get("seed", 0)),
		"species": int(player.get("species_id", 0)),
		"finalSpecies": int(player.get("species_id", 0)),
		"biome": String(state.get("biome", "forest")),
		"tier": int(state.get("stage", 1)),
		"stage": int(state.get("stage", 1)),
		"time": float(state.get("time", 0.0)),
		"kills": int(stats.get("kills", 0)),
		"damage": float(stats.get("damage", 0.0)),
		"level": int(player.get("level", 1)),
		"victory": bool(state.get("victory", false)),
		"score": score(state),
		"seed": int(state.get("seed", 0)),
		"moves": moves,
		"items": PbJson.as_dict(player.get("items", {})).keys(),
		"splits": PbJson.as_array(state.get("splits", [])),
		"mode": String(state.get("mode", "standard")),
		"bosses": int(stats.get("bosses", 0)),
		"legendaries": int(stats.get("legendaries", 0)),
		"econ": {"gold": int(state.get("gold", 0))},
		"fusions": PbJson.as_array(state.get("fusions", [])),
		"endHow": state.get("endHow"),
	}


static func score(state: Dictionary) -> int:
	var stats := PbJson.as_dict(state.get("stats", {}))
	return int(roundf(float(stats.get("damage", 0.0)) * 0.01 + float(stats.get("kills", 0)) * 5.0 \
		+ float(int(PbJson.as_dict(state.get("player", {})).get("level", 1))) * 20.0))


static func _message(state: Dictionary, text: String) -> void:
	PbJson.as_array(state["messages"]).append(text)
	if PbJson.as_array(state["messages"]).size() > 40:
		PbJson.as_array(state["messages"]).pop_front()


## Test hook: run the simulation headlessly for `seconds`, auto-picking the first
## card whenever the level-up modal opens. Used by the smoke test.
static func simulate(state: Dictionary, seconds: float, dt: float = 1.0 / 12.0) -> void:
	var steps := int(seconds / dt)
	var log_every := int(30.0 / dt)
	for s in steps:
		_walk_towards_action(state, dt)
		tick(state, dt)
		if String(state.get("state", "play")) == "modal":
			choose_offer(state, 0)
		if s % log_every == 0 and s > 0:
			print("   ... t=%.0fs stage=%d kills=%d level=%d" % [float(state["time"]),
				int(state["stage"]), int(state["stats"]["kills"]), int(state["player"]["level"])])
		if String(state.get("state", "")) == "over":
			return


## Test hook: drive the player the way a competent human would -- pick up nearby
## candies, otherwise kite at weapon range and strafe instead of face-tanking.
static func _walk_towards_action(state: Dictionary, dt: float) -> void:
	var pool := pool_of(state)
	var player: Dictionary = state["player"]
	var px := player_x(state)
	var pz := player_z(state)
	var target_x := px
	var target_z := pz
	var best_d := 14.0
	for raw in PbJson.as_array(state.get("orbs", [])):
		var orb := PbJson.as_dict(raw)
		var d := sqrt(pow(float(orb["x"]) - px, 2.0) + pow(float(orb["z"]) - pz, 2.0))
		if d < best_d:
			best_d = d
			target_x = float(orb["x"])
			target_z = float(orb["z"])
	var idx := PbEnemies.nearest(pool, px, pz, 40.0)
	if target_x == px and target_z == pz and idx >= 0:
		var ex := float(PbEnemies.get_field(pool, "x", idx))
		var ez := float(PbEnemies.get_field(pool, "z", idx))
		var dx := ex - px
		var dz := ez - pz
		var dist := sqrt(dx * dx + dz * dz)
		if dist < 0.001:
			return
		if dist > 6.0:
			target_x = ex
			target_z = ez
		elif dist < 3.5:
			target_x = px - dx
			target_z = pz - dz
		else:
			target_x = px + dz / dist
			target_z = pz - dx / dist
	var mx := target_x - px
	var mz := target_z - pz
	var md := sqrt(mx * mx + mz * mz)
	if md < 0.001:
		return
	var speed := float(PbJson.as_dict(player.get("stats", {})).get("moveSpeed", 1.0)) * 6.0
	var step := minf(speed * dt, md)
	player["x"] = px + mx / md * step
	player["z"] = pz + mz / md * step
	player["facing"] = 2 if mx > 0.0 else 6
