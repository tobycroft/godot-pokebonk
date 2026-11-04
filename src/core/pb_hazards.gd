class_name PbHazards
extends RefCounted
## Hostile terrain ("危险地形"): spawn scatter, per-frame effects and lifecycle.
##
## Port of the web controller `kw` (bundle main-CPuTGAQ @1311320, table `bw`
## @1311009, biome map `xw` @1311220). The runtime table is read from
## data/pb/world_fx.json -> hazards, which carries the same numbers as the
## bundle plus the four-locale `name`/`say` blocks; data/pb/hazards.json is the
## flat ingest copy and is not read here (see `PbData.hazards_table()`).
##
## Field semantics (verified against `update()` @1311600):
##   slow  -- movement multiplier for the player (min across overlapping hazards);
##            enemies get `slow * .9`. 1 = no slowdown.
##   pull  -- position displacement per second toward the centre (not an
##            acceleration): player `pull*dt*(1-f/r*.5)`, enemies `pull*1.3*dt`.
##   hurt  -- player-only damage every tick, as a fraction of maxHp.
##   bite  -- enemy-only damage every tick, as a fraction of maxHp; Boss/Alpha/
##            Totem/Summoner take `.1` of it.
##   type  -- damage type of `hurt`/`bite`; status is the enemy status applied
##            on a bite tick at 50% chance (players never get hazard statuses).

const INTRO := 2.0          # flicker phase before a hazard becomes active
const FADE := 1.5           # linear fade-out after `life + INTRO`
const FIRST_TICK := 0.2     # initial damage timer
const TICK := 0.5           # `Sw` in the bundle; timer reset after each tick
const MIN_RADIUS := 4.5     # smallest accepted flat spot
const ATLAS_PATH := "res://assets/env/common/hazards.png"

const DAMAGE_FACTOR_FLAGS := PbEnemies.Flag["Boss"] | PbEnemies.Flag["Alpha"] \
	| PbEnemies.Flag["Totem"] | PbEnemies.Flag["Summoner"]


# ------------------------------------------------------------------ data
## data/pb/world_fx.json -> hazards is the single runtime source (multilingual).
static func table() -> Dictionary:
	return PbJson.as_dict(PbData.hazards_table())


static func defs() -> Dictionary:
	return PbJson.as_dict(table().get("defs"))


static func def_of(kind: String) -> Dictionary:
	return PbJson.as_dict(defs().get(kind, {}))


static func by_biome() -> Dictionary:
	return PbJson.as_dict(table().get("byBiome"))


## `xw[biome] ?? Object.keys(bw)`: unknown biomes get every kind.
static func kinds_for(biome: String) -> Array:
	var map := by_biome()
	if map.has(biome):
		return PbJson.as_array(map[biome])
	return defs().keys()


## Web gates spawning on the atlas load (`Dw`); the port ships the atlas.
static func atlas_ready() -> bool:
	return ResourceLoader.exists(ATLAS_PATH)


static func localized(kind: String, field: String) -> String:
	var def := def_of(kind)
	var block := PbJson.as_dict(def.get(field))
	var es := str(block.get("es", ""))
	# The Spanish source text is the web i18n key; App.ui() resolves it for the
	# current locale and falls back to the key itself.
	return App.ui(es) if not es.is_empty() else ""


# ------------------------------------------------------------------ state
static func ensure(state: Dictionary) -> Dictionary:
	if not state.has("hazards"):
		state["hazards"] = {"list": [], "nextT": 180.0, "nextId": 0}
	return PbJson.as_dict(state["hazards"])


static func list(state: Dictionary) -> Array:
	return PbJson.as_array(ensure(state).get("list", []))


static func clear(state: Dictionary) -> void:
	var controller := ensure(state)
	controller["list"] = []
	controller["nextT"] = 180.0
	PbJson.as_dict(state.get("player", {}))["hazardSlow"] = 1.0
	var pool := PbJson.as_dict(state.get("enemies", {}))
	for entry in PbJson.as_array(pool.get("live", [])):
		PbEnemies.set_field(pool, "hazSlow", int(entry), 1.0)


