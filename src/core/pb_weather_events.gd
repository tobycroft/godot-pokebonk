class_name PbWeatherEvents
extends RefCounted
## Limited-time map weather events (fog/storm/eclipse/meowth), recovered from
## the bundle's `uS` table (@1061261) and `fS` controller (@1062329).
##
## State lives under `state["weatherEvent"]`; the set of events already seen in
## this run is `state["weatherDone"]`. Like the web, an event never writes
## `weather`/`weatherT`/`baseWeather`: it only installs its `look` override
## (§4.5/@1062379, where the controller drives `look`/`atmos` instead of
## `setWeather`). The badge and the damage layer therefore keep reading the
## weather channel while an event runs.

const MEOWTH_SPECIES := 52
const SPAWN_INTERVAL := 4.0
const SPAWN_CAP := 30


static func table() -> Dictionary:
	return PbJson.as_dict(PbData.pb_table("weather"))


static func ensure(state: Dictionary) -> Dictionary:
	if not state.has("weatherEvent"):
		state["weatherEvent"] = {
			"kind": "", "left": 0.0, "k": 0.0,
			"spawnT": 0.0, "boltT": 0.0, "spawned": 0,
			"shinyRolled": false,
			"meowth": -1, "meowthGen": 0, "meowthX": 0.0, "meowthZ": 0.0,
			"coinCd": 0.0, "wetT": 0.0, "flash": 0.0,
			"boltQueue": [], "lookKind": "",
			"stage": 0, "beats": [], "next": 0.0,
		}
	if not state.has("weatherDone"):
		state["weatherDone"] = []
	return PbJson.as_dict(state["weatherEvent"])


static func active(state: Dictionary) -> bool:
	return str(ensure(state).get("kind", "")) != ""


static func kind(state: Dictionary) -> String:
	return str(ensure(state).get("kind", ""))


## §4.11: fog blinds once the event is more than half faded in.
static func blind(state: Dictionary) -> bool:
	var c := ensure(state)
	return str(c.get("kind", "")) == "fog" and float(c.get("k", 0.0)) > 0.5


## §4.8: read by other systems; the event itself does not add the bonus.
static func elite_bonus(state: Dictionary) -> float:
	return 0.12 if kind(state) == "eclipse" else 0.0


static func flash(state: Dictionary) -> float:
	return float(ensure(state).get("flash", 0.0))


## Live telegraph markers for the renderer: [{"x","z","t"}] (t = seconds to bolt).
static func markers(state: Dictionary) -> Array:
	return PbJson.as_array(ensure(state).get("boltQueue", []))


static func look_weight(state: Dictionary) -> float:
	return clampf(float(ensure(state).get("k", 0.0)), 0.0, 1.0)


## `look` override for the world view; kept through the fade-out (`lookKind`).
static func look_overrides(state: Dictionary) -> Dictionary:
	var c := ensure(state)
	var look_kind := str(c.get("kind", ""))
	if look_kind == "":
		look_kind = str(c.get("lookKind", ""))
	if look_kind == "" or look_kind == "meowth":
		return {}
	return PbJson.as_dict(PbJson.as_dict(table().get(look_kind)).get("look", {}))


## §4.3: pool[min(2, stage-1)], filtered to species with a sprite sheet.
static func pool(state: Dictionary) -> Array:
	var entry := PbJson.as_dict(table().get(kind(state)))
	if entry.is_empty():
		return []
	var stages := PbJson.as_array(entry.get("pool", []))
	if stages.is_empty():
		return []
	var ids := PbJson.as_array(stages[mini(2, maxi(0, int(state.get("stage", 1)) - 1))])
	var sprites := PbData.sprites_map()
	var out := []
	for raw in ids:
		var id := int(raw)
		if sprites.has(str(id)):
			out.append(id)
	return out


## §4.4 weights: meowth 0.8, everything else 1.
static func weights(state: Dictionary) -> Array:
	var done := PbJson.as_array(state.get("weatherDone", []))
	var out := []
	for event_kind in ["fog", "storm", "eclipse", "meowth"]:
		if done.has(event_kind):
			continue
		out.append([0.8 if event_kind == "meowth" else 1.0, event_kind])
	return out


