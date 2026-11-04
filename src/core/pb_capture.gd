class_name PbCapture
extends RefCounted
## Ball capture, ported from two bundle classes:
##   * League/shiny weakened encounter  -- ``kS`` (offset 1074615)
##   * Alpha down window               -- ``Cg`` (offset 543430)
##
## A capturable encounter is not a wild Pokémon to ball at random: its HP is
## floored at 1 % (League weakT 10 s, Alpha downT 8 s), then the player throws
## an Amigo Ball from < 9 world units. A normal kill only credits XP/gold; it
## never writes ``captured``. Dex ``seen`` is written by PbRun when the species
## appears.

## kS.spawnAt = F.range(50,120), escapeT = 150 for non-legendary league members.
const SPAWN_MIN := 50.0
const SPAWN_MAX := 120.0
const ESCAPE_T := 150.0
const WEAK_T := 10.0
const RETRY_WEAK_T := 6.0
const ALPHA_DOWN_T := 8.0
const THROW_RANGE := 9.0
const THROW_TIME := 0.75
## kS.throwBall: .55 + rate/255*.35 + attempts*.2, cap .97.
## Cg.throwBall: .45 + rate/255*.35 + attempts*.2, cap .95.
const LEAGUE_BASE := 0.55
const ALPHA_BASE := 0.45
const RATE_SCALE := 0.35
const ATTEMPT_BONUS := 0.2
const STATUS_BONUS := 0.15
const LEAGUE_MAX := 0.97
const ALPHA_MAX := 0.95
## kS.onDefeated/recover: 1 % -> 40 %. Cg.intercept/breakFree: 1 % -> 30 %.
const WEAK_HP := 0.01
const RECOVER_HP := 0.4
const ALPHA_ESCAPE_HP := 0.3
const MAX_ATTEMPTS := 3
## Base party size; lab "party" raises it (lab.json: de 2 a 3).
const BASE_PARTY_CAP := 2


static func create(state: Dictionary) -> void:
	if str(state.get("mode", "standard")) != "standard":
		return
	state["capture"] = {
		"state": "idle",
		"mode": "league",
		"leagueDone": false,
		"spawnAt": PbRng.randf_range(SPAWN_MIN, SPAWN_MAX),
		"index": -1,
		"species": 0,
		"family": 0,
		"gen": 0,
		"attempts": 0,
		"alphaAttempts": {},
		"weakT": 0.0,
		"downT": 0.0,
		"escapeT": 0.0,
		"shakes": 0,
		"outcome": false,
		"throwT": 0.0,
		"stage": 0,
		"sure": false,
	}


static func data_of(state: Dictionary) -> Dictionary:
	return PbJson.as_dict(state.get("capture", {}))


## Both the league weakT window and the Alpha downT window block player attacks.
static func is_weakened(state: Dictionary) -> bool:
	var cap := data_of(state)
	return str(cap.get("state", "")) in ["weakened", "down"]


static func mode(state: Dictionary) -> String:
	return str(data_of(state).get("mode", "league"))


static func index(state: Dictionary) -> int:
	return int(data_of(state).get("index", -1))


static func species(state: Dictionary) -> int:
	return int(data_of(state).get("species", 0))


## Per-frame driver (kS.update @1075700 / Cg.update).
static func tick(state: Dictionary, dt: float) -> void:
	var cap := data_of(state)
	if cap.is_empty():
		return
	var pool := PbJson.as_dict(state["enemies"])
	match str(cap.get("state", "idle")):
		"idle":
			if not bool(cap.get("leagueDone", false)) \
					and float(state.get("stageT", 0.0)) >= float(cap.get("spawnAt", 0.0)):
				_spawn(state)
		"roaming":
			if not _target_alive(state):
				cap["state"] = "done"
				cap["leagueDone"] = true
				_clear(state)
				return
			cap["escapeT"] = float(cap["escapeT"]) - dt
			if float(cap["escapeT"]) <= 0.0:
				_flee(state)
		"weakened":
			if not _target_alive(state):
				cap["state"] = "done"
				cap["leagueDone"] = true
				_clear(state)
				return
			# kS.update: stun=.5 while weakened, so it never attacks between throws.
			PbEnemies.set_field(pool, "stun", int(cap["index"]), 0.5)
			if not bool(cap.get("sure", false)):
				cap["weakT"] = float(cap["weakT"]) - dt
				if float(cap["weakT"]) <= 0.0:
					_recover(state)
		"down":
			# Cg.update: stun=.5 for the 8 s down window; timeout = faint().
			if not _target_alive(state):
				cap["state"] = "idle"
				cap["index"] = -1
				return
			PbEnemies.set_field(pool, "stun", int(cap["index"]), 0.5)
			cap["downT"] = float(cap["downT"]) - dt
			if float(cap["downT"]) <= 0.0:
				_faint(state)
		"throwing":
			cap["throwT"] = float(cap["throwT"]) - dt
			if float(cap["throwT"]) <= 0.0:
				_resolve(state)


