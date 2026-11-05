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

## Web has no fixed stage timer. The guardian is awakened from a `boss` altar
## (interactable @1303414) and the stage ends when the guardian dies and the
## portal is taken (onBossKilled @1529103 / enterPortal @1532894). The one
## stage-time milestone in the bundle is the final swarm at 600 s (@1558002);
## it never wakes the guardian.
const STAGE_TIME := 600.0
## `boss` interactable radius: add() bumps the 2.6 default to 4 (@1288807), and
## the prompt gate adds .8 (nearest @1310201). `portal` uses 3.4 (@1288785).
const ALTAR_RADIUS := 4.0
const PORTAL_RADIUS := 3.4
const MAX_SPAWNS_PER_SEC := 1800.0  # Ab.MAX_SPAWNS_PER_SEC @876500
const SPAWN_ALLOWANCE_CAP := 180.0  # 0.1 * MAX_SPAWNS_PER_SEC
## credit() @765300: goldFrac += .2 * stats.gold * weight
const GOLD_PER_KILL := 0.2


## Web stage count is per biome: `stage>=4 || stage>=3 && !biome.sanctuary`
## (@1532894). Sanctuary biomes (forest/desert/coast/glacier) clear on stage 4;
## graveyard/volcano clear on stage 3.
static func stage_count(state: Dictionary) -> int:
	var biome := PbData.biome(str(state.get("biome", "forest")))
	return 4 if not PbJson.as_dict(biome.get("sanctuary", {})).is_empty() else 3


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
		"altarX": 0.0,
		"altarZ": 0.0,
		"altarStage": 0,
		"altarUsed": false,
		"portalX": 0.0,
		"portalZ": 0.0,
		"portalOpen": false,
		"weather": "clear",
		"baseWeather": "clear",
		"weatherT": 0.0,
		"weatherDone": [],
		"victory": false,
		"endHow": null,
		"gold": 0.0,
		"stats": {"kills": 0, "damage": 0.0, "damageTaken": 0.0, "hits": 0,
			"dodges": 0, "crits": 0, "megaCrits": 0, "bosses": 0, "legendaries": 0,
			"powerUps": 0, "movesLearned": 0, "evolutions": 0, "captured": [],
			"allies": [], "newSeen": [], "killsBy": {}, "splits": []},
		"splits": [],
		"fusions": [],
		"banished": {},
		"rerolls": 0,
		"skips": 0,
		"banishes": 0,
		"orbs": [],
		"messages": [],
		"shop": {},
		"shopBuys": [],
		"shopRerolls": 0,
		"shopVisit": 0,
		"meowth": false,
		"meowthT": PbShop.npc_num("first_arrival", 210.0),
		"meowthLeft": 0.0,
		"meowthX": 0.0,
		"meowthZ": 0.0,
		"goldSpent": 0.0,
		"econ": {"shop": 0, "sold": 0},
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
	# kS capture encounter (bundle @1074615): one capturable legendary per stage.
	PbCapture.create(state)
	# The web places the `boss` altar when the stage's interactables populate.
	place_altar(state)
	# The run's growth index follows the player's level (estimated mapping).
	_apply_lab(state, lab_deltas)
	# First evolution plan (bundle planEvolution @1514341). Runs have no roster
	# mode, so this is the plain runEvolution result raised to the start level.
	state["nextEvo"] = PbEvo.plan_evolution(actor, int(actor.get("level", 1)))
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


## `state.weather` is a plain id string. GDScript's `str(null)` is the literal
## "<null>", so any null read (a move def without a `weather` key, a save that
## predates the field) must not reach the state -- the HUD echoes it verbatim.
static func _weather_id(value: Variant, fallback: String = "clear") -> String:
	var w := PbJson.as_string(value, "")
	return fallback if w.is_empty() or w == "<null>" else w