## §4.4: gates + one-per-run set. Endless clears the set once all four ran.
static func start_random(state: Dictionary) -> bool:
	var c := ensure(state)
	if str(c.get("kind", "")) != "":
		return false
	if bool(state.get("bossSpawned", false)) \
			and PbEnemies.is_alive(state["enemies"], int(state.get("bossIndex", -1))):
		return false
	if bool(state.get("stageCleared", false)):
		return false
	if bool(PbJson.as_dict(state.get("mapEvents", {})).get("busy", false)):
		return false
	var entries := weights(state)
	if entries.is_empty():
		if str(state.get("mode", "")) != "endless":
			return false
		state["weatherDone"] = []
		entries = weights(state)
	if entries.is_empty():
		return false
	return start(state, str(PbRng.weighted(entries)))


## §4.5: enter an event, superseding any running one silently.
static func start(state: Dictionary, event_kind: String) -> bool:
	var entry := PbJson.as_dict(table().get(event_kind))
	if entry.is_empty():
		return false
	var c := ensure(state)
	if str(c.get("kind", "")) != "":
		end(state, true)
	c["kind"] = event_kind
	c["left"] = float(entry.get("dur", 0.0))
	c["spawned"] = 0
	c["spawnT"] = 2.0
	c["boltT"] = 3.0
	c["shinyRolled"] = false
	c["coinCd"] = 0.0
	c["wetT"] = 0.5
	c["flash"] = 0.0
	c["boltQueue"] = []
	c["lookKind"] = "" if event_kind == "meowth" else event_kind
	var done := PbJson.as_array(state.get("weatherDone", []))
	if not done.has(event_kind):
		done.append(event_kind)
	state["weatherDone"] = done
	if event_kind == "meowth" and not spawn_meowth(state):
		c["kind"] = ""
		c["left"] = 0.0
		return false
	# §4.5 banner: `banner|title|body|colour|big`.
	var title := App.ui("¡{name}!", {"name": App.ui(str(entry.get("name", event_kind)))})
	_message(state, "banner|%s|%s|%s|big" % [title, App.ui(str(entry.get("sub", ""))),
		str(entry.get("color", "#f7c948"))])
	# The web's event controller never calls `setWeather`; the event id lives on
	# the `look` channel only, so `weather`/`weatherT` stay as they were.
	return true


## §4.5: leave the event; `silent` suppresses the natural-expiry toast.
static func end(state: Dictionary, silent: bool = false) -> void:
	var c := ensure(state)
	var was := str(c.get("kind", ""))
	if was == "":
		return
	if not silent:
		var msg := ""
		match was:
			"fog": msg = "La niebla se disipa"
			"storm": msg = "La tormenta se aleja"
			"eclipse": msg = "La luz vuelve"
		if msg != "":
			_message(state, App.ui(msg))
	c["kind"] = ""
	c["left"] = 0.0
	c["boltQueue"] = []
	c["meowth"] = -1
	# The weather channel is not ours to clear: an event never installed an
	# override there (weather moves keep their own `weatherT`).
	# The look keeps fading out through `lookKind` until k reaches 0.


