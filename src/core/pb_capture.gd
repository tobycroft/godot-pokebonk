class_name PbCapture
extends RefCounted
## Poké Ball capture encounter, ported from the bundle class ``kS`` (offset
## 1074615): spawnEncounter / throwBall / breakFree / caught / recover.
##
## The web client spawns a capturable encounter 50-120 s into a stage. Once its
## HP hits zero it is *weakened* (1 % HP, 10 s window) instead of killed; the
## player throws a ball and the result is decided by the capture-rate formula.
## Only a successful throw writes ``stats.captured`` and the profile's
## ``unlocked`` list -- a plain kill never does (that only marks the species as
## seen, bundble @763264).

## kS.spawnAt = F.range(50,120), escapeT = 150 for non-legendary league members.
const SPAWN_MIN := 50.0
const SPAWN_MAX := 120.0
const ESCAPE_T := 150.0
const WEAK_T := 10.0
const RETRY_WEAK_T := 6.0
const THROW_RANGE := 9.0
const THROW_TIME := 0.75
## kS.canThrow/throwBall: .55 + captureRate/255*.35 + attempts*.2, status +.15,
## capped at .97 (master-ball or the scripted "sure" path ignores the roll).
const BASE_CHANCE := 0.55
const RATE_SCALE := 0.35
const ATTEMPT_BONUS := 0.2
const STATUS_BONUS := 0.15
const MAX_CHANCE := 0.97
## onDefeated(): hp = maxHp*.01, recover(): hp = maxHp*.4.
const WEAK_HP := 0.01
const RECOVER_HP := 0.4
const MAX_ATTEMPTS := 3


static func create(state: Dictionary) -> void:
	if str(state.get("mode", "standard")) != "standard":
		return
	state["capture"] = {
		"state": "idle",
		"spawnAt": PbRng.randf_range(SPAWN_MIN, SPAWN_MAX),
		"index": -1,
		"species": 0,
		"family": 0,
		"attempts": 0,
		"weakT": 0.0,
		"escapeT": 0.0,
		"shakes": 0,
		"outcome": false,
		"throwT": 0.0,
		"stage": 0,
	}


static func data_of(state: Dictionary) -> Dictionary:
	return PbJson.as_dict(state.get("capture", {}))


static func is_weakened(state: Dictionary) -> bool:
	return str(data_of(state).get("state", "")) == "weakened"


static func index(state: Dictionary) -> int:
	return int(data_of(state).get("index", -1))


static func species(state: Dictionary) -> int:
	return int(data_of(state).get("species", 0))


## Per-frame driver: spawn countdown, roaming escape timer, weakened window and
## ball throw resolution (kS.update @1075700).
static func tick(state: Dictionary, dt: float) -> void:
	var cap := data_of(state)
	if cap.is_empty():
		return
	var pool := PbJson.as_dict(state["enemies"])
	match str(cap.get("state", "idle")):
		"idle", "done":
			if float(state.get("stageT", 0.0)) >= float(cap.get("spawnAt", 0.0)):
				_spawn(state)
		"roaming":
			if not _target_alive(state):
				cap["state"] = "done"
				_clear(state)
				return
			cap["escapeT"] = float(cap["escapeT"]) - dt
			if float(cap["escapeT"]) <= 0.0:
				_flee(state)
		"weakened":
			if not _target_alive(state):
				cap["state"] = "done"
				_clear(state)
				return
			# kS.update: stun=.5 while weakened, so it never attacks between throws.
			PbEnemies.set_field(pool, "stun", int(cap["index"]), 0.5)
			cap["weakT"] = float(cap["weakT"]) - dt
			if float(cap["weakT"]) <= 0.0:
				_recover(state)
		"throwing":
			cap["throwT"] = float(cap["throwT"]) - dt
			if float(cap["throwT"]) <= 0.0:
				_resolve(state)