## Fill a restored/imported run state with the defaults the web's run init
## (@1506897: weather/baseWeather `clear`, weatherT 0) and the later systems
## need. A state built by create() already has all of them; this keeps an older
## save playable instead of letting a null weather/stage leak into the tick.
## The map-event channel (`weatherEvent`) is added by PbWeatherEvents.ensure and
## old saves that stored an event id in `weather` are normalized there.
static func ensure_state(state: Dictionary) -> Dictionary:
	var base := _weather_id(state.get("baseWeather"))
	state["baseWeather"] = base
	state["weather"] = _weather_id(state.get("weather"), base)
	if typeof(state.get("weatherT")) != TYPE_FLOAT and typeof(state.get("weatherT")) != TYPE_INT:
		state["weatherT"] = 0.0
	if not (state.get("weatherDone") is Array):
		state["weatherDone"] = []
	if (typeof(state.get("stage")) != TYPE_FLOAT and typeof(state.get("stage")) != TYPE_INT) \
			or int(state.get("stage", 0)) <= 0:
		state["stage"] = 1
	if typeof(state.get("stageT")) != TYPE_FLOAT and typeof(state.get("stageT")) != TYPE_INT:
		state["stageT"] = 0.0
	if typeof(state.get("shopVisit")) != TYPE_FLOAT and typeof(state.get("shopVisit")) != TYPE_INT:
		state["shopVisit"] = 0
	if not (state.get("shop") is Dictionary):
		state["shop"] = {}
	if not (state.get("shopBuys") is Array):
		state["shopBuys"] = []
	if typeof(state.get("shopRerolls")) != TYPE_FLOAT and typeof(state.get("shopRerolls")) != TYPE_INT:
		state["shopRerolls"] = 0
	if not (state.get("fusions") is Array):
		state["fusions"] = []
	var player := PbJson.as_dict(state.get("player", {}))
	if not player.is_empty():
		if typeof(player.get("evo_stage")) != TYPE_FLOAT and typeof(player.get("evo_stage")) != TYPE_INT:
			player["evo_stage"] = 0
		if not (player.get("vitamins") is Dictionary):
			player["vitamins"] = {}
		player["pendingLevels"] = int(player.get("pendingLevels", 0))
		state["player"] = player
		if state.get("nextEvo") == null:
			state["nextEvo"] = PbEvo.plan_evolution(player, int(player.get("level", 1)))
	var stats := {
		"kills": 0, "damage": 0.0, "damageTaken": 0.0, "hits": 0, "dodges": 0,
		"crits": 0, "megaCrits": 0, "bosses": 0, "legendaries": 0, "powerUps": 0,
		"movesLearned": 0, "evolutions": 0, "captured": [], "allies": [],
		"newSeen": [], "killsBy": {}, "splits": [],
	}
	for key in PbJson.as_dict(state.get("stats", {})).keys():
		stats[key] = state["stats"][key]
	if not (stats.get("captured") is Array):
		stats["captured"] = []
	state["stats"] = stats
	if str(state.get("mode", "standard")) == "standard" and not (state.get("capture") is Dictionary):
		PbCapture.create(state)
	# Old saves predate the altar/portal pair. A state that was already auto-woken
	# keeps a dimmed altar (used=true) and stays playable: the guardian is on the
	# field and the altar must not summon a second one.
	if (typeof(state.get("altarStage")) != TYPE_FLOAT and typeof(state.get("altarStage")) != TYPE_INT):
		state["altarStage"] = 0
	if typeof(state.get("altarUsed")) != TYPE_BOOL:
		state["altarUsed"] = false
	if typeof(state.get("portalOpen")) != TYPE_BOOL:
		state["portalOpen"] = false
	if typeof(state.get("portalX")) != TYPE_FLOAT and typeof(state.get("portalX")) != TYPE_INT:
		state["portalX"] = 0.0
	if typeof(state.get("portalZ")) != TYPE_FLOAT and typeof(state.get("portalZ")) != TYPE_INT:
		state["portalZ"] = 0.0
	place_altar(state)
	if bool(state.get("bossSpawned", false)):
		state["altarUsed"] = true
	PbHazards.ensure(state)
	PbWeatherEvents.ensure(state)
	# Older saves wrote the map-event id into `weather`; move it back onto the
	# event channel so the badge/damage keep reading the weather channel (web
	# never puts event ids there, @1521349 setWeather is moves-only).
	PbWeatherEvents.normalize_legacy(state)
	return state


static func _needs_restore(state: Dictionary) -> bool:
	var w := PbJson.as_string(state.get("weather"), "")
	return int(state.get("stage", 0)) <= 0 or w.is_empty() or w == "<null>" \
		or not (state.get("stats") is Dictionary)