## Migration for saves written before the channels were split: those saves put
## the event id into `weather` (and the event duration into `weatherT`). Move a
## tracked id back onto the event channel and restore the base weather. `fog`
## is also a graveyard base weather, so an untracked `fog` only counts as a
## leftover event when the base weather is something else.
static func normalize_legacy(state: Dictionary) -> void:
	var c := ensure(state)
	var raw := PbJson.as_string(state.get("weather"), "")
	if raw.is_empty() or raw == "<null>":
		return
	var base := PbJson.as_string(state.get("baseWeather"), "")
	if base.is_empty() or base == "<null>":
		base = "clear"
		state["baseWeather"] = base
	var tracked := str(c.get("kind", ""))
	if tracked != "":
		# The event is still tracked: only its id can be stale in `weather`.
		if raw != tracked:
			return
	else:
		# storm/eclipse/meowth are never weather ids; fog is a base weather too.
		if raw == "fog":
			if base == "fog":
				return
		elif raw != "storm" and raw != "eclipse" and raw != "meowth":
			return
		tracked = raw
		var left := float(state.get("weatherT", 0.0))
		if left > 0.0:
			# Revive the event for its remaining time so the normal fade/timer
			# path closes it (and a mid-event save keeps its look).
			c["kind"] = tracked
			c["left"] = left
			c["lookKind"] = "" if tracked == "meowth" else tracked
			c["k"] = 0.0 if tracked == "meowth" else 1.0
			c["spawnT"] = 2.0
			c["boltT"] = 3.0
			var done := PbJson.as_array(state.get("weatherDone", []))
			if not done.has(tracked):
				done.append(tracked)
			state["weatherDone"] = done
	state["weather"] = base
	state["weatherT"] = 0.0


## §4.5: timers + per-kind effects.
static func update(state: Dictionary, dt: float) -> void:
	var c := ensure(state)
	var event_kind := str(c.get("kind", ""))
	c["flash"] = maxf(0.0, float(c.get("flash", 0.0)) - dt * 5.0)
	if event_kind != "":
		c["left"] = float(c.get("left", 0.0)) - dt
		if event_kind == "meowth":
			update_meowth(state, dt)
			c["k"] = maxf(0.0, float(c.get("k", 0.0)) - dt / 3.0)
		else:
			c["k"] = minf(1.0, float(c.get("k", 0.0)) + dt / 3.0)
			update_spawns(state, dt)
			if event_kind == "storm":
				storm_fx(state, dt)
			elif event_kind == "eclipse":
				eclipse_fx(state)
		if float(c.get("left", 0.0)) <= 0.0 and str(c.get("kind", "")) != "":
			end(state)
	else:
		c["k"] = maxf(0.0, float(c.get("k", 0.0)) - dt / 3.0)
		if float(c.get("k", 0.0)) <= 0.0:
			c["lookKind"] = ""


## §4.6: every 4 s spawn 3+stage pool species around the player.
static func update_spawns(state: Dictionary, dt: float) -> int:
	var c := ensure(state)
	var event_kind := str(c.get("kind", ""))
	var ids := pool(state)
	if ids.is_empty() or int(c.get("spawned", 0)) >= SPAWN_CAP or float(c.get("left", 0.0)) < 6.0:
		return 0
	c["spawnT"] = float(c.get("spawnT", 0.0)) - dt
	if float(c["spawnT"]) > 0.0:
		return 0
	c["spawnT"] = SPAWN_INTERVAL
	var stage := int(state.get("stage", 1))
	var stage_t := float(state.get("stageT", 0.0))
	var stats := PbJson.as_dict(PbJson.as_dict(state.get("player", {})).get("stats", {}))
	var diff := PbJson.as_dict(state.get("diff", {}))
	var difficulty := float(stats.get("difficulty", 1.0)) * float(stats.get("enemyAmount", 1.0))
	var hp_mult := PbCombat.hp_mult(stage, stage_t, diff, difficulty)
	var dmg_mult := PbCombat.dmg_mult(stage, stage_t)
	var player := PbJson.as_dict(state.get("player", {}))
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var enemies: Dictionary = state["enemies"]
	var terrain = state.get("terrain")
	var count := 3 + stage
	var made := 0
	for n in count:
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(20.0, 27.0)
		var x := px + cos(angle) * dist
		var z := pz + sin(angle) * dist
		if terrain != null and not terrain.in_bounds(x, z, 5.0):
			continue
		var tier := "wild"
		if event_kind == "eclipse" and n == 0 and stage_t > 90.0:
			tier = "elite"
		var index := PbEnemies.spawn(enemies, int(PbRng.pick(ids)), x, z, stage, diff,
			tier, hp_mult, dmg_mult, 1.0, stage_t)
		if index < 0:
			continue
		c["spawned"] = int(c.get("spawned", 0)) + 1
		made += 1
		if event_kind == "fog":
			PbEnemies.set_field(enemies, "flags", index,
				PbEnemies.flags(enemies, index) | int(PbEnemies.Flag["Flying"]))
			PbEnemies.set_field(enemies, "xp", index,
				float(PbEnemies.get_field(enemies, "xp", index)) * 2.0)
	return made


