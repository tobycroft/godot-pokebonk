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

## Web has no fixed stage timer: the guardian is awakened at an altar and the
## stage ends when the portal is taken (Ab.update @884400). The port keeps a
## timed guardian to stay playable headlessly -- 待确认.
const STAGE_TIME := 60.0
const STAGES := 5
const MAX_SPAWNS_PER_SEC := 1800.0  # Ab.MAX_SPAWNS_PER_SEC @876500
const SPAWN_ALLOWANCE_CAP := 180.0  # 0.1 * MAX_SPAWNS_PER_SEC
## credit() @765300: goldFrac += .2 * stats.gold * weight
const GOLD_PER_KILL := 0.2


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
		"baseWeather": "clear",
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
	# Bundle @1513275: base weather = F.pick(biome.weather) for regular stages
	# (sanctuaries/towers stay clear), then weather abilities override it.
	# `standard` is the port's regular-stage mode.
	var base_weather := "clear"
	if mode == "standard":
		var weather_pool := PbJson.as_array(PbData.biome(biome).get("weather", []))
		if not weather_pool.is_empty():
			base_weather = str(PbRng.pick(weather_pool))
	base_weather = _ability_weather(str(actor.get("ability", "")), base_weather)
	state["baseWeather"] = base_weather
	state["weather"] = base_weather
	# The run's growth index follows the player's level (estimated mapping).
	_apply_lab(state, lab_deltas)
	return state


static func _apply_lab(state: Dictionary, lab: Dictionary) -> void:
	state["rerolls"] = int(lab.get("reroll", 0))
	state["skips"] = int(lab.get("skip", 0))
	state["banishes"] = int(lab.get("banish", 0))


## Weather abilities overwrite the biome's base weather (bundle `sb(ability)`).
static func _ability_weather(ability: String, base: String) -> String:
	var map := {
		"drizzle": "rain",
		"drought": "sun",
		"sand-stream": "sand",
		"snow-warning": "hail",
	}
	return str(map.get(ability, base))