## League spawn (kS.spawnEncounter @1078302). The web picks a `leagueReady()`
## member; this port has no roster yet, so the player's family root stands in.
## A league starter is `common`: hp x0.8, damage x1, escapeT 150 (@1077812).
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
	cap["mode"] = "league"
	cap["index"] = index
	cap["species"] = chosen
	cap["family"] = int(species_def.get("family", chosen))
	cap["gen"] = int(PbEnemies.get_field(pool, "gen", index))
	cap["attempts"] = 0
	cap["sure"] = false
	cap["escapeT"] = ESCAPE_T
	cap["stage"] = int(state.get("stage", 1))
	PbRun._mark_seen(state, chosen)
	var display := _display_name(chosen)
	PbRun._message(state, "banner|%s|%s|#36c9ff" % [
		App.ui("¡{name} salvaje apareció!", {"name": display}),
		App.ui("Reto completado: debilítalo y captúralo para unirlo a tu Liga")])


## Lethal damage lands here instead of a kill.
##   * Alpha flag  -> ``Cg.intercept`` (down 8 s, 1 % HP).
##   * League     -> ``kS.onDefeated`` (weakened 10 s, 1 % HP).
## Returns true when the hit was consumed by a capture window.
static func on_defeated(state: Dictionary, hit_index: int = -1) -> bool:
	if hit_index >= 0:
		var pool := PbJson.as_dict(state["enemies"])
		if not PbEnemies.is_alive(pool, hit_index):
			return false
		if PbEnemies.flags(pool, hit_index) & int(PbEnemies.Flag["Alpha"]) != 0:
			return _begin_alpha(state, hit_index)
	var cap := data_of(state)
	if str(cap.get("state", "")) != "roaming":
		return false
	if not _target_alive(state):
		return false
	cap["state"] = "weakened"
	cap["mode"] = "league"
	cap["weakT"] = WEAK_T
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap["index"])
	PbEnemies.set_field(pool, "hp", i, float(PbEnemies.get_field(pool, "maxHp", i)) * WEAK_HP)
	PbEnemies.set_field(pool, "flags", i,
		int(PbEnemies.get_field(pool, "flags", i)) | int(PbEnemies.Flag["Capture"]))
	var display := _display_name(int(cap["species"]))
	PbRun._message(state, "banner|%s|%s|#5af0ff" % [
		App.ui("¡{name} está debilitado!", {"name": display}),
		App.ui("Acércate y {key} para lanzar la Poké Ball", {"key": "E"})])
	return true


## Cg.intercept @544603. The Alpha keeps per-generation attempts and joins the
## run's support team (never the profile league).
static func _begin_alpha(state: Dictionary, hit_index: int) -> bool:
	var cap := data_of(state)
	if str(cap.get("state", "")) == "down":
		return int(cap.get("index", -1)) == hit_index
	# A separate Alpha manager in the web build; here one league encounter owns
	# the state, so an active league window blocks the interception.
	if str(cap.get("state", "")) not in ["idle", "done"]:
		return false
	var pool := PbJson.as_dict(state["enemies"])
	var species_id := int(PbEnemies.get_field(pool, "species", hit_index))
	var species_def := PbData.species(species_id)
	cap["state"] = "down"
	cap["mode"] = "alpha"
	cap["index"] = hit_index
	cap["species"] = species_id
	cap["family"] = int(species_def.get("family", species_id))
	cap["gen"] = int(PbEnemies.get_field(pool, "gen", hit_index))
	cap["downT"] = ALPHA_DOWN_T
	cap["sure"] = false
	var max_hp := float(PbEnemies.get_field(pool, "maxHp", hit_index))
	PbEnemies.set_field(pool, "hp", hit_index, max_hp * WEAK_HP)
	PbEnemies.set_field(pool, "burn", hit_index, 0.0)
	PbEnemies.set_field(pool, "poison", hit_index, 0.0)
	PbRun._mark_seen(state, species_id)
	var display := _display_name(species_id)
	var label := App.ui(PbData.type_label(str(_first_type(species_def))))
	var allies: Array = PbJson.as_array(state["stats"].get("allies", []))
	var full := allies.size() >= _party_cap()
	var key := ("{key} cerca: Amigo Ball para que luche contigo esta partida (tu equipo está lleno: tendrás que liberar a uno; no se une a tu Liga) · si no, soltará su premio"
		if full else "{key} cerca: Amigo Ball para que luche contigo esta partida (no se une a tu Liga) · si no, soltará su premio")
	PbRun._message(state, "banner|%s|%s|#5af0ff" % [
		App.ui("¡{name} Alfa está debilitado!", {"name": display}),
		App.ui("Apoyo: {label}", {"label": label}) + " · " + App.ui(key, {"key": "E"})])
	return true