## §4.7: wet + telegraph queue + bolt scheduling.
static func storm_fx(state: Dictionary, dt: float) -> void:
	var c := ensure(state)
	var enemies: Dictionary = state["enemies"]
	var player := PbJson.as_dict(state.get("player", {}))
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	# Non-desert storms wet enemies within 25 units every 0.5 s.
	if str(state.get("biome", "forest")) != "desert":
		c["wetT"] = float(c.get("wetT", 0.0)) - dt
		if float(c["wetT"]) <= 0.0:
			c["wetT"] = 0.5
			for entry in PbEnemies.within(enemies, px, pz, 25.0):
				var i := int(entry)
				PbEnemies.set_field(enemies, "wet", i,
					maxf(float(PbEnemies.get_field(enemies, "wet", i)), 2.0))
	# Resolve queued telegraphs (delay .6 s enemy / 1.1 s player).
	var queue := PbJson.as_array(c.get("boltQueue", []))
	var keep := []
	for raw in queue:
		var bolt_info := PbJson.as_dict(raw)
		bolt_info["t"] = float(bolt_info.get("t", 0.0)) - dt
		if float(bolt_info["t"]) <= 0.0:
			bolt(state, float(bolt_info.get("x", 0.0)), float(bolt_info.get("z", 0.0)),
				float(bolt_info.get("r", 3.0)))
		else:
			keep.append(bolt_info)
	c["boltQueue"] = keep
	c["boltT"] = float(c.get("boltT", 0.0)) - dt
	if float(c["boltT"]) > 0.0 or float(c.get("k", 0.0)) < 0.6:
		return
	c["boltT"] = PbRng.randf_range(0.9, 1.6)
	var tx := 0.0
	var tz := 0.0
	var delay := 0.6
	if PbRng.chance(0.35):
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(0.0, 3.0)
		tx = px + cos(angle) * dist
		tz = pz + sin(angle) * dist
		delay = 1.1
	else:
		var near := PbEnemies.within(enemies, px, pz, 26.0)
		if not near.is_empty():
			var i := int(PbRng.pick(near))
			tx = float(PbEnemies.get_field(enemies, "x", i))
			tz = float(PbEnemies.get_field(enemies, "z", i))
		else:
			tx = px + PbRng.randf_range(-18.0, 18.0)
			tz = pz + PbRng.randf_range(-18.0, 18.0)
	keep = PbJson.as_array(c.get("boltQueue", []))
	keep.append({"x": tx, "z": tz, "r": 3.0, "t": delay})
	c["boltQueue"] = keep