## Spawns the encounter (kS.spawnEncounter @1078302). The web picks the species
## from the player's league roster (leagueReady()); this port has no roster yet,
## so the player's own family root stands in. A league starter is the `common`
## tier: hp x0.8, damage x1, escapeT 150 (bundle @1077812).
static func _spawn(state: Dictionary) -> void:
	var cap := data_of(state)
	var pool := PbJson.as_dict(state["enemies"])
	var player: Dictionary = state["player"]
	var own := PbData.species(int(player.get("species_id", player.get("species", 0))))
	var chosen := int(own.get("family", 0))
	if chosen <= 0:
		cap["spawnAt"] = 1.0e9
		return
	var species_def := PbData.species(chosen)
	if species_def.is_empty():
		cap["spawnAt"] = 1.0e9
		return
	var angle := PbRng.randf_range(0.0, TAU)
	var dist := PbRng.randf_range(18.0, 32.0)
	var stage_t := float(state.get("stageT", 0.0))
	var difficulty := float(PbJson.as_dict(player.get("stats", {})).get("difficulty", 1.0))
	var index := PbEnemies.spawn(pool, chosen,
		PbRun.player_x(state) + cos(angle) * dist,
		PbRun.player_z(state) + sin(angle) * dist,
		int(state.get("stage", 1)), PbJson.as_dict(state["diff"]), "wild",
		PbCombat.hp_mult(int(state.get("stage", 1)), stage_t, PbJson.as_dict(state["diff"]), difficulty) * 0.8,
		PbCombat.dmg_mult(int(state.get("stage", 1)), stage_t), 1.0, stage_t)
	if index < 0:
		cap["spawnAt"] = 1.0e9
		return
	pool["capture_index"] = index
	PbEnemies.set_field(pool, "flags", index,
		int(PbEnemies.get_field(pool, "flags", index)) | int(PbEnemies.Flag["Capture"]))
	cap["state"] = "roaming"
	cap["index"] = index
	cap["species"] = chosen
	cap["family"] = int(species_def.get("family", chosen))
	cap["attempts"] = 0
	cap["escapeT"] = ESCAPE_T
	cap["stage"] = int(state.get("stage", 1))
	var stats: Dictionary = state["stats"]
	_mark_seen(state, chosen)
	var display := _display_name(chosen)
	PbRun._message(state, "banner|%s|%s|#f7c948" % [
		App.ui("¡{name} apareció!", {"name": display}),
		App.ui("Derrótalo y te esperará para que lo captures")])


## damage() sends lethal hits on the capture index here instead of killing it
## (bundle @763264: onDefeated). HP is clamped to 1 % and the target waits.
static func on_defeated(state: Dictionary) -> void:
	var cap := data_of(state)
	if str(cap.get("state", "")) != "roaming":
		return
	if not _target_alive(state):
		return
	cap["state"] = "weakened"
	cap["weakT"] = WEAK_T
	cap["attempts"] = int(cap.get("attempts", 0))
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap["index"])
	PbEnemies.set_field(pool, "hp", i, float(PbEnemies.get_field(pool, "maxHp", i)) * WEAK_HP)
	PbEnemies.set_field(pool, "flags", i,
		int(PbEnemies.get_field(pool, "flags", i)) | int(PbEnemies.Flag["Capture"]))
	var display := _display_name(int(cap["species"]))
	PbRun._message(state, "banner|%s|%s|#8ae8ff" % [
		App.ui("¡{name} está debilitado!", {"name": display}),
		App.ui("Acércate y {key} para lanzar la Poké Ball", {"key": "E"})])


## Throw attempt (kS.throwBall @1082671). Chance uses the attempts already
## spent, so the first ball is always the hardest.
static func throw_ball(state: Dictionary) -> bool:
	var cap := data_of(state)
	if cap.is_empty() or str(state.get("state", "play")) != "play":
		return false
	if str(cap.get("state", "")) != "weakened":
		return false
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap.get("index", -1))
	if i < 0 or not PbEnemies.is_alive(pool, i):
		return false
	var player: Dictionary = state["player"]
	var dx := float(PbEnemies.get_field(pool, "x", i)) - PbRun.player_x(state)
	var dz := float(PbEnemies.get_field(pool, "z", i)) - PbRun.player_z(state)
	if sqrt(dx * dx + dz * dz) >= THROW_RANGE:
		return false
	var chance := chance_for(state)
	var guaranteed := PbActor.item_power(player, "master-ball") > 0.0
	var hit := guaranteed or PbRng.chance(minf(MAX_CHANCE, chance))
	cap["state"] = "throwing"
	cap["throwT"] = THROW_TIME
	cap["outcome"] = hit
	cap["shakes"] = 3 if hit else 1 + int(floor(PbRng.randf() * 3.0))
	PbRun._message(state, App.ui("¡Adelante, Poké Ball!"))
	return true