## ------------------------------------------------------------------ tick
static func tick(state: Dictionary, dt: float) -> void:
	# A resumed run (or an imported state) may not carry the newer fields yet.
	if _needs_restore(state):
		ensure_state(state)
	var mode := str(state.get("state", "play"))
	# Evolution cinematic (startEvolution @1543295) pauses gameplay; the 3.6s
	# timer and the completion settlement run in PbEvo.
	if mode == "evolving":
		PbEvo.tick(state, dt)
		return
	if mode != "play":
		return
	var player: Dictionary = state["player"]
	state["time"] = float(state["time"]) + dt
	state["stageT"] = float(state["stageT"]) + dt
	_tick_meowth(state, dt)
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
			state["weather"] = _weather_id(state.get("baseWeather"))
	_tick_director(state, dt)
	# Boss.exhaust() fight clock: only ticks while the current boss is alive.
	if bool(state.get("bossSpawned", false)) \
			and PbEnemies.is_alive(state["enemies"], int(state.get("bossIndex", -1))):
		state["bossFightT"] = float(state.get("bossFightT", 0.0)) + dt
	_tick_player(state, dt)
	PbCapture.tick(state, dt)
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
	# DoT damage that lands on the 1 % floor still opens the capture window.
	var dot_capture: Array = PbJson.as_array(state["enemies"].get("dot_capture", []))
	if not dot_capture.is_empty():
		PbCapture.on_defeated(state)
		state["enemies"]["dot_capture"] = []
	var dot_alpha: Array = PbJson.as_array(state["enemies"].get("dot_alpha", []))
	for entry in dot_alpha:
		var alpha_index := int(entry)
		if not PbCapture.on_defeated(state, alpha_index):
			var alpha_info := PbEnemies.kill(state["enemies"], alpha_index)
			if alpha_info != null:
				_on_kill_info(state, PbJson.as_dict(alpha_info))
	if not dot_alpha.is_empty():
		state["enemies"]["dot_alpha"] = []
	if float(player.get("hp", 0.0)) <= 0.0 or bool(player.get("dead", false)):
		# Web death order (bundle @848700): a Revivir Máximo charge restores 60%
		# HP with 3s of i-frames before the run actually ends.
		if _try_revive(state):
			pass
		else:
			state["state"] = "over"
			state["endHow"] = "defeat"
	elif int(state["stage"]) > stage_count(state):
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

	# The guardian only comes from the altar interaction (@1297900); 600 s is the
	# web's final-swarm milestone, never a wake-up.
	if bool(state["bossSpawned"]) and not PbEnemies.is_alive(pool, int(state["bossIndex"])) and not bool(state["stageCleared"]):
		state["stageCleared"] = true
		var boss_index := int(state["bossIndex"])
		state["splits"].append({"stage": int(state["stage"]), "time": float(state["time"]),
			"kills": int(state["stats"]["kills"]), "level": int(state["player"].get("level", 1))})
		# onBossKilled (@1529103) opens the portal where the guardian died and
		# leaves stage advancement to enterPortal (@1532894).
		spawn_portal(state, float(PbEnemies.get_field(pool, "x", boss_index)),
			float(PbEnemies.get_field(pool, "z", boss_index)))
	# Hostile terrain: `schedule`/`update` run every director tick, matching the
	# web controller (`kw.update`), with no extra play-state gate.
	PbHazards.schedule(state, dt)
	PbHazards.update(state, dt)
	# Map weather events (fog/storm/eclipse/meowth): beats are scheduled on the
	# director clock and the controller ticks every director frame.
	PbWeatherEvents.schedule(state)
	PbWeatherEvents.update(state, dt)


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


## ------------------------------------------------ meowth shop NPC (@1401011)
static func meowth_present(state: Dictionary) -> bool:
	return bool(state.get("meowth", false))


## The web shows the interactable prompt when the player is close; the exact
## radius is not in the recovered fragment -- 4 units (估计).
static func meowth_near(state: Dictionary, radius: float = -1.0) -> bool:
	if not meowth_present(state):
		return false
	var reach := radius if radius > 0.0 else PbShop.npc_num("interact_radius", 4.0)
	var dx := player_x(state) - float(state.get("meowthX", 0.0))
	var dz := player_z(state) - float(state.get("meowthZ", 0.0))
	return dx * dx + dz * dz <= reach * reach