## ------------------------------------------------------------------ tick
static func tick(state: Dictionary, dt: float) -> void:
	if str(state.get("state", "play")) != "play":
		return
	var player: Dictionary = state["player"]
	state["time"] = float(state["time"]) + dt
	state["stageT"] = float(state["stageT"]) + dt
	# siegeMult (offset 1399900): after 300s the endless director ramps up damage
	# while the player stays put -- `v(max(camp, idle))` with grace 20 / ramp 40 /
	# floor .3. `idle` grows while still; `camp` grows while inside the 12-unit
	# anchor radius and drops by 15 on leaving it.
	var moved := absf(float(player.get("x", 0.0)) - float(state.get("lastX", 0.0))) \
		+ absf(float(player.get("z", 0.0)) - float(state.get("lastZ", 0.0)))
	state["siegeIdle"] = float(state.get("siegeIdle", 0.0)) + dt if moved < 0.02 else 0.0
	state["lastX"] = float(player.get("x", 0.0))
	state["lastZ"] = float(player.get("z", 0.0))
	if float(state["time"]) >= 300.0:
		var camp_x := float(state.get("campX", float(player.get("x", 0.0))))
		var camp_z := float(state.get("campZ", float(player.get("z", 0.0))))
		var camp := float(state.get("camp", 0.0))
		var away := Vector2(float(player.get("x", 0.0)) - camp_x,
			float(player.get("z", 0.0)) - camp_z).length()
		if away > 12.0:
			camp_x = float(player.get("x", 0.0))
			camp_z = float(player.get("z", 0.0))
			camp = maxf(0.0, camp - 15.0)
		else:
			camp += dt
		state["campX"] = camp_x
		state["campZ"] = camp_z
		state["camp"] = camp
	# Weather moves set a temporary weather (bundle: setWeather); once the timer
	# runs out the stage's base weather comes back.
	if float(state.get("weatherT", 0.0)) > 0.0:
		state["weatherT"] = maxf(0.0, float(state["weatherT"]) - dt)
		if float(state["weatherT"]) <= 0.0:
			state["weather"] = str(state.get("baseWeather", "clear"))
	_tick_director(state, dt)
	# Boss.exhaust() fight clock: only ticks while the current boss is alive.
	if bool(state.get("bossSpawned", false)) \
			and PbEnemies.is_alive(state["enemies"], int(state.get("bossIndex", -1))):
		state["bossFightT"] = float(state.get("bossFightT", 0.0)) + dt
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
		# Web death order (bundle @848700): a Revivir Máximo charge restores 60%
		# HP with 3s of i-frames before the run actually ends.
		if _try_revive(state):
			pass
		else:
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
	var stage := int(state["stage"])
	var stage_t := float(state["stageT"])
	var stats := PbJson.as_dict(state["player"].get("stats", {}))
	var difficulty := float(stats.get("difficulty", 1.0)) * float(stats.get("enemyAmount", 1.0))
	var live_cap := mini(PbEnemies.CAPACITY, PbCombat.enemy_cap(stage, stage_t))
	var rate := PbCombat.credit_rate(stage, stage_t, difficulty,
		float(diff.get("enemyAmount", 1.0)))
	var credits := float(state["credits"]) + rate * dt
	# Ab.update @884400: credits cap = rate*2 + 10*weight (weight is 1 at 1x population).
	credits = minf(credits, rate * 2.0 + 10.0)
	state["credits"] = credits
	var allowance := minf(SPAWN_ALLOWANCE_CAP,
		float(state["spawnAllowance"]) + PbCombat.MAX_SPAWNS_PER_SEC * dt)
	var alive := PbEnemies.alive_count(pool)
	var hp_multiplier := PbCombat.hp_mult(stage, stage_t, diff, difficulty)
	var dmg_multiplier := PbCombat.dmg_mult(stage, stage_t)
	while allowance >= 1.0 and alive < live_cap:
		var species := _pick_wild_species(state)
		var species_def := PbData.species(species)
		if species_def.is_empty():
			break
		var cost := PbCombat.spawn_cost(float(species_def.get("bst", 300.0)))
		if credits < cost:
			break
		credits -= cost
		allowance -= 1.0
		var tier := "wild"
		if PbRng.chance(PbCombat.elite_chance(stage, stage_t,
				float(stats.get("difficulty", 1.0)), 1.0)):
			tier = "elite"
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(14.0, 22.0)
		var index := PbEnemies.spawn(pool, species,
			cos(angle) * dist + player_x(state), sin(angle) * dist + player_z(state),
			stage, diff, tier, hp_multiplier, dmg_multiplier, 1.0, stage_t)
		if index >= 0:
			alive += 1
		state["_last_spawn_species"] = species
	state["spawnAllowance"] = allowance
	state["credits"] = maxf(0.0, credits)

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


## Danger meter (bundle director.danger @882422 = 0.5*log2(hpMult*dmgMult*
## enemyDamage*enemyAmount*enemySpeed^2)). The hpMult/dmgMult/ve inputs live in
## unrecoverable closures, so we feed the port's own stage/time multipliers --
## same shape, estimated magnitude, mirrored by tools-re/golden_values.py.
static func danger(state: Dictionary) -> float:
	var diff := PbJson.as_dict(state.get("diff", {}))
	var stage := float(int(state.get("stage", 1)))
	var time := float(state.get("time", 0.0))
	var hp_mult := 1.0 + (stage - 1.0) * 0.35
	var dmg_mult := (1.0 + time / 60.0 * 0.13) * hp_mult
	var raw := hp_mult * dmg_mult * float(diff.get("enemyDamage", 1.0)) \
		* float(diff.get("enemyAmount", 1.0)) * float(diff.get("enemySpeed", 1.0)) \
		* float(diff.get("enemySpeed", 1.0))
	return 0.5 * (log(maxf(1.0, raw)) / log(2.0))


static func _try_revive(state: Dictionary) -> bool:
	var player: Dictionary = state["player"]
	if int(player.get("revives", 0)) <= 0:
		return false
	player["revives"] = int(player.get("revives", 0)) - 1
	player["hp"] = float(player.get("maxHp", 100.0)) * 0.6
	player["dead"] = false
	player["iframes"] = 3.0
	_message(state, App.ui("¡Revivir Máximo!"))
	return true