# ------------------------------------------------------------------ scheduling
## Called once per director tick. `state["terrain"]` is set by the run screen;
## the headless simulation without a terrain simply never spawns one.
static func schedule(state: Dictionary, dt: float) -> void:
	var controller := ensure(state)
	controller["nextT"] = float(controller.get("nextT", 0.0)) - dt
	if float(controller["nextT"]) > 0.0 or not atlas_ready():
		return
	controller["nextT"] = PbRng.randf_range(45.0, 70.0)
	var limit := 3 if int(state.get("stage", 1)) >= 3 else 2
	if list(state).size() >= limit:
		return
	if bool(PbJson.as_dict(state.get("mewtwo", {})).get("active", false)):
		return
	var terrain = state.get("terrain")
	if terrain == null:
		return
	var spot = flat_spot(terrain, PbRun.player_x(state), PbRun.player_z(state),
		PbRng.randf_range(6.0, 9.0))
	if spot == null:
		return
	var kinds := kinds_for(str(state.get("biome", "forest")))
	if kinds.is_empty():
		return
	spawn(state, str(PbRng.pick(kinds)), float(spot["x"]), float(spot["z"]),
		float(spot["r"]), PbRng.randf_range(40.0, 55.0))


## 24 samples around the player (8..28 units), shrinking the radius from the
## target down to MIN_RADIUS; a radius is flat when 12 angles × (0.5, 1.0)
## samples stay within 1.2 height units of the centre.
static func flat_spot(terrain: PbTerrain, px: float, pz: float,
		target: float) -> Variant:
	var best = null
	for i in 24:
		var angle := PbRng.randf_range(0.0, TAU)
		var dist := PbRng.randf_range(8.0, 28.0)
		var cx := px + cos(angle) * dist
		var cz := pz + sin(angle) * dist
		# Terrain.randomPoint's own acceptance test.
		if not terrain.in_bounds(cx, cz, 6.0) or not terrain.is_flat_open(cx, cz):
			continue
		var base := terrain.height(cx, cz)
		var radius := target
		while radius >= MIN_RADIUS:
			var ok := terrain.in_bounds(cx, cz, radius + 2.0)
			for step in 12:
				var a := float(step) / 12.0 * PI * 2.0
				for ratio in [0.5, 1.0]:
					if absf(terrain.height(cx + cos(a) * radius * float(ratio),
							cz + sin(a) * radius * float(ratio)) - base) > 1.2:
						ok = false
			if ok:
				break
			radius -= 1.0
		if radius >= MIN_RADIUS and (best == null or radius > float(best["r"])):
			best = {"x": cx, "z": cz, "r": radius}
		if best != null and float(best["r"]) >= target:
			break
	return best


## Push one hazard into the list and toast its `say` line (spawn-time only, like
## the web `a.ui.toast(o.say(), null)` — there is no separate "stepped on" toast).
static func spawn(state: Dictionary, kind: String, x: float, z: float, radius: float,
		life: float) -> Dictionary:
	var def := def_of(kind)
	if def.is_empty():
		return {}
	var controller := ensure(state)
	controller["nextId"] = int(controller.get("nextId", 0)) + 1
	var hazard := {
		"id": int(controller["nextId"]),
		"kind": kind, "x": x, "z": z, "r": radius,
		"age": 0.0, "life": life, "tick": FIRST_TICK,
		"rot": PbRng.randf_range(0.0, TAU), "alpha": 0.0,
	}
	list(state).append(hazard)
	var say := localized(kind, "say")
	if not say.is_empty():
		PbRun._message(state, say)
	return hazard


# ------------------------------------------------------------------ effects
## One frame of lifecycle + effects. Player effects only while grounded (the
## port has no airborne state, so that check is always true).
static func update(state: Dictionary, dt: float) -> void:
	var controller := ensure(state)
	var player := PbJson.as_dict(state.get("player", {}))
	player["hazardSlow"] = 1.0
	var entries := list(state)
	for index in range(entries.size() - 1, -1, -1):
		var hazard := PbJson.as_dict(entries[index])
		hazard["age"] = float(hazard["age"]) + dt
		var active_end := INTRO + float(hazard["life"])
		if float(hazard["age"]) >= active_end + FADE:
			entries.remove_at(index)
			continue
		var age := float(hazard["age"])
		hazard["alpha"] = 0.35 + 0.15 * sin(age * 12.0) if age < INTRO \
			else (1.0 if age < active_end else 1.0 - (age - active_end) / FADE)
		if age < INTRO:
			continue
		if age >= active_end:
			continue
		hazard["tick"] = float(hazard["tick"]) - dt
		var reached := float(hazard["tick"]) <= 0.0
		if reached:
			hazard["tick"] = TICK
		_affect_player(state, player, hazard, dt, reached)
		_affect_enemies(state, hazard, dt, reached)