## update: `meowth ? (meowthLeft-=dt)<=0 && play && leaves()
##                  : (meowthT-=dt)<=0 && (meowthT=300, arrives())`.
static func _tick_meowth(state: Dictionary, dt: float) -> void:
	if meowth_present(state):
		state["meowthLeft"] = float(state.get("meowthLeft", 0.0)) - dt
		if float(state["meowthLeft"]) <= 0.0 and str(state.get("state", "play")) == "play":
			meowth_leaves(state)
		return
	state["meowthT"] = float(state.get("meowthT", 0.0)) - dt
	if float(state["meowthT"]) <= 0.0:
		state["meowthT"] = PbShop.npc_num("respawn", 300.0)
		meowth_arrives(state)


## meowthArrives(): shopVisit++, spawn 12-18 units from the player, stay 45 s.
static func meowth_arrives(state: Dictionary) -> void:
	# 超梦事件激活时只把重试计时拨到 30 s，不生成 NPC、不递增 shopVisit。
	# 天气事件层尚未移植 -- 待确认.
	if bool(state.get("mewtwoActive", false)):
		state["meowthT"] = PbShop.npc_num("mewtwo_retry", 30.0)
		return
	state["shopVisit"] = int(state.get("shopVisit", 0)) + 1
	var angle := PbRng.randf_range(0.0, TAU)
	var dist := PbRng.randf_range(PbShop.npc_num("spawn_radius_min", 12.0),
		PbShop.npc_num("spawn_radius_max", 18.0))
	state["meowthX"] = player_x(state) + cos(angle) * dist
	state["meowthZ"] = player_z(state) + sin(angle) * dist
	state["meowth"] = true
	state["meowthLeft"] = PbShop.npc_num("stay", 45.0)
	_message(state, App.ui("¡Meowth ha venido con su tienda! Se irá en 45 s"))


static func meowth_leaves(state: Dictionary) -> void:
	state["meowth"] = false
	state["meowthLeft"] = 0.0
	_message(state, App.ui("Meowth se ha marchado"))


## buildPool() @879880: wild spawns draw from a stage- and biome-filtered pool.
## Stage 1 only permits `evoStage == 0`; stage 2 widens to 0..1; stage 3 keeps
## 1..2 and adds unevolving stage-0 species with `bst >= 420`; stage 4 accepts
## every stage. Legendaries/mythicals never spawn, and the species must share a
## type with the biome.
static func _pick_wild_species(state: Dictionary) -> int:
	var ids := _wild_pool(state)
	if ids.is_empty():
		return 1
	return int(PbRng.pick(ids))


## `this.pool = this.rng.shuffle(o.slice())` (@880322): the shuffle happens once
## per stage, so the cache is keyed on (stage, biome).
static func _wild_pool(state: Dictionary) -> Array:
	var stage := int(state.get("stage", 1))
	var biome_id := str(state.get("biome", "forest"))
	var cache := PbJson.as_dict(state.get("wildPool", {}))
	if int(cache.get("stage", 0)) == stage and str(cache.get("biome", "")) == biome_id:
		return PbJson.as_array(cache.get("ids", []))
	var biome_types := PbJson.as_array(PbData.biome(biome_id).get("types", []))
	var sprites := PbData.sprites_map()
	var max_evo := 0 if stage == 1 else (1 if stage == 2 else 2)
	var min_evo := 1 if stage == 3 else 0
	var base: Array = []
	for raw in PbData.dex_ids(1):
		var species := PbData.species(int(raw))
		if species.is_empty():
			continue
		if bool(species.get("legendary", false)) or bool(species.get("mythical", false)):
			continue
		if PbJson.as_dict(sprites.get(str(int(raw)), {})).is_empty():
			continue
		base.append(species)
	var matched: Array = []
	for raw in base:
		var species: Dictionary = raw
		if not _type_match(PbJson.as_array(species.get("types", [])), biome_types):
			continue
		var evo := int(species.get("evoStage", 0))
		if evo < min_evo or evo > max_evo:
			continue
		matched.append(species)
	# `s=o.filter(hasAnimated); s.length>=24&&(o=s)`: animated sheets win when
	# they still leave a pool of at least 24 species.
	var animated: Array = []
	for raw in matched:
		var id := int(PbJson.as_dict(raw).get("id", 0))
		if not PbJson.as_dict(sprites.get(str(id), {}).get("anims", {})).is_empty():
			animated.append(raw)
	if animated.size() >= 24:
		matched = animated
	if stage == 3:
		for raw in base:
			var species: Dictionary = raw
			var id := int(species.get("id", 0))
			if not _type_match(PbJson.as_array(species.get("types", [])), biome_types):
				continue
			if int(species.get("evoStage", 0)) != 0 or not PbData.evolutions_of(id).is_empty():
				continue
			if float(species.get("bst", 0.0)) < 420.0:
				continue
			if PbJson.as_dict(sprites.get(str(id), {}).get("anims", {})).is_empty():
				continue
			matched.append(species)
	var ids: Array = []
	for raw in matched:
		ids.append(int(PbJson.as_dict(raw).get("id", 0)))
	ids = PbRng.shuffled(ids)
	state["wildPool"] = {"stage": stage, "biome": biome_id, "ids": ids}
	return ids


