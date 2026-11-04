class_name PbEvo
extends RefCounted
## Evolution runtime: the run-level half of the web's `runEvolution` (@6543),
## `evoReady`/`tryEvolve` (@1541178/@1541278) and `startEvolution` (@1543295).
##
## The species table already carries `evoFrom`/`evoLevel`/`evoStage`, so the
## reverse index lives in PbData.evolutions_of (bundle @5379). There is no extra
## data file to maintain.
##
## Roster/league mode is not ported: `plan_evolution` ignores roster overrides
## and `try_evolve` leaves the `to == -1` branch UI as a stub.

const DURATION := 3.6
const SHOCK_RADIUS := 18.0
## Family bits used by the completion shockwave (web `R.Boss | 12290`; 12290 is
## Alpha|Totem|Summoner).
const FAMILY_FLAGS := 4 | 2 | 4096 | 8192


## Bundle `runEvolution(e,t)` (@6543). Returns {"to": species_id, "level": int}
## or {} when the species has no next form.
## Level formula: another form exists -> clamp(8+a,16,30); final form ->
## clamp(22+a*.6,36,50), where a = evoLevel ?? (source evoStage==0 ? 20 : 34).
static func run_evolution(species_id: int, forced_id: int = -1) -> Dictionary:
	var nexts := PbData.evolutions_of(species_id)
	if nexts.is_empty():
		return {}
	var chosen := {}
	if forced_id >= 0:
		for raw in nexts:
			var entry := PbJson.as_dict(raw)
			if int(entry.get("id", -1)) == forced_id:
				chosen = entry
				break
		if chosen.is_empty():
			return {}
	elif nexts.size() > 1:
		chosen = PbJson.as_dict(PbRng.pick(nexts))
	else:
		chosen = PbJson.as_dict(nexts[0])
	var to_id := int(chosen.get("id", -1))
	if to_id < 0:
		return {}
	var source := PbData.species(species_id)
	var a := 20.0 if int(source.get("evoStage", 0)) == 0 else 34.0
	var evo_level = chosen.get("evoLevel")
	if evo_level != null:
		a = float(evo_level)
	var level := 0
	if PbData.evolutions_of(to_id).size() > 0:
		level = clampi(int(roundf(8.0 + a)), 16, 30)
	else:
		level = clampi(int(roundf(22.0 + a * 0.6)), 36, 50)
	return {"to": to_id, "level": level}


## Bundle `planEvolution(e,t)` (@1514341). The port's runs have no roster, so a
## roster `branch` / `evoLevels` override is intentionally skipped; the plain
## result is raised to `level_arg`.
static func plan_evolution(actor: Variant, level_arg: int) -> Dictionary:
	var species_id := 0
	if actor is Dictionary:
		species_id = int(PbJson.as_dict(actor).get("species_id", 0))
	else:
		species_id = int(actor)
	var step := run_evolution(species_id)
	if step.is_empty():
		return {}
	return {"to": int(step["to"]), "level": maxi(int(step["level"]), level_arg)}


## Bundle `evoReady()` (@1541178): level reached and the target has a sprite.
## `to == -1` belongs to the roster branch picker (showBranch @2190988), which the
## port has no mode for yet.
static func ready(player: Dictionary, next_evo: Dictionary) -> bool:
	if next_evo.is_empty():
		return false
	if int(player.get("level", 1)) < int(next_evo.get("level", 9999)):
		return false
	var to_id := int(next_evo.get("to", -1))
	if to_id == -1:
		return false
	return PbData.sprites_map().has(str(to_id))


## Bundle `tryEvolve()` (@1541278): start the cinematic, or leave the branch
## picker as an unimplemented hook.
static func try_evolve(state: Dictionary) -> bool:
	var player := PbJson.as_dict(state.get("player", {}))
	var next_evo := PbJson.as_dict(state.get("nextEvo", {}))
	if not ready(player, next_evo):
		return false
	if int(next_evo.get("to", -1)) == -1:
		# TODO(port): roster branch picker (`showBranch`), out of scope for 6e.
		return false
	start_evolution(state)
	return true


## Bundle `startEvolution()` (@1543295). Only the 3.6s timer and the state
## transition live here; the sprite flashing/flash particles are presentation and
## stay in run_screen (the existing avatar swap already follows species_id).
static func start_evolution(state: Dictionary) -> void:
	var player := PbJson.as_dict(state.get("player", {}))
	var old_id := int(player.get("species_id", 0))
	var to_id := int(PbJson.as_dict(state.get("nextEvo", {})).get("to", -1))
	if old_id <= 0 or to_id < 0:
		return
	state["state"] = "evolving"
	state["offers"] = []
	state["evo"] = {
		"from": old_id,
		"to": to_id,
		"t": DURATION,
		"oldMaxHp": int(roundf(float(player.get("maxHp", 0.0)))),
	}
	PbRun._message(state, App.ui("¿Eh? ¡{name} está evolucionando!",
		{"name": _display_name(old_id)}))