## Throw attempt (kS.throwBall @1082671 / Cg.throwBall @544603). Chance uses the
## attempts already spent, so the first ball is always the hardest.
static func throw_ball(state: Dictionary) -> bool:
	var cap := data_of(state)
	if cap.is_empty() or str(state.get("state", "play")) != "play":
		return false
	var wanted := "down" if mode(state) == "alpha" else "weakened"
	if str(cap.get("state", "")) != wanted:
		return false
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap.get("index", -1))
	if i < 0 or not PbEnemies.is_alive(pool, i):
		return false
	var dx := float(PbEnemies.get_field(pool, "x", i)) - PbRun.player_x(state)
	var dz := float(PbEnemies.get_field(pool, "z", i)) - PbRun.player_z(state)
	if sqrt(dx * dx + dz * dz) >= THROW_RANGE:
		return false
	var chance := chance_for(state)
	var limit := ALPHA_MAX if mode(state) == "alpha" else LEAGUE_MAX
	var guaranteed := _guaranteed(state)
	var hit := guaranteed or PbRng.chance(minf(limit, chance))
	cap["state"] = "throwing"
	cap["throwT"] = THROW_TIME
	cap["outcome"] = hit
	cap["shakes"] = 3 if hit else 1 + int(floor(PbRng.randf() * 3.0))
	PbRun._message(state, App.ui("¡Adelante, Poké Ball!"))
	return true


## Success rate exposed for the HUD and the smoke test.
## League: .55 + rate/255*.35 + attempts*.2, cap .97.
## Alpha:  .45 + rate/255*.35 + attempts*.2, cap .95.
## Status (paralysis/sleep/freeze) adds .15; sure/master-ball returns 1.
static func chance_for(state: Dictionary) -> float:
	var cap := data_of(state)
	var species_id := int(cap.get("species", 0))
	if species_id == 0:
		return 0.0
	if _guaranteed(state):
		return 1.0
	var alpha := str(cap.get("mode", "league")) == "alpha"
	var species_def := PbData.species(species_id)
	var rate := float(species_def.get("captureRate", 0.0))
	var attempts := _attempts(cap)
	var chance := (ALPHA_BASE if alpha else LEAGUE_BASE) + rate / 255.0 * RATE_SCALE \
		+ float(attempts) * ATTEMPT_BONUS
	var pool := PbJson.as_dict(state["enemies"])
	var i := int(cap.get("index", -1))
	if i >= 0 and PbEnemies.is_alive(pool, i):
		for kind in ["paralysis", "sleep", "freeze"]:
			if float(PbEnemies.get_field(pool, kind, i)) > 0.0:
				chance += STATUS_BONUS
				break
	return minf(ALPHA_MAX if alpha else LEAGUE_MAX, chance)


static func _attempts(cap: Dictionary) -> int:
	if str(cap.get("mode", "league")) == "alpha":
		return int(PbJson.as_dict(cap.get("alphaAttempts", {})).get(str(cap.get("gen", 0)), 0))
	return int(cap.get("attempts", 0))


static func _guaranteed(state: Dictionary) -> bool:
	var cap := data_of(state)
	if bool(cap.get("sure", false)):
		return true
	return PbActor.item_power(state["player"], "master-ball") > 0.0


static func _resolve(state: Dictionary) -> void:
	var cap := data_of(state)
	if bool(cap.get("outcome", false)):
		_caught(state)
	else:
		_break_free(state)


static func _caught(state: Dictionary) -> void:
	if mode(state) == "alpha":
		_caught_alpha(state)
	else:
		_caught_league(state)