static func _affect_player(state: Dictionary, player: Dictionary, hazard: Dictionary,
		dt: float, reached: bool) -> void:
	var def := def_of(str(hazard["kind"]))
	var dx := float(hazard["x"]) - float(player.get("x", 0.0))
	var dz := float(hazard["z"]) - float(player.get("z", 0.0))
	var dist := sqrt(dx * dx + dz * dz)
	var inside := dist < float(hazard["r"])
	if inside:
		player["hazardSlow"] = minf(float(player.get("hazardSlow", 1.0)),
			float(def.get("slow", 1.0)))
		var pull := float(def.get("pull", 0.0))
		if pull > 0.0 and dist > 0.5:
			var step := pull * dt * (1.0 - dist / float(hazard["r"]) * 0.5)
			player["x"] = float(player.get("x", 0.0)) + dx / dist * step
			player["z"] = float(player.get("z", 0.0)) + dz / dist * step
	hazard["tick"] = float(hazard["tick"]) - dt
	if not (reached and inside):
		return
	var hurt := float(def.get("hurt", 0.0))
	if hurt <= 0.0:
		return
	var amount := float(player.get("maxHp", 1.0)) * hurt
	var dealt := PbActor.damage(player, amount)
	PbJson.as_dict(state.get("stats", {}))["damageTaken"] = \
		float(PbJson.as_dict(state.get("stats", {})).get("damageTaken", 0.0)) + dealt


static func _affect_enemies(state: Dictionary, hazard: Dictionary, dt: float,
		reached: bool) -> void:
	var def := def_of(str(hazard["kind"]))
	var pool := PbJson.as_dict(state.get("enemies", {}))
	var slow := float(def.get("slow", 1.0)) * 0.9
	var pull := float(def.get("pull", 0.0))
	var bite := float(def.get("bite", 0.0))
	var status := str(def.get("status", ""))
	for entry in PbEnemies.within(pool, float(hazard["x"]), float(hazard["z"]),
			float(hazard["r"])):
		var index := int(entry)
		if PbEnemies.flags(pool, index) & int(PbEnemies.Flag["Flying"]) != 0:
			continue
		PbEnemies.set_field(pool, "hazSlow", index,
			minf(float(PbEnemies.get_field(pool, "hazSlow", index)), slow))
		if pull > 0.0:
			var dx := float(hazard["x"]) - float(PbEnemies.get_field(pool, "x", index))
			var dz := float(hazard["z"]) - float(PbEnemies.get_field(pool, "z", index))
			var dist := sqrt(dx * dx + dz * dz)
			if dist > 0.5:
				PbEnemies.set_field(pool, "x", index,
					float(PbEnemies.get_field(pool, "x", index)) + dx / dist * pull * 1.3 * dt)
				PbEnemies.set_field(pool, "z", index,
					float(PbEnemies.get_field(pool, "z", index)) + dz / dist * pull * 1.3 * dt)
		if not reached or bite <= 0.0:
			continue
		var factor := 0.1 if PbEnemies.flags(pool, index) & DAMAGE_FACTOR_FLAGS != 0 else 1.0
		var amount := float(PbEnemies.get_field(pool, "maxHp", index)) * bite * factor
		var result := PbEnemies.damage(pool, index, amount)
		PbJson.as_dict(state.get("stats", {}))["damage"] = \
			float(PbJson.as_dict(state.get("stats", {})).get("damage", 0.0)) \
			+ float(result.get("dealt", 0.0))
		if bool(result.get("capture", false)):
			PbCapture.on_defeated(state)
		elif bool(result.get("alpha", false)):
			if not PbCapture.on_defeated(state, index) and PbEnemies.is_alive(pool, index):
				var info := PbEnemies.kill(pool, index)
				if info != null:
					PbRun._on_kill_info(state, PbJson.as_dict(info))
		elif bool(result.get("died", false)):
			PbRun._on_kill_info(state, PbJson.as_dict(result.get("info", {})))
		if PbEnemies.is_alive(pool, index) and not status.is_empty() \
				and PbStatus.roll(status, 0.5):
			PbEnemies.apply_status(pool, index, status, 1.0, amount, 1.0)