static func _type_match(species_types: Array, wanted: Array) -> bool:
	for type_name in species_types:
		if wanted.has(type_name):
			return true
	return false


static func spawn_boss(state: Dictionary, origin_x: float = -1.0e9,
		origin_z: float = -1.0e9) -> void:
	var pool: Dictionary = state["enemies"]
	var diff: Dictionary = state["diff"]
	var legendary := _legendary_for_stage(state)
	var stage_t := float(state["stageT"])
	var zone := float(PbCombat.BOSS_ZONE_HP[mini(maxi(int(state["stage"]) - 1, 0),
		PbCombat.BOSS_ZONE_HP.size() - 1)])
	# spawnBoss(e,t) @1527570: `this.terrain.randomPoint(F,e,t,6,10)` -- the
	# guardian appears 6-10 units from the altar, not on the player.
	var spawn_x := player_x(state) + 8.0
	var spawn_z := player_z(state)
	if origin_x > -1.0e8:
		if state.get("terrain") is PbTerrain:
			var point: Vector3 = (state["terrain"] as PbTerrain)._random_point(
				_stage_rng(state, 71), origin_x, origin_z, 6.0, 10.0)
			spawn_x = point.x
			spawn_z = point.z
		else:
			spawn_x = origin_x + 6.0
			spawn_z = origin_z
	var index := PbEnemies.spawn(pool, legendary, spawn_x, spawn_z,
		int(state["stage"]), diff, "boss",
		PbCombat.hp_mult(int(state["stage"]), stage_t, diff,
			float(PbJson.as_dict(state["player"].get("stats", {})).get("difficulty", 1.0))) \
			* PbCombat.BOSS_HP_BONUS * zone,
		PbCombat.dmg_mult(int(state["stage"]), stage_t), 1.0, stage_t)
	if index >= 0:
		state["bossSpawned"] = true
		state["bossIndex"] = index
		state["bossFightT"] = 0.0
		_mark_seen(state, legendary)
		_message(state, "boss! species %d" % legendary)


static func _legendary_for_stage(state: Dictionary) -> int:
	var candidates := []
	for p in PbData.pokemon_list():
		if bool(p.get("legendary", false)) and int(p.get("gen", 1)) == 1:
			candidates.append(int(p["id"]))
	if candidates.is_empty():
		return 150
	return int(candidates[mini(int(state["stage"]) - 1, candidates.size() - 1)])


## ------------------------------------------------ boss altar (@1303414)
## Interactables.populate() adds one `boss` altar on every non-endless stage
## (@1290477) at `randomPoint(play*.55, play*.97)` and renders the shipped
## boss.glb at 6.2. Its prompt is `[E] Despertar al guardián`; the interaction
## marks the altar used, wakes the guardian there and dims the model (@1297900).
static func altar_present(state: Dictionary) -> bool:
	if str(state.get("mode", "standard")) == "endless":
		return false
	return int(state.get("altarStage", 0)) == int(state.get("stage", 1))


static func altar_used(state: Dictionary) -> bool:
	return bool(state.get("altarUsed", false))


static func altar_distance(state: Dictionary) -> float:
	return Vector2(player_x(state) - float(state.get("altarX", 0.0)),
		player_z(state) - float(state.get("altarZ", 0.0))).length()