## kS.caught @1086500: kill, joinLeague(), stats.captured, dex seen.
static func _caught_league(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var species_id := int(cap["species"])
	var family := int(cap["family"])
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.kill(pool, i)
	cap["state"] = "done"
	cap["leagueDone"] = true
	cap["index"] = -1
	_clear(state)
	var stats: Dictionary = state["stats"]
	var captured: Array = PbJson.as_array(stats.get("captured", []))
	if not captured.has(family):
		captured.append(family)
	stats["captured"] = captured
	PbRun._mark_seen(state, species_id)
	# joinLeague() @1667709 runs immediately on a successful catch.
	Save.apply_actions([
		{"t": "joinLeague", "id": family},
		{"t": "capture", "id": family},
		{"t": "unlock", "id": family},
		{"t": "seen", "id": species_id},
	])
	Save.save()
	var display := _display_name(family)
	PbRun._message(state, "banner|%s|%s|#ffb21a" % [
		App.ui("¡{name} se une a tu Liga!", {"name": display}),
		App.ui("Ya puedes elegirlo al empezar una partida")])


## Cg.caught @546700: kill, counters.alphaCaught + stats.allies, never joined
## to the profile league. A full party opens the replacement modal in the web UI;
## this port only has banner/toast feedback for that branch.
static func _caught_alpha(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var species_id := int(cap["species"])
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.kill(pool, i)
	cap["state"] = "idle"
	cap["index"] = -1
	_clear(state)
	var stats: Dictionary = state["stats"]
	var allies: Array = PbJson.as_array(stats.get("allies", []))
	var full := allies.size() >= _party_cap()
	allies.append(species_id)
	stats["allies"] = allies
	Save.apply_actions([{"t": "count", "id": "alphaCaught", "v": 1}])
	Save.save()
	var display := _display_name(species_id)
	if full:
		PbRun._message(state, App.ui("{name} vuelve al bosque. ¡Hasta pronto!",
			{"name": display}))
		return
	var label := App.ui(PbData.type_label(_first_type(PbData.species(species_id))))
	PbRun._message(state, "banner|%s|%s|#36c96a" % [
		App.ui("¡{name} te acompaña esta partida!", {"name": display}),
		App.ui("Alfa de apoyo · {label} · no se une a tu Liga", {"label": label})])


static func _break_free(state: Dictionary) -> void:
	if mode(state) == "alpha":
		_alpha_break_free(state)
		return
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


## Cg.breakFree @545960: attempts per gen, 30 % HP and back to the arena.
static func _alpha_break_free(state: Dictionary) -> void:
	var cap := data_of(state)
	var gen := int(cap.get("gen", 0))
	var attempts := PbJson.as_dict(cap.get("alphaAttempts", {})).duplicate()
	attempts[str(gen)] = int(attempts.get(str(gen), 0)) + 1
	cap["alphaAttempts"] = attempts
	var i := int(cap["index"])
	var pool := PbJson.as_dict(state["enemies"])
	var alive := PbEnemies.is_alive(pool, i)
	cap["state"] = "idle"
	cap["index"] = -1
	if alive:
		PbEnemies.set_field(pool, "hp", i,
			float(PbEnemies.get_field(pool, "maxHp", i)) * ALPHA_ESCAPE_HP)
		PbEnemies.set_field(pool, "stun", i, 0.0)
		PbRun._message(state, App.ui("¡Se ha escapado! Debilítalo otra vez: el siguiente lanzamiento será más fácil"))


static func _flee(state: Dictionary) -> void:
	var cap := data_of(state)
	var species_id := int(cap["species"])
	var pool := PbJson.as_dict(state["enemies"])
	var display := _display_name(species_id)
	PbEnemies.kill(pool, int(cap["index"]))
	cap["state"] = "done"
	cap["leagueDone"] = true
	cap["index"] = -1
	_clear(state)
	PbRun._message(state, "banner|%s|%s|#8a90a8" % [
		App.ui("¡{name} ha huido...", {"name": display}),
		App.ui("Volverá a aparecer en otra partida")])


## kS.recover @1085320: 40 % HP back to roaming.
static func _recover(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var pool := PbJson.as_dict(state["enemies"])
	PbEnemies.set_field(pool, "hp", i,
		float(PbEnemies.get_field(pool, "maxHp", i)) * RECOVER_HP)
	cap["state"] = "roaming"
	PbRun._message(state, App.ui("¡{name} se ha recuperado y huye!",
		{"name": _display_name(int(cap["species"]))}))


## Cg.downT timeout -> faint(): the Alpha drops its reward and is killed.
static func _faint(state: Dictionary) -> void:
	var cap := data_of(state)
	var i := int(cap["index"])
	var pool := PbJson.as_dict(state["enemies"])
	var info: Variant = PbEnemies.kill(pool, i)
	cap["state"] = "idle"
	cap["index"] = -1
	_clear(state)
	if info != null:
		PbRun._on_kill_info(state, PbJson.as_dict(info))


static func _clear(state: Dictionary) -> void:
	var pool := PbJson.as_dict(state["enemies"])
	pool["capture_index"] = -1


static func _target_alive(state: Dictionary) -> bool:
	var cap := data_of(state)
	var i := int(cap.get("index", -1))
	if i < 0:
		return false
	return PbEnemies.is_alive(PbJson.as_dict(state["enemies"]), i)


static func _party_cap() -> int:
	return BASE_PARTY_CAP + Save.lab("party")


static func _first_type(species_def: Dictionary) -> String:
	var types: Array = PbJson.as_array(species_def.get("types", ["normal"]))
	return str(types[0]) if types.size() > 0 else "normal"


static func _display_name(species_id: int) -> String:
	var def := PbData.species(species_id)
	return App.t("pokemon", int(def.get("id", species_id)), str(def.get("name", "?")))