## Advances the cinematic; completion runs the settlement sequence.
static func tick(state: Dictionary, dt: float) -> void:
	var evo := PbJson.as_dict(state.get("evo", {}))
	if evo.is_empty():
		state["state"] = "play"
		return
	evo["t"] = maxf(0.0, float(evo.get("t", 0.0)) - dt)
	state["evo"] = evo
	# Float subtraction can leave a sliver (3.6-3.0-0.6 != 0); treat it as done.
	if float(evo["t"]) > 0.0001:
		return
	_complete(state, evo)


## Bundle `setSpecies(e)` (@837293). HP rule is "at least 80% of the new max":
## hp = min(newMax, newMax*max(t,.5) + newMax*.3). Moves are neither inherited nor
## learned here -- the web keeps the move list untouched.
static func set_species(player: Dictionary, new_id: int) -> void:
	var data := PbData.species(new_id)
	if data.is_empty():
		return
	var old_max := float(player.get("maxHp", 0.0))
	var ratio := 0.0
	if old_max > 0.0:
		ratio = float(player.get("hp", 0.0)) / old_max
	player["species_id"] = int(data.get("id", new_id))
	player["species_key"] = str(data.get("key", ""))
	# The web reads `name` off the data table; the port caches it for the HUD.
	player["name"] = str(data.get("name", ""))
	player["data"] = data
	player["types"] = PbJson.as_array(data.get("types", ["normal"]))
	player["evo_stage"] = int(player.get("evo_stage", 0)) + 1
	PbActor.recompute(player)
	var new_max := float(player.get("maxHp", old_max))
	player["hp"] = minf(new_max, new_max * maxf(ratio, 0.5) + new_max * 0.3)


## Settlement order from §3.5: setSpecies, flash/iframes, nextEvo, stats,
## firstEvoAt, account count, dex form, shockwave, reveal.
static func _complete(state: Dictionary, evo: Dictionary) -> void:
	var player := PbJson.as_dict(state.get("player", {}))
	var from_id := int(evo.get("from", 0))
	var to_id := int(evo.get("to", 0))
	var old_max := float(evo.get("oldMaxHp", 0.0))
	player["species_id"] = from_id
	set_species(player, to_id)
	player["flash"] = 1
	player["renderScale"] = 1.0
	player["iframes"] = maxf(float(player.get("iframes", 0.0)), 2.6)
	state["nextEvo"] = plan_evolution(player, int(player.get("level", 1)) + 3)
	var stats := PbJson.as_dict(state.get("stats", {}))
	stats["evolutions"] = int(stats.get("evolutions", 0)) + 1
	state["stats"] = stats
	if state.get("firstEvoAt") == null:
		state["firstEvoAt"] = float(state.get("time", 0.0))
	Save.apply_actions([
		{"t": "count", "id": "evolutions", "v": 1},
		{"t": "form", "id": to_id},
	])
	Save.save()
	_shockwave(state, player)
	PbRun._message(state, "banner|%s|%s|#f7c948|big" % [
		App.ui("¡Enhorabuena! {name} ha evolucionado a", {"name": _display_name(from_id)}),
		"%s · %s %d → %d" % [_display_name(to_id), App.ui("PS máx."),
			int(roundf(old_max)), int(roundf(float(player.get("maxHp", 0.0))))]])
	state["evoHold"] = 2.4
	state["state"] = "play"
	state.erase("evo")
	# The level-up that triggered this evolution is consumed (doLevelUp @1541606).
	state["pendingLevels"] = maxi(0, int(state.get("pendingLevels", 0)) - 1)
	if int(state.get("pendingLevels", 0)) > 0:
		PbRun.open_offers(state)


## Radius-18 shockwave (bundle @1543295): capture targets are skipped; boss-family
## flags take 5% maxHp, everything else `80 * player.level`.
static func _shockwave(state: Dictionary, player: Dictionary) -> void:
	var pool := PbJson.as_dict(state.get("enemies", {}))
	var x := float(player.get("x", 0.0))
	var z := float(player.get("z", 0.0))
	var level := float(player.get("level", 1))
	for raw in PbEnemies.within(pool, x, z, SHOCK_RADIUS):
		var index := int(raw)
		var flags := int(PbEnemies.get_field(pool, "flags", index))
		if flags & int(PbEnemies.Flag["Capture"]) != 0:
			continue
		var amount := 80.0 * level
		if flags & FAMILY_FLAGS != 0:
			amount = float(PbEnemies.get_field(pool, "maxHp", index)) * 0.05
		var res := PbEnemies.damage(pool, index, amount)
		if bool(res.get("died", false)) and res.get("info") != null:
			PbRun._on_kill_info(state, PbJson.as_dict(res["info"]))


static func _display_name(species_id: int) -> String:
	var species := PbData.species(species_id)
	return App.t("pokemon", species_id, str(species.get("name", "")))