static func altar_near(state: Dictionary, radius: float = -1.0) -> bool:
	if not altar_present(state):
		return false
	var limit := ALTAR_RADIUS + 0.8 if radius < 0.0 else radius
	return altar_distance(state) <= limit


static func altar_prompt(state: Dictionary) -> String:
	if bool(state.get("bossSpawned", false)) or bool(state.get("altarUsed", false)):
		return "El guardián ya despertó"
	var sanct := PbJson.as_dict(PbData.biome(str(state.get("biome", "forest"))).get("sanctuary", {}))
	if int(state.get("stage", 1)) >= 3 and sanct.is_empty():
		return "Invocar al legendario"
	return "Despertar al guardián"


## Re-pick the stage's altar. `force` is used once the height field exists, so
## the headless placement is replaced by a terrain-aware one before play starts.
static func place_altar(state: Dictionary, force: bool = false) -> void:
	if str(state.get("mode", "standard")) == "endless":
		return
	var stage := int(state.get("stage", 1))
	if not force and int(state.get("altarStage", 0)) == stage:
		return
	var point := _altar_point(state)
	state["altarX"] = point.x
	state["altarZ"] = point.z
	state["altarStage"] = stage
	state["altarUsed"] = false


## randomPoint(a*.55, a*.97) around the world centre (@1290460: `a=t.play-5`).
static func _altar_point(state: Dictionary) -> Vector3:
	var terrain: PbTerrain = state["terrain"] if state.get("terrain") is PbTerrain else null
	var play := 128.0  # DEFAULT_WORLD/2 - 12 when no height field exists yet.
	if terrain != null:
		play = terrain.play
	var inner := maxf(0.0, (play - 5.0) * 0.55)
	var outer := maxf(inner + 1.0, (play - 5.0) * 0.97)
	var rng := _stage_rng(state, 17)
	if terrain != null:
		for _i in 24:
			var point: Vector3 = terrain._random_point(rng, 0.0, 0.0, inner, outer)
			# altars never sit inside a prop cylinder (web `r()` rejects those).
			if not terrain.hit_prop(point.x, point.z, point.y + 1.0, ALTAR_RADIUS + 2.0):
				return point
	var angle := rng.range_f(0.0, TAU)
	var radius := rng.range_f(inner, outer)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## A stage-local generator: the altar/portal rolls must not shift the combat RNG.
static func _stage_rng(state: Dictionary, salt: int) -> PbJsRng:
	return PbJsRng.new(int(state.get("seed", 0)) + int(state.get("stage", 1)) * 7919 + salt)


## The altar interaction (@1297900: `e.used=true, spawnBoss(e.x,e.z)`). The
## mewtwo psychic barrier has no port counterpart, so it adds no gate.
static func wake_guardian(state: Dictionary) -> bool:
	if not altar_present(state) or bool(state.get("bossSpawned", false)):
		return false
	state["altarUsed"] = true
	spawn_boss(state, float(state.get("altarX", 0.0)), float(state.get("altarZ", 0.0)))
	return bool(state.get("bossSpawned", false))


## ------------------------------------------------ portal (onBossKilled @1529103)
static func portal_open(state: Dictionary) -> bool:
	return bool(state.get("portalOpen", false)) and bool(state.get("stageCleared", false))


static func portal_distance(state: Dictionary) -> float:
	return Vector2(player_x(state) - float(state.get("portalX", 0.0)),
		player_z(state) - float(state.get("portalZ", 0.0))).length()


static func portal_near(state: Dictionary, radius: float = -1.0) -> bool:
	if not portal_open(state):
		return false
	var limit := PORTAL_RADIUS + 0.8 if radius < 0.0 else radius
	return portal_distance(state) <= limit


static func portal_prompt(state: Dictionary) -> String:
	if str(state.get("mode", "standard")) == "endless":
		return "Migrar a tierras nuevas"
	var sanct := PbJson.as_dict(PbData.biome(str(state.get("biome", "forest"))).get("sanctuary", {}))
	if not sanct.is_empty() and int(state.get("stage", 1)) >= 4:
		return "Salir del santuario"
	return "Entrar al portal"


## The guardian died: open the portal where it fell (onBossKilled calls
## `spawnPortal(t.x[e], t.z[e])`) and freeze stage progression until it is taken.
static func spawn_portal(state: Dictionary, x: float, z: float) -> void:
	var point := _portal_point(state, x, z)
	state["portalX"] = point.x
	state["portalZ"] = point.z
	state["portalOpen"] = true