## Success rate exposed for the HUD and the smoke test. Mirrors
## 0.55 + captureRate/255*.35 + attempts*.2 (+0.15 with para/sleep/freeze).
static func chance_for(state: Dictionary) -> float:
	var cap := data_of(state)
	var species_id := int(cap.get("species", 0))
	if species_id == 0:
		return 0.0
	var species_def := PbData.species(species_id)
	var rate := float(species_def.get("captureRate", 0.0))
	var chance := BASE_CHANCE + rate / 255.0 * RATE_SCALE \
		+ float(cap.get("attempts", 0)) * ATTEMPT_BONUS
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap.get("index", -1))
	if i >= 0 and PbEnemies.is_alive(pool, i):
		for kind in ["paralysis", "sleep", "freeze"]:
			if float(PbEnemies.get_field(pool, kind, i)) > 0.0:
				chance += STATUS_BONUS
				break
	return minf(MAX_CHANCE, chance)


static func _resolve(state: Dictionary) -> void:
	var cap := data_of(state)
	if bool(cap.get("outcome", false)):
		_caught(state)
	else:
		_break_free(state)


static func _caught(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var species_id := int(cap["species"])
	var family := int(cap["family"])
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.kill(pool, i)
	_clear(state)
	var stats: Dictionary = state["stats"]
	var captured: Array = PbJson.as_array(stats.get("captures", []))
	if not captured.has(family):
		captured.append(family)
	stats["captures"] = captured
	_mark_seen(state, species_id)
	# joinLeague() @1667709 runs immediately on a successful catch.
	Save.apply_actions([
		{"t": "capture", "id": family},
		{"t": "unlock", "id": family},
		{"t": "seen", "id": species_id},
	])
	Save.save()
	var display := _display_name(species_id)
	PbRun._message(state, "banner|%s|%s|#7ee787" % [
		App.ui("¡{name} se une a tu Liga!", {"name": display}),
		App.ui("Nuevo en tu Pokédex")])


static func _break_free(state: Dictionary) -> void:
	var cap := data_of(state)
	cap["attempts"] = int(cap.get("attempts", 0)) + 1
	if int(cap["attempts"]) >= MAX_ATTEMPTS:
		_flee(state)
		return
	cap["state"] = "weakened"
	cap["weakT"] = RETRY_WEAK_T
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.set_field(pool, "hp", int(cap["index"]),
		float(PbEnemies.get_field(pool, "maxHp", int(cap["index"]))) * WEAK_HP)
	PbRun._message(state, App.ui("¡Se ha escapado! Inténtalo otra vez: cada lanzamiento es más fácil"))


static func _flee(state: Dictionary) -> void:
	var cap := data_of(state)
	var species_id := int(cap["species"])
	var pool := PbJson.as_dict(state["enemies"])
	var display := _display_name(species_id)
	PbEnemies.kill(pool, int(cap["index"]))
	cap["state"] = "done"
	_clear(state)
	PbRun._message(state, "banner|%s|%s|#8a90a8" % [
		App.ui("¡{name} ha huido...", {"name": display}),
		App.ui("Volverá a aparecer en otra partida")])


static func _recover(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.set_field(pool, "hp", i,
		float(PbEnemies.get_field(pool, "maxHp", i)) * RECOVER_HP)
	cap["state"] = "roaming"
	cap["attempts"] = int(cap.get("attempts", 0))
	PbRun._message(state, "banner|%s|%s|#8a90a8" % [
		App.ui("¡{name} se ha recuperado y huye!", {"name": _display_name(int(cap["species"]))}),
		App.ui("Derrótalo y te esperará para que lo captures")])


static func _clear(state: Dictionary) -> void:
	var pool := PbJson.as_dict(state["enemies"])
	pool["capture_index"] = -1


static func _target_alive(state: Dictionary) -> bool:
	var cap := data_of(state)
	var i := int(cap.get("index", -1))
	if i < 0:
		return false
	return PbEnemies.is_alive(PbJson.as_dict(state["enemies"]), i)


static func _mark_seen(state: Dictionary, species_id: int) -> void:
	var stats: Dictionary = state["stats"]
	var seen: Array = PbJson.as_array(stats.get("newSeen", []))
	if not seen.has(species_id):
		seen.append(species_id)
	stats["newSeen"] = seen
	Save.apply_actions([{"t": "seen", "id": species_id}])


static func _display_name(species_id: int) -> String:
	var def := PbData.species(species_id)
	return App.t("pokemon", int(def.get("id", species_id)), str(def.get("name", "?")))