## §4.7: strike. Player within 3 + grounded, enemies within 4.5.
static func bolt(state: Dictionary, x: float, z: float, radius: float = 3.0) -> void:
	var c := ensure(state)
	c["flash"] = 1.0
	var player := PbJson.as_dict(state.get("player", {}))
	var stats := PbJson.as_dict(player.get("stats", {}))
	var stage := int(state.get("stage", 1))
	var stage_t := float(state.get("stageT", 0.0))
	var diff := PbJson.as_dict(state.get("diff", {}))
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var ground := _ground_y(state, x, z)
	if Vector2(px - x, pz - z).length() < radius \
			and float(player.get("y", 0.0)) - ground < 2.5:
		var raw := 16.0 * PbCombat.dmg_mult(stage, stage_t) \
			* float(diff.get("enemyDamage", 1.0))
		var taken := PbDamage.incoming_to_player(raw, "electric",
			PbJson.as_array(player.get("types", [])), stats, false,
			str(player.get("ability", "")), int(player.get("level", 1)))
		taken = PbDamage.apply_incoming_floor_cap(taken, raw,
			float(player.get("maxHp", 1.0)), 0.0, 0.0)
		var applied := PbActor.damage(player, taken)
		state["stats"]["damageTaken"] = float(state["stats"]["damageTaken"]) + applied
	var enemies: Dictionary = state["enemies"]
	for entry in PbEnemies.within(enemies, x, z, radius + 1.5):
		var i := int(entry)
		var flags := PbEnemies.flags(enemies, i)
		var elite := flags & (int(PbEnemies.Flag["Boss"]) | int(PbEnemies.Flag["Alpha"])
			| int(PbEnemies.Flag["Totem"]) | int(PbEnemies.Flag["Summoner"]))
		var amount := float(PbEnemies.get_field(enemies, "maxHp", i)) * (0.04 if elite != 0 else 0.3)
		var hit := PbEnemies.damage(enemies, i, amount)
		var dealt := float(hit.get("dealt", 0.0))
		state["stats"]["damage"] = float(state["stats"]["damage"]) + dealt
		if bool(hit.get("capture", false)):
			PbCapture.on_defeated(state)
		elif bool(hit.get("alpha", false)):
			if not PbCapture.on_defeated(state, i):
				var alpha_info := PbEnemies.kill(enemies, i)
				if alpha_info != null:
					PbRun._on_kill_info(state, PbJson.as_dict(alpha_info))
		elif bool(hit.get("died", false)):
			PbRun._on_kill_info(state, PbJson.as_dict(hit.get("info", {})))
		if PbEnemies.is_alive(enemies, i):
			PbEnemies.apply_status(enemies, i, "paralysis", 1.0)


## §4.8: one shiny roll 12 s into the event (not in endless).
static func eclipse_fx(state: Dictionary) -> void:
	var c := ensure(state)
	var dur := float(PbJson.as_dict(table().get("eclipse")).get("dur", 40.0))
	if bool(c.get("shinyRolled", false)) or float(c.get("left", 0.0)) >= dur - 12.0:
		return
	var capture := PbJson.as_dict(state.get("capture", {}))
	var capture_state := str(capture.get("state", ""))
	if capture_state == "roaming" or capture_state == "weakened" or capture_state == "throwing":
		return
	c["shinyRolled"] = true
	if str(state.get("mode", "")) == "endless":
		return
	var ids := pool(state)
	if ids.is_empty():
		return
	var stats := PbJson.as_dict(PbJson.as_dict(state.get("player", {})).get("stats", {}))
	var luck := float(stats.get("luck", 0.0))
	# meta.shinyRate() is not recovered from the bundle; the doc's factor is
	# applied as identity when the run does not carry a rate (待确认).
	var shiny_rate := float(PbJson.as_dict(state.get("meta", {})).get("shinyRate", 1.0))
	var chance := minf(0.9, (0.2 + minf(0.08, luck / 1000.0)) * shiny_rate)
	if PbRng.chance(chance):
		spawn_shiny(state, ids)


## §4.5/§4.8: `capture.spawnShiny` is not recovered; spawn the pick like an
## event spawn at 20-27 units and tag it with the port's Shiny bit.
static func spawn_shiny(state: Dictionary, ids: Array) -> int:
	var player := PbJson.as_dict(state.get("player", {}))
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var stage := int(state.get("stage", 1))
	var stage_t := float(state.get("stageT", 0.0))
	var stats := PbJson.as_dict(player.get("stats", {}))
	var diff := PbJson.as_dict(state.get("diff", {}))
	var difficulty := float(stats.get("difficulty", 1.0)) * float(stats.get("enemyAmount", 1.0))
	var angle := PbRng.randf_range(0.0, TAU)
	var dist := PbRng.randf_range(20.0, 27.0)
	var enemies: Dictionary = state["enemies"]
	var index := PbEnemies.spawn(enemies, int(PbRng.pick(ids)), px + cos(angle) * dist,
		pz + sin(angle) * dist, stage, diff, "wild",
		PbCombat.hp_mult(stage, stage_t, diff, difficulty),
		PbCombat.dmg_mult(stage, stage_t), 1.0, stage_t)
	if index < 0:
		return -1
	PbEnemies.set_field(enemies, "flags", index,
		PbEnemies.flags(enemies, index) | int(PbEnemies.Flag["Shiny"]))
	return index