## spawnPortal's flat-spot search: keep the death spot when it is walkable, else
## try the rings 6/12/20/35 (@1294753).
static func _portal_point(state: Dictionary, x: float, z: float) -> Vector3:
	if not (state.get("terrain") is PbTerrain):
		return Vector3(x, 0.0, z)
	var terrain: PbTerrain = state["terrain"]
	var rng := _stage_rng(state, 29)
	for radius in [0.0, 6.0, 12.0, 20.0, 35.0]:
		for _i in 40:
			var point := Vector3(x, 0.0, z)
			if radius > 0.0:
				point = terrain._random_point(rng, x, z, radius * 0.3, radius)
			point.y = terrain.height(point.x, point.z)
			if not terrain.is_flat_open(point.x, point.z) or not terrain.in_bounds(point.x, point.z, 6.0):
				continue
			if terrain.hit_prop(point.x, point.z, point.y + 1.0, PORTAL_RADIUS + 2.0):
				continue
			return point
	return Vector3(x, terrain.height(x, z), z)


## enterPortal @1532894: only after the guardian is down and the player stands
## inside the 3.4-unit portal radius; increments the stage and re-places the altar.
static func enter_portal(state: Dictionary) -> bool:
	if not portal_near(state):
		return false
	state["stage"] = int(state.get("stage", 1)) + 1
	state["stageT"] = 0.0
	state["bossSpawned"] = false
	state["bossIndex"] = -1
	state["stageCleared"] = false
	state["portalOpen"] = false
	place_altar(state)
	_message(state, "stage %d" % int(state["stage"]))
	return true


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
		var target := PbEnemies.nearest(pool_of(state), player_x(state), player_z(state), radius,
			PbCapture.index(state) if PbCapture.is_weakened(state) else -1)
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
	# def["weather"] exists on every move and is null for non-weather moves;
	# `str(null)` would be "<null>", so read it through the null-aware helper.
	var cast_weather := _weather_id(def.get("weather"), "")
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
			"weather": _weather_id(state.get("weather")),
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
			"bonusDamage": PbCombat.bonus_damage_mult(player, state, _weather_id(state.get("weather"))),
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
		if bool(hit_res.get("capture", false)):
			# Lethal hit on the league encounter: weaken instead of killing.
			PbCapture.on_defeated(state)
		elif bool(hit_res.get("alpha", false)):
			# Alpha lethal hit: `Cg.intercept` (@544603) turns it into the
			# 8-second down window. If another capture owns the state, it dies.
			if not PbCapture.on_defeated(state, target):
				var alpha_info := PbEnemies.kill(pool, target)
				if alpha_info != null:
					_on_kill_info(state, PbJson.as_dict(alpha_info))
		state["stats"]["damage"] = float(state["stats"]["damage"]) + dealt
		state["stats"]["hits"] = int(state["stats"].get("hits", 0)) + 1
		# §4.9: the golden Meowth drops a coin on every hit (0.16 s cooldown).
		PbWeatherEvents.on_hit(state, target)
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


## Dex "seen": normal enemies write it from the kill path (`tally` @766688),
## while special individuals write it when they enter the arena.
static func _mark_seen(state: Dictionary, species: int) -> void:
	var stats: Dictionary = state["stats"]
	var seen: Array = stats.get("newSeen", [])
	if seen.has(species):
		return
	seen.append(species)
	stats["newSeen"] = seen
	Save.apply_actions([{"t": "seen", "id": species}])