static func player_x(state: Dictionary) -> float:
	return float(PbJson.as_dict(state["player"]).get("x", 0.0))


static func player_z(state: Dictionary) -> float:
	return float(PbJson.as_dict(state["player"]).get("z", 0.0))


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
	var stage_t := float(state["stageT"])
	var zone := float(PbCombat.BOSS_ZONE_HP[mini(maxi(int(state["stage"]) - 1, 0),
		PbCombat.BOSS_ZONE_HP.size() - 1)])
	var index := PbEnemies.spawn(pool, legendary, player_x(state) + 8.0, player_z(state),
		int(state["stage"]), diff, "boss",
		PbCombat.hp_mult(int(state["stage"]), stage_t, diff,
			float(PbJson.as_dict(state["player"].get("stats", {})).get("difficulty", 1.0))) \
			* PbCombat.BOSS_HP_BONUS * zone,
		PbCombat.dmg_mult(int(state["stage"]), stage_t), 1.0, stage_t)
	if index >= 0:
		state["bossSpawned"] = true
		state["bossIndex"] = index
		state["bossFightT"] = 0.0
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
			if str(state.get("aimMode", "auto")) == "auto" else maxf(1.0, float(built.get("reach", 0.0)))
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


## Ob.heal() @843232: in endless the healing rate decays after 30 minutes
## (news `sn`), and a wound halves it.
static func _heal_mult(state: Dictionary) -> float:
	var mult := 1.0
	if str(state.get("mode", "")) == "endless":
		var minutes := float(state.get("time", 0.0)) / 60.0
		mult *= maxf(0.3, 1.0 - 0.025 * maxf(0.0, minutes - 30.0))
	if bool(PbJson.as_dict(state.get("player", {})).get("wound", false)):
		mult *= 0.5
	return mult


static func _move_mods(inst: Dictionary, player: Dictionary) -> Dictionary:
	## vA(level) plus the card mods collected on this move.
	var level := int(inst.get("level", 1))
	var mods := PbDamage.level_mods(level)
	for raw in PbJson.as_array(inst.get("mods", [])):
		var mod := PbJson.as_dict(raw)
		var stat := str(mod.get("stat", ""))
		if stat.is_empty():
			continue
		if mod.has("add"):
			mods[stat] = float(mods.get(stat, 0)) + float(mod["add"])
		elif mod.has("mul"):
			mods[stat] = float(mods.get(stat, 1)) * float(mod["mul"])
	return mods


static func _fire(state: Dictionary, def: Dictionary, built: Dictionary, target: int) -> void:
	# Weather archetype (rain dance / sunny day / sandstorm / hail): the web
	# applies it on cast (case 'weather'), before any damage roll.
	var cast_weather := str(def.get("weather", ""))
	if not cast_weather.is_empty():
		state["weather"] = cast_weather
		state["weatherT"] = float(built.get("dur", 0.0))
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
			"weather": str(state.get("weather", "clear")),
			"flags": PbEnemies.flags(pool, target),
			"elite": PbEnemies.is_elite(pool, target),
			"boss": PbEnemies.is_boss(pool, target),
			"exhaust": PbCombat.boss_exhaust(float(state.get("bossFightT", 0.0))) \
				if target == int(state.get("bossIndex", -1)) else 1.0,
			"curse": int(PbEnemies.get_field(pool, "curse", target) > 0.0),
			"veil": int(PbEnemies.get_field(pool, "confusion", target) > 0.0),
			"frozen": int(PbEnemies.get_field(pool, "freeze", target) > 0.0),
			"paralysed": int(PbEnemies.get_field(pool, "paralysis", target) > 0.0),
			"asleep": int(PbEnemies.get_field(pool, "sleep", target) > 0.0),
			"poison_stacks": int(PbEnemies.get_field(pool, "poisonStacks", target)),
			"shield": 0.0,
			"scope": 1.0,
			"status_count": 0,
			# Ob.bonusDamageMult() @841430 / siegeMult @749555.
			"bonusDamage": PbCombat.bonus_damage_mult(player, state, str(state.get("weather", "clear"))),
			"ice_heal": str(player.get("ability", "")) == "ice-heal",
			"siege": PbCombat.siege_mult(maxf(float(state.get("camp", 0.0)),
				float(state.get("siegeIdle", 0.0))),
				float(state.get("time", 0.0)), str(state.get("mode", "")) == "endless"),
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
			PbEnemies.apply_status(pool, target, str(out["status"]),
				float(stats.get("duration", 1.0)), dealt, float(stats.get("statusDamage", 1.0)))
		var drain := float(out["drain"])
		if drain > 0.0:
			PbActor.heal(player, dealt * drain, _heal_mult(state))
		var lifesteal := float(stats.get("lifesteal", 0.0))
		if lifesteal > 0.0:
			PbActor.heal(player, dealt * lifesteal, _heal_mult(state))
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
	# credit() @765300: the orb carries the enemy's own xp value; run.diff.xpMul
	# is applied again when the orb is collected (addXp @843900).
	_drop_orb(state, float(info.get("xp", 1.0)), float(info["x"]), float(info["z"]))
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
static func _drop_orb(state: Dictionary, xp_value: float, x: float, z: float) -> void:
	var value := maxf(0.1, xp_value)
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
			if str(orb.get("kind", "xp")) == "xp":
				add_xp(state, float(orb["xp"]))
		elif float(orb["life"]) > 0.0:
			kept.append(orb)
	state["orbs"] = kept