## §4.9: try 12 times to place the golden Meowth; `hp = hpMult, dmg = 1`.
static func spawn_meowth(state: Dictionary) -> bool:
	var c := ensure(state)
	var player := PbJson.as_dict(state.get("player", {}))
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var stage := int(state.get("stage", 1))
	var stage_t := float(state.get("stageT", 0.0))
	var stats := PbJson.as_dict(player.get("stats", {}))
	var diff := PbJson.as_dict(state.get("diff", {}))
	var difficulty := float(stats.get("difficulty", 1.0)) * float(stats.get("enemyAmount", 1.0))
	var hp_mult := PbCombat.hp_mult(stage, stage_t, diff, difficulty)
	var enemies: Dictionary = state["enemies"]
	var terrain = state.get("terrain")
	for n in 12:
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(14.0, 20.0)
		var x := px + cos(angle) * dist
		var z := pz + sin(angle) * dist
		if terrain != null and not terrain.in_bounds(x, z, 10.0):
			continue
		var index := PbEnemies.spawn(enemies, MEOWTH_SPECIES, x, z, stage, diff,
			"wild", hp_mult, 1.0, 1.0, stage_t)
		if index < 0:
			return false
		PbEnemies.set_field(enemies, "flags", index,
			PbEnemies.flags(enemies, index) | int(PbEnemies.Flag["Treasure"]))
		PbEnemies.set_field(enemies, "dmg", index, 1.0)
		PbEnemies.set_field(enemies, "speed", index, 7.4)
		c["meowth"] = index
		c["meowthGen"] = int(PbEnemies.get_field(enemies, "gen", index))
		c["meowthX"] = x
		c["meowthZ"] = z
		return true
	return false


## §4.9 marker: index + generation + alive.
static func marker(state: Dictionary) -> Dictionary:
	var c := ensure(state)
	var index := int(c.get("meowth", -1))
	var enemies: Dictionary = state["enemies"]
	if index < 0 or not PbEnemies.is_alive(enemies, index):
		return {}
	if int(PbEnemies.get_field(enemies, "gen", index)) != int(c.get("meowthGen", 0)):
		return {}
	return {"i": index, "x": float(PbEnemies.get_field(enemies, "x", index)),
		"z": float(PbEnemies.get_field(enemies, "z", index))}


static func is_event_meowth(state: Dictionary, index: int) -> bool:
	var m := marker(state)
	return not m.is_empty() and int(m.get("i", -1)) == index


## §4.9: escape on timeout, or close the event if the marker vanished.
static func update_meowth(state: Dictionary, dt: float) -> void:
	var c := ensure(state)
	c["coinCd"] = float(c.get("coinCd", 0.0)) - dt
	var m := marker(state)
	if m.is_empty():
		c["meowth"] = -1
		end(state, true)
		return
	if float(c.get("left", 0.0)) <= 0.0:
		PbEnemies.kill(state["enemies"], int(m.get("i", -1)))
		c["meowth"] = -1
		_message(state, App.ui("Meowth dorado se escapa con su botín"))


## §4.9: each hit (max one per .16 s) drops a coin.
static func on_hit(state: Dictionary, index: int) -> void:
	var c := ensure(state)
	if index != int(c.get("meowth", -1)) or float(c.get("coinCd", 0.0)) > 0.0:
		return
	c["coinCd"] = 0.16
	var gold := _gold_mult(state)
	var amount := float(ceili((2.0 + float(state.get("stage", 1)) * 2.0) * gold))
	_spawn_coins(state, index, amount, 1)