## Consume a kill payload (from a hit or a damage-over-time tick).
static func _on_kill_info(state: Dictionary, info: Dictionary) -> void:
	if info.is_empty():
		return
	var species := int(info["species"])
	# §4.9: the event Meowth pays out 30 coins and closes the event.
	PbWeatherEvents.on_killed_info(state, info)
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
	# tally @766688: a normal kill pushes `seen`. Special individuals (shiny /
	# legendary / league weakened spawn) already wrote it on appearance, and
	# `_mark_seen` de-duplicates, so the dex count stays one per species.
	_mark_seen(state, species)


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
			elif str(orb.get("kind", "")) == "coin":
				state["gold"] = float(state["gold"]) + float(orb.get("value", 0.0))
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
	# Bundle doLevelUp @1541606: an evolution consumes this level-up and no cards
	# are offered for it.
	if PbEvo.try_evolve(state):
		return
	var player: Dictionary = state["player"]
	state["offers"] = PbCards.offer(player, 3, state["banished"], int(state.get("stage", 1)))
	# doLevelUp() @1542070: when KS() finds no candidates (all moves at
	# capOf(), all vitamins capped) the level-up pays out heal + gold instead
	# of showing cards. The web's random `train()` mini-stat is not ported --
	## 待确认 (zk table absent from the extracted data).
	if PbJson.as_array(state["offers"]).is_empty():
		_empty_level_up(state)
		return
	state["state"] = "modal"


static func _empty_level_up(state: Dictionary) -> void:
	var player: Dictionary = state["player"]
	PbActor.heal(player, float(player.get("maxHp", 0.0)) * 0.2)
	state["gold"] = float(state["gold"]) + 15.0
	# doLevelUp @1542119 `r()`: heal(.2*maxHp), addGold(15), then train().
	# train() @1542115 picks from `zk` (7 mini-stats, critChance skipped once
	# megaCrit >= 1) and shows `ui.trained(...)`; the first one also banners.
	var info := PbActor.train(player)
	if not info.is_empty():
		_message(state, "training: +%s %s" % [
			_fmt_train(float(info.get("amount", 0.0)), str(info.get("mode", "add"))),
			str(info.get("stat", ""))])
		if bool(info.get("first", false)):
			_message(state, "training unlocked: every empty level now grants a small permanent bonus")
	state["pendingLevels"] = maxi(0, int(state["pendingLevels"]) - 1)
	state["offers"] = []
	state["state"] = "play"
	if int(state["pendingLevels"]) > 0:
		open_offers(state)


static func _fmt_train(amount: float, mode: String) -> String:
	if mode == "mul":
		return "%s%%" % str(snappedf(amount * 100.0, 0.1))
	return str(snappedf(amount, 0.001))


static func choose_offer(state: Dictionary, index: int) -> bool:
	var offers: Array = PbJson.as_array(state.get("offers", []))
	if index < 0 or index >= offers.size():
		return false
	var card := PbJson.as_dict(offers[index])
	var player: Dictionary = state["player"]
	var result := PbCards.take(player, card)
	# JS() @1098000 also counts newly learned moves for the run stats.
	if str(card.get("kind", "")) == "new_move" and result == "learned":
		state["stats"]["movesLearned"] = int(state["stats"].get("movesLearned", 0)) + 1
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
	# doLevelUp @1542111: `addGold(Math.max(10*stage, .2*eT(this)))` and a single
	# `addGold` rounds (run.addGold @1516416). eT = PbShop.chest_price().
	var payout := int(roundf(maxf(10.0 * float(int(state.get("stage", 1))),
		0.2 * PbShop.chest_price(state))))
	state["gold"] = float(state["gold"]) + float(payout)
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
	# Reuse the exact keys the roll_* pools consult (`m:`+move, `v`+vit);
	# the old `kind:field` tag never matched and banish had no effect.
	state["banished"][PbCards._card_key(card, index)] = true
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
		# Capture encounters are passive: the bundle spawns them with R.Capture and
		# enemy attacks/AI ignore that flag (bundle @551237, @552310).
		if (int(PbEnemies.get_field(pool, "flags", i)) & int(PbEnemies.Flag["Capture"])) != 0:
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
			# Enemy hazards: `S *= hazSlow[h]; hazSlow[h] = 1` in the web move step.
			speed *= float(PbEnemies.get_field(pool, "hazSlow", i))
			PbEnemies.set_field(pool, "hazSlow", i, 1.0)
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
		"econ": PbJson.as_dict(state.get("econ", {})).merged({"gold": int(state.get("gold", 0))}, true),
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
		if str(state.get("state", "play")) != "evolving":
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
	var speed := float(PbJson.as_dict(player.get("stats", {})).get("moveSpeed", 1.0)) * 6.0 \
		* float(player.get("hazardSlow", 1.0))
	var step := minf(speed * dt, md)
	player["x"] = px + mx / md * step
	player["z"] = pz + mz / md * step
	player["facing"] = 2 if mx > 0.0 else 6