static func add_xp(state: Dictionary, amount: float) -> int:
	var player: Dictionary = state["player"]
	var diff: Dictionary = state["diff"]
	var gained := PbXp.grant(player, amount,
		float(PbJson.as_dict(player.get("stats", {})).get("xpGain", 1.0)),
		float(diff.get("xpMult", 1.0)), str(state.get("mode", "")) == "endless")
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
	var tag := "%s:%s" % [str(card.get("kind", "")), str(card.get("stat", card.get("type", card.get("move_key", ""))))]
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
		state["fusions"].append(str(PbJson.as_dict(offer.get("recipe", {})).get("key", "")))
		_message(state, "fused %s" % str(inst.get("def", {}).get("name", "?")))
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
			# Ob.tick @758500: chilled enemies lose 35% speed, paralysis halves it,
			# sleep/freeze stop it entirely.
			if PbEnemies.get_field(pool, "chill", i) > 0.0:
				speed *= 0.65
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
				# Ob.hurt() @846019 rolls evasion before any mitigation.
				if PbRng.chance(float(stats.get("evasion", 0.0))):
					state["stats"]["dodges"] = int(state["stats"].get("dodges", 0)) + 1
					continue
				var raw := float(PbEnemies.get_field(pool, "dmg", i))
				var types: Array = [str(PbEnemies.get_field(pool, "typeA", i))]
				var taken := PbDamage.incoming_to_player(raw, types[0],
					PbJson.as_array(player.get("types", [])), stats, false,
					str(player.get("ability", "")), int(player.get("level", 1)))
				taken = maxf(0.0, taken * float(state["diff"].get("enemyDamage", 1.0)))
				# Contact hits carry no floor/cap config in the web build; the
				# pipeline is wired for hazard/projectile overrides.
				taken = PbDamage.apply_incoming_floor_cap(taken, raw, float(player.get("maxHp", 1.0)), 0.0, 0.0)
				var applied := PbActor.damage(player, taken)
				player["iframes"] = 0.45
				state["stats"]["damageTaken"] = float(state["stats"]["damageTaken"]) + applied
				# Ob.hurt() thorns: stats.thorns * (1+level*.05), fixed steel hit.
				var thorns := float(stats.get("thorns", 0.0))
				if thorns > 0.0 and not bool(player.get("dead", false)):
					PbEnemies.damage(pool, i, thorns * (1.0 + float(player.get("level", 1)) * 0.05))
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
		"biome": str(state.get("biome", "forest")),
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
		"mode": str(state.get("mode", "standard")),
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
		if str(state.get("state", "play")) == "modal":
			choose_offer(state, 0)
		if s % log_every == 0 and s > 0:
			print("   ... t=%.0fs stage=%d kills=%d level=%d" % [float(state["time"]),
				int(state["stage"]), int(state["stats"]["kills"]), int(state["player"]["level"])])
		if str(state.get("state", "")) == "over":
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