## §4.9: kill reward -- 30 coins + banner, then end silently.
static func on_killed_info(state: Dictionary, info: Dictionary) -> void:
	var c := ensure(state)
	var index := int(c.get("meowth", -1))
	if index < 0 or int(info.get("species", 0)) != MEOWTH_SPECIES:
		return
	# Guard against unrelated Meowth kills: the slot must still carry the
	# generation captured when the event spawned it.
	var enemies: Dictionary = state["enemies"]
	if int(PbEnemies.get_field(enemies, "gen", index)) != int(c.get("meowthGen", 0)):
		return
	var x := float(info.get("x", 0.0))
	var z := float(info.get("z", 0.0))
	var gold := _gold_mult(state)
	var amount := float(ceili((4.0 + float(state.get("stage", 1)) * 4.0) * gold))
	_message(state, "banner|%s|%s|#ffc83a|big" % [App.ui("¡Día de Pago!"),
		App.ui("Meowth dorado suelta todas sus monedas")])
	for n in 30:
		_spawn_coin(state, x, z, amount)
	c["meowth"] = -1
	end(state, true)


## §4.10: beat clock on `stageTime` (the run resets it on every zone change,
## @1506202 run init / @1506897 enterPortal). The doc's beats are stageTime
## values, so they now run on `stageT` again instead of the run clock.
static func schedule(state: Dictionary) -> void:
	var c := ensure(state)
	var run_t := float(state.get("time", 0.0))
	if str(state.get("mode", "")) == "endless":
		if float(c.get("next", 0.0)) <= 0.0:
			c["next"] = run_t + _beat(170.0, 230.0)
		if run_t >= float(c.get("next", 0.0)):
			if start_random(state):
				c["next"] = run_t + _beat(220.0, 260.0)
			else:
				c["next"] = run_t + _beat(15.0, 15.0)
		return
	var stage := int(state.get("stage", 1))
	var stage_t := float(state.get("stageT", 0.0))
	if int(c.get("stage", 0)) != stage:
		c["stage"] = stage
		var beats := []
		if stage == 1:
			beats.append({"t": stage_t + _beat(170.0, 300.0), "fired": false})
		else:
			beats.append({"t": stage_t + _beat(130.0, 230.0), "fired": false})
			beats.append({"t": stage_t + _beat(340.0, 460.0), "fired": false})
		c["beats"] = beats
	var beats := PbJson.as_array(c.get("beats", []))
	for raw in beats:
		var beat := PbJson.as_dict(raw)
		if bool(beat.get("fired", false)) or stage_t < float(beat.get("t", 0.0)):
			continue
		if start_random(state):
			beat["fired"] = true
		else:
			beat["t"] = stage_t + _beat(15.0, 15.0)


## Doc beat seconds (stageTime); kept verbatim (see `schedule`).
static func _beat(from: float, to: float) -> float:
	return PbRng.randf_range(from, to)


static func _gold_mult(state: Dictionary) -> float:
	return float(PbJson.as_dict(PbJson.as_dict(state.get("player", {})).get("stats", {})).get("gold", 1.0))


static func _spawn_coins(state: Dictionary, index: int, amount: float, count: int) -> void:
	var enemies: Dictionary = state["enemies"]
	var x := float(PbEnemies.get_field(enemies, "x", index))
	var z := float(PbEnemies.get_field(enemies, "z", index))
	for n in count:
		_spawn_coin(state, x, z, amount)


static func _spawn_coin(state: Dictionary, x: float, z: float, amount: float) -> void:
	PbJson.as_array(state.get("orbs", [])).append({
		"x": x,
		"z": z,
		"kind": "coin",
		"value": amount,
		"life": 12.0,
	})


static func _ground_y(state: Dictionary, x: float, z: float) -> float:
	var terrain = state.get("terrain")
	if terrain is PbTerrain:
		return terrain.surface(x, z)
	return 0.0


static func _message(state: Dictionary, text: String) -> void:
	var messages := PbJson.as_array(state.get("messages", []))
	messages.append(text)
	if messages.size() > 40:
		messages.pop_front()
	state["messages"] = messages
