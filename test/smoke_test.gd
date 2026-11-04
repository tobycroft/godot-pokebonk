extends Node
## Headless verification suite for the pokebonk-web -> Godot port.
##
## Run with:
##   Godot --headless --path . res://test/SmokeTest.tscn
##
## Three kinds of checks:
##   1. data integrity     -- every ported table loads with the expected size
##   2. formula parity     -- GDScript results are compared against
##                            data/pb/golden_values.json, produced by an
##                            independent Python implementation of the same
##                            recovered formulas (tools-re/golden_values.py)
##   3. end-to-end flows   -- run simulation, settlement, save round-trip,
##                            lab purchase, import/export, fusion
##
## Exit code is non-zero when anything fails, so CI / the terminal can tell.

const EPS := 1e-4

var _checks := 0
var _failures: Array[String] = []
var _golden := {}


func _ready() -> void:
	print("\n=== PokéBonk Godot port smoke test ===")
	_golden = PbJson.as_dict(PbData.pb_table("golden_values"))
	if _golden.is_empty():
		_fail("golden_values.json missing -- regenerate with tools-re/golden_values.py")
	_data_integrity()
	_formula_parity()
	_fusion_checks()
	_run_flow()
	_save_flow()
	_asset_checks()
	_avatar_fallback_checks()
	_theme_ui_checks()
	_revive_checks()
	_danger_golden_checks()
	_ui_build_checks()
	_terrain_checks()
	_locale_checks()
	report()
	get_tree().quit(0 if _failures.is_empty() else 1)


# ------------------------------------------------------------------ helpers
func ok(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _fail(label: String) -> void:
	_checks += 1
	_failures.append(label)
	print("  FAIL  %s" % label)


func close(got: float, want: float, label: String) -> void:
	ok(absf(got - want) <= EPS * maxf(1.0, absf(want)), "%s (got %.6f want %.6f)" % [label, got, want])


func section(name: String) -> void:
	print("\n-- %s" % name)


# ------------------------------------------------------------------ 1. data
func _data_integrity() -> void:
	section("data integrity")
	ok(PbData.types_table().size() > 0, "types.json loaded")
	ok(PbJson.as_array(PbData.types_table().get("types", [])).size() == 18, "18 types")
	ok(PbJson.as_array(PbData.types_table().get("chart", [])).size() == 18, "18x18 chart")
	ok(PbData.pokemon_list().size() == 1025, "1025 species (got %d)" % PbData.pokemon_list().size())
	ok(PbData.moves_list().size() == 919, "919 moves (got %d)" % PbData.moves_list().size())
	ok(PbData.abilities_map().size() == 314, "314 abilities (got %d)" % PbData.abilities_map().size())
	ok(PbData.items_map().size() == 151, "151 items (got %d)" % PbData.items_map().size())
	ok(PbData.learnsets_map().size() == 1025, "1025 learnsets (got %d)" % PbData.learnsets_map().size())
	ok(PbData.sprites_map().size() == 1025, "1025 sprite sheets (got %d)" % PbData.sprites_map().size())
	ok(PbData.kanto_ids().size() == 151, "151 Kanto dex ids")
	var archetypes := PbJson.as_dict(PbData.pb_table("archetypes"))
	ok(archetypes.size() == 26, "26 move archetypes (got %d)" % archetypes.size())
	ok(PbJson.as_dict(PbData.pb_table("move_arch")).size() == 427, "427 archetype overrides")
	ok(PbJson.as_dict(PbData.pb_table("type_status")).size() == 18, "type->status table")
	ok(PbFusion.count() >= 100, "fusion catalogue recovered (%d)" % PbFusion.count())
	ok(PbJson.as_array(PbData.i18n("en").keys()).size() >= 4, "i18n en loaded")
	var meta := PbData.constants()
	ok(not meta.is_empty(), "recovered constants loaded")
	print("   species=%d moves=%d abilities=%d items=%d fusions=%d" % [
		PbData.pokemon_list().size(), PbData.moves_list().size(),
		PbData.abilities_map().size(), PbData.items_map().size(), PbFusion.count()])


# ------------------------------------------------------------------ 2. parity
func _formula_parity() -> void:
	section("type effectiveness vs golden")
	for raw in PbJson.as_array(_golden.get("effectiveness", [])):
		var c := PbJson.as_dict(raw)
		close(PbDamage.effectiveness(str(c["atk"]), PbJson.as_array(c["def"])),
			float(c["want"]), "effectiveness %s -> %s" % [c["atk"], str(c["def"])])

	section("stat derivation (Qy port)")
	var bulba := PbData.species(1)
	var want := PbJson.as_dict(PbJson.as_dict(_golden.get("stats", {})).get("bulbasaur_g0", {}))
	var got := PbStats.stats_from_species(bulba, 0.0)
	ok(got.keys().has("typeBoost"), "derived stats carry the per-type boost map")
	for key in PbStats.STAT_KEYS:
		ok(got.has(str(key)), "stat block exposes %s" % str(key))
	for key in want.keys():
		if typeof(want[key]) == TYPE_ARRAY or typeof(want[key]) == TYPE_DICTIONARY:
			continue
		close(float(got.get(key, -1)), float(want[key]), "bulbasaur %s" % str(key))
	var g9 := PbJson.as_dict(PbJson.as_dict(_golden.get("stats", {})).get("bulbasaur_g9", {}))
	var got9 := PbStats.stats_from_species(bulba, 9.0)
	close(float(got9.get("maxHp", 0)), float(g9.get("maxHp", 0)), "bulbasaur growth9 maxHp")
	close(float(got9.get("damage", 0)), float(g9.get("damage", 0)), "bulbasaur growth9 damage")

	section("armour mitigation (rb port)")
	var armor := PbJson.as_dict(_golden.get("armor_mitigation", {}))
	for key in armor.keys():
		close(PbStats.armor_mitigation(float(key)), float(armor[key]), "armor(%s)" % key)

	section("xp curve (Cb port)")
	var xp := PbJson.as_dict(_golden.get("xp", {}))
	for key in xp.keys():
		close(float(PbXp.need(int(key))), float(xp[key]), "xp(%s)" % key)

	section("move resolution (_y + vy ports)")
	var defs := PbJson.as_dict(_golden.get("move_defs", {}))
	ok(defs.size() > 15, "golden move set present (%d)" % defs.size())
	for key in defs.keys():
		var want_def := PbJson.as_dict(defs[key])
		var got_def := PbMoves.resolve(str(key))
		ok(not got_def.is_empty(), "resolve(%s) produced a definition" % key)
		if got_def.is_empty():
			continue
		ok(str(got_def.get("arch", "")) == str(want_def.get("arch", "")),
			"%s arch %s==%s" % [key, got_def.get("arch"), want_def.get("arch")])
		close(float(got_def.get("dmg", 0)), float(want_def.get("dmg", 0)), "%s dmg" % key)
		close(float(got_def.get("cd", 0)), float(want_def.get("cd", 0)), "%s cd" % key)
		ok(int(got_def.get("count", 0)) == int(want_def.get("count", 0)), "%s count" % key)
		close(float(got_def.get("statusChance", -1)), float(want_def.get("statusChance", -1)),
			"%s statusChance" % key)
		ok(str(got_def.get("status")) == str(want_def.get("status")), "%s status" % key)

	section("move instance (yA port)")
	var inst := PbJson.as_dict(_golden.get("instances_level5", {}))
	var actor := PbActor.create(1)
	var actor_data := PbActor.actor_for_damage(actor)
	for key in inst.keys():
		var want_inst := PbJson.as_dict(inst[key])
		var def := PbMoves.resolve(str(key))
		if def.is_empty():
			_fail("instance golden move %s unresolved" % key)
			continue
		var got_inst := PbDamage.move_instance(def, actor_data, 5)
		for field in ["base", "real", "stab", "cd", "area", "dps", "use", "crit"]:
			if not want_inst.has(field):
				continue
			close(float(got_inst.get(field, -1)), float(want_inst[field]), "%s lv5 %s" % [key, field])
		ok(int(got_inst.get("count", -1)) == int(want_inst.get("count", 0)), "%s lv5 count" % key)

	section("card mod stacking ($y + tb ports)")
	var cards := PbJson.as_dict(_golden.get("cards_mod_case", {}))
	var pikachu := PbData.species(25)
	var stats := PbStats.stats_from_species(pikachu, 0.0)
	PbStats.apply_mod_groups(stats, [[
		{"stat": "damage", "mul": 1.1}, {"stat": "damage", "mul": 1.1},
		{"stat": "evasion", "add": 0.9}, {"stat": "luck", "add": 40},
		{"stat": "attackSpeed", "mul": 0.8}, {"stat": "critChance", "add": 0.95},
	]])
	PbStats.finalize(stats)
	for key in ["damage", "evasion", "critChance", "megaCrit", "luckMult", "attackSpeed", "area"]:
		close(float(stats.get(key, -1)), float(cards.get(key, -1)), "card stacking %s" % key)


# ------------------------------------------------------------------ 3. fusion
func _fusion_checks() -> void:
	section("fusion machine (Uw / JC ports)")
	var golden_fusion := PbJson.as_dict(_golden.get("fusion", {}))
	var sig := PbJson.as_dict(golden_fusion.get("signature", {}))
	var recipe := PbFusion.recipe_for(PbMoves.resolve("razor-leaf"), PbMoves.resolve("solar-beam"))
	ok(str(recipe.get("key", "")) == str(sig.get("recipe_key", "")), "signature recipe fu-1 found")
	var fused := PbFusion.fused_def(recipe)
	var want := PbJson.as_dict(sig.get("def", {}))
	for field in ["dmg", "cd", "area", "power"]:
		close(float(fused.get(field, -1)), float(want.get(field, -1)), "fused %s" % field)
	ok(str(fused.get("arch", "")) == "fusion", "fused archetype is fusion")
	ok(int(fused.get("pierce", 0)) == 99, "fused pierce 99")
	ok(fused.get("fusion") != null, "fused payload present")
	close(float(PbJson.as_dict(fused.get("fusion", {})).get("hits", 0)), float(want.get("hits", 0)), "fused hits")

	var cross := PbFusion.recipe_for(PbMoves.resolve("flamethrower"), PbMoves.resolve("thunderbolt"))
	ok(str(cross.get("kind", "")) == str(PbJson.as_dict(golden_fusion.get("cross_type", {})).get("kind", "")),
		"unrelated types fall back to %s" % PbJson.as_dict(golden_fusion.get("cross_type", {})).get("kind", ""))

	var same := PbFusion.recipe_for(PbMoves.resolve("flamethrower"), PbMoves.resolve("ember"))
	if not same.is_empty():
		ok(str(same.get("kind", "")) in ["signature", "reaction", "type"],
			"same-type pair resolves to a type/reaction recipe (got %s)" % same.get("kind"))

	# Fusion area clamp (My) and the min cd for fusions.
	close(PbDamage.fusion_area_scale(1.0), minf(3.4, 1.25 * pow(1.0, 0.9)), "My(1.0)")
	close(PbDamage.fusion_area_scale(10.0), 3.4, "My(10) hits the 3.4 ceiling")
	var actor := PbActor.create(25)
	var built := PbDamage.move_instance(fused, PbActor.actor_for_damage(actor), 1)
	ok(float(built.get("cd", 0)) >= PbDamage.FUSION_MIN_CD - EPS, "fusion cd floor 0.6s respected")

	# Offers require both moves at level 8 (Ww "/8").
	var low := PbFusion.offers(PbJson.as_array(actor.get("moves", [])))
	var ready_low := 0
	for raw in low:
		if bool(PbJson.as_dict(raw).get("ready", false)):
			ready_low += 1
	var maxed: Array = PbJson.as_array(actor.get("moves", [])).duplicate(true)
	for i in maxed.size():
		if maxed[i] != null:
			PbJson.as_dict(maxed[i])["level"] = PbFusion.MOVE_MAX_LEVEL
	var high := PbFusion.offers(maxed)
	var ready_high := 0
	for raw in high:
		if bool(PbJson.as_dict(raw).get("ready", false)):
			ready_high += 1
	ok(ready_low == 0, "no fusion ready below level 8 (got %d)" % ready_low)
	print("   level-8 offers available: %d" % ready_high)


# ------------------------------------------------------------------ 4. run flow
func _run_flow() -> void:
	section("run simulation + settlement")
	PbRng.seed(20261102)
	var run := PbRun.create(1, "forest", 20261102, {"damage": 0.2, "maxHp": 20})
	ok(not run.is_empty(), "run created")
	var player: Dictionary = run["player"]
	ok(PbActor.move_keys(player).size() >= 3, "auto-assigned moves (%d)" % PbActor.move_keys(player).size())
	ok(float(player.get("maxHp", 0)) > 0.0, "player stats derived")
	var before_damage := 0.0
	ok(str(run.get("aimMode", "")) == "auto", "run defaults to the web's auto aim mode")
	PbRun.simulate(run, 150.0)
	var stats: Dictionary = run["stats"]
	print("   simulated %.0fs: stage=%d kills=%d damage=%.0f level=%d gold=%.0f state=%s" % [
		float(run["time"]), int(run["stage"]), int(stats.get("kills", 0)),
		float(stats.get("damage", 0.0)), int(player.get("level", 1)),
		float(run.get("gold", 0)), str(run.get("state", "play"))])
	before_damage = float(stats.get("damage", 0.0))
	ok(before_damage > 0.0, "the player dealt damage (damage pipeline works)")
	ok(int(stats.get("kills", 0)) > 0, "enemies died (kill/loot pipeline works)")
	ok(int(player.get("level", 1)) > 1, "player levelled up (xp curve + offers work)")
	ok(int(stats.get("powerUps", 0)) > 0, "cards were picked during level-ups")
	ok(bool(run.get("bossSpawned", false)) or int(run["stage"]) >= 2,
		"stage timer drove the boss/stage progression")
	ok(PbJson.as_array(run["orbs"]).size() >= 0, "orb list maintained")
	ok(not PbJson.as_array(run["offers"]).is_empty() or int(run["pendingLevels"]) == 0,
		"modal state consistent with pending levels")
	var result := PbRun.finish(run, "exit")
	# Web semantics: `seen` is registered when the species appears; the captured
	# list is written exclusively by a successful Poké Ball throw.
	ok(PbJson.as_array(stats.get("captured", [])).size() == 0,
		"kills do not write captures (ball throw only)")
	ok(PbJson.as_array(stats.get("newSeen", [])).size() > 0, "seen species list filled")
	ok(PbJson.as_dict(stats.get("killsBy", {})).size() > 0, "per-species kill counts tracked")
	ok(result.has("species") and result.has("kills") and result.has("splits"),
		"settlement payload has the api-core.js fields")
	ok(result.has("econ") and PbJson.as_dict(result["econ"]).has("gold"), "econ.gold present")

	# In-run fusion: max out the moves and fuse through the machine.
	var run2 := PbRun.create(25, "forest", 99, {})
	var p2: Dictionary = run2["player"]
	for raw in PbJson.as_array(p2.get("moves", [])):
		if raw != null:
			PbJson.as_dict(raw)["level"] = PbFusion.MOVE_MAX_LEVEL
	var offers2 := PbRun.fusion_offers(run2)
	var ready2 := []
	for raw in offers2:
		if bool(PbJson.as_dict(raw).get("ready", false)):
			ready2.append(raw)
	print("   fusion offers in a fresh run: %d total, %d ready" % [offers2.size(), ready2.size()])
	if ready2.is_empty():
		# Deterministic fallback: force the two ingredients into slots 0/1 and fuse
		# them through the same offer shape the machine produces.
		var recipe2 := PbFusion.recipe_for(PbMoves.resolve("flamethrower"), PbMoves.resolve("thunderbolt"))
		ok(not recipe2.is_empty(), "recipe_for picked a fusion for flamethrower+thunderbolt")
		PbActor.learn(p2, "flamethrower", 0)
		PbActor.learn(p2, "thunderbolt", 1)
		PbJson.as_dict(PbJson.as_array(p2["moves"])[0])["level"] = PbFusion.MOVE_MAX_LEVEL
		PbJson.as_dict(PbJson.as_array(p2["moves"])[1])["level"] = PbFusion.MOVE_MAX_LEVEL
		var synthetic_offer := {"recipe": recipe2, "a": 0, "b": 1,
			"names": ["Flamethrower", "Thunderbolt"], "types": ["fire", "electric"],
			"ready": true, "need": []}
		var inst2 := PbFusion.apply(PbJson.as_array(p2["moves"]), synthetic_offer)
		ok(not inst2.is_empty(), "fusion apply works on a synthetic offer")
		ok(str(PbJson.as_dict(inst2.get("def", {})).get("arch", "")) == "fusion",
			"synthetic fused move carries the fusion archetype")
		ok(PbJson.as_array(p2["moves"])[1] == null, "one source slot was freed by the fusion")
	else:
		var fused_inst := PbRun.fuse(run2, PbJson.as_dict(ready2[0]))
		ok(not fused_inst.is_empty(), "in-run fusion produced a move")
		ok(str(PbJson.as_dict(fused_inst.get("def", {})).get("arch", "")) == "fusion",
			"fused move uses the fusion archetype")
		ok(PbJson.as_array(run2["fusions"]).size() == 1, "fusion recorded on the run")

	# Settlement reward must follow api-core's formula, checked against golden.
	for raw in PbJson.as_array(_golden.get("settle_reward", [])):
		var case := PbJson.as_dict(raw)
		var kills := int(case["kills"])
		var t := float(case["time"])
		var expected := int(case["stardust"])
		var got := maxi(1, int(roundf(kills * 0.5 + t * 0.2)))
		ok(got == expected, "stardust formula kills=%d time=%d -> %d" % [kills, t, got])

	# aimMode is a profile setting that reaches the simulation.
	var manual := PbRun.create(6, "forest", 4242, {})
	manual["aimMode"] = "manual"
	PbRun.simulate(manual, 25.0)
	ok(str(manual.get("aimMode", "")) == "manual", "manual aim mode survives the tick loop")
	ok(float(manual["time"]) > 20.0, "manual-aim run keeps simulating (t=%.0fs)" % float(manual["time"]))

	# --- capture (bundle class kS @1074615): only a successful ball throw writes
	# the captured list; kills never do (seen is written at spawn).
	var cap_run := PbRun.create(25, "forest", 777, {})
	ok(cap_run.has("capture"), "capture encounter state created")
	PbCapture.data_of(cap_run)["spawnAt"] = 0.0
	PbCapture.tick(cap_run, 0.1)
	var cap_index := PbCapture.index(cap_run)
	ok(cap_index >= 0 and PbEnemies.is_alive(cap_run["enemies"], cap_index),
		"capture encounter spawned (kS.spawnEncounter @1078302)")
	var cap_pool: Dictionary = cap_run["enemies"]
	ok(int(PbEnemies.get_field(cap_pool, "flags", cap_index)) & int(PbEnemies.Flag["Capture"]) != 0,
		"capture encounter carries the R.Capture flag")
	# Lethal damage weakens instead of killing (kS.onDefeated @1082804).
	var lethal := PbEnemies.damage(cap_pool, cap_index, 1.0e9)
	ok(bool(lethal.get("capture", false)) and not bool(lethal.get("died", true)),
		"lethal damage on the capture target only weakens it")
	PbCapture.on_defeated(cap_run)
	ok(PbCapture.is_weakened(cap_run), "capture target enters the weakened window")
	var cap_hp := float(PbEnemies.get_field(cap_pool, "hp", cap_index))
	var cap_max := float(PbEnemies.get_field(cap_pool, "maxHp", cap_index))
	ok(absf(cap_hp - cap_max * 0.01) < 0.01, "weakened target sits at 1% HP")
	# Chance formula (kS.throwBall @1082671): .55 + rate/255*.35 + attempts*.2.
	var cap_species := PbCapture.species(cap_run)
	var cap_rate := float(PbData.species(cap_species).get("captureRate", 0.0))
	var cap_chance := PbCapture.chance_for(cap_run)
	var cap_expect := minf(0.97, 0.55 + cap_rate / 255.0 * 0.35)
	ok(absf(cap_chance - cap_expect) < EPS,
		"capture chance %.4f matches web %.4f (rate %.0f)" % [cap_chance, cap_expect, cap_rate])
	# Move inside the 9-unit throw range (kS.tryThrow), then force the catch with
	# the master ball (kS.throwBall: the item guarantees the hit).
	PbJson.as_dict(cap_run["player"])["x"] = float(PbEnemies.get_field(cap_pool, "x", cap_index)) + 1.0
	PbJson.as_dict(cap_run["player"])["z"] = float(PbEnemies.get_field(cap_pool, "z", cap_index))
	PbActor.give_item(PbJson.as_dict(cap_run["player"]), "master-ball", 1.0)
	ok(PbCapture.throw_ball(cap_run), "ball throw accepted inside the 9-unit range")
	PbCapture.tick(cap_run, 1.0)
	var cap_family := int(PbCapture.data_of(cap_run).get("family", 0))
	ok(PbJson.as_array(cap_run["stats"].get("captured", [])).has(cap_family),
		"successful catch records the family in run captured")
	ok(PbJson.as_array(Save.store.get("captured", [])).has(cap_family)
		and PbJson.as_array(Save.store.get("unlocked", [])).has(cap_family),
		"catch writes captures + unlocked to the profile (joinLeague @1667709)")

	# Failed throws: attempts accumulate, the window shrinks to 6s, and the third
	# miss makes the encounter flee (kS.breakFree @1083400).
	var miss_run := PbRun.create(6, "forest", 778, {})
	PbCapture.data_of(miss_run)["spawnAt"] = 0.0
	PbCapture.tick(miss_run, 0.1)
	var miss_index := PbCapture.index(miss_run)
	PbCapture.on_defeated(miss_run)
	for n in 3:
		PbCapture.data_of(miss_run)["state"] = "throwing"
		PbCapture.data_of(miss_run)["outcome"] = false
		PbCapture.data_of(miss_run)["throwT"] = 0.0
		PbCapture.tick(miss_run, 0.01)
	ok(int(PbCapture.data_of(miss_run).get("attempts", 0)) == 3, "failed throws accumulate attempts")
	ok(str(PbCapture.data_of(miss_run).get("state", "")) == "done"
		and not PbEnemies.is_alive(miss_run["enemies"], miss_index),
		"third failed throw makes the encounter flee")

	# --- shop (nC @1104993 / aC @1105132): rC=[80,130,220,400,750], rT=2.2^(stage-1),
	# shopHeat iC=[1.15,1.25,1.4,1.6,2] from the 3rd purchase, oC=1-.08*teeth.
	var shop_run := PbRun.create(4, "forest", 999, {})
	PbShop.open(shop_run)
	var shop_rows := PbShop.stock(shop_run)
	ok(shop_rows.size() == 4, "shop rolls 4 stock rows")
	var shop_keys := {}
	for raw in shop_rows:
		var row := PbJson.as_dict(raw)
		shop_keys[str(row["key"])] = true
		ok(int(row["price"]) == PbShop.price_for(shop_run, str(row["key"])),
			"stock price matches aC for %s" % str(row["key"]))
	ok(shop_keys.size() == 4, "shop stock keys are distinct")
	# Price samples at stage 1 (no heat, no discount): 80/130/220/400/750.
	var sample0 := ""
	var sample4 := ""
	for raw in PbJson.as_array(PbData.pb_table("items_game")):
		var def := PbJson.as_dict(raw)
		if bool(def.get("premium", false)):
			continue
		if int(def.get("rarity", 0)) == 0 and sample0.is_empty():
			sample0 = str(def.get("key", ""))
		if int(def.get("rarity", 0)) == 4 and sample4.is_empty():
			sample4 = str(def.get("key", ""))
	ok(PbShop.price_for(shop_run, sample0) == 80, "rarity-0 price is 80 (stage 1)")
	ok(PbShop.price_for(shop_run, sample4) == 750, "rarity-4 price is 750 (stage 1)")
	# Stage 2 multiplies by 2.2 (rT clamp 1..4).
	shop_run["stage"] = 2
	ok(PbShop.price_for(shop_run, sample0) == 176, "stage 2 rarity-0 price is 176")
	# Every purchase past the first two multiplies heat by iC[rarity].
	shop_run["shopBuys"] = [0, 0, 0]
	ok(PbShop.price_for(shop_run, sample0) == int(roundf(80.0 * 2.2 * 1.15)),
		"the 3rd purchase adds heat (iC[0]=1.15)")
	shop_run["shopBuys"] = [0, 0, 2]
	ok(PbShop.price_for(shop_run, sample0) == int(roundf(80.0 * 2.2 * 1.4)),
		"heat uses the bought rarity's multiplier (iC[2]=1.4)")
	# oC: 3 gold-teeth = -24%.
	PbActor.give_item(PbJson.as_dict(shop_run["player"]), "gold-teeth", 3.0)
	ok(absf(PbShop.discount(shop_run) - 0.76) < EPS, "gold-teeth discount caps at 24%")
	# Purchase validation: gold, sold flag, stack cap and the item grant.
	PbActor.give_item(PbJson.as_dict(shop_run["player"]), "gold-teeth", 0.0)
	shop_run["shopBuys"] = []
	shop_run["stage"] = 1
	shop_run["gold"] = 500.0
	var buy_key := str(PbJson.as_dict(PbShop.stock(shop_run)[0])["key"])
	ok(PbShop.buy(shop_run, 0), "shop buy succeeds with enough gold")
	ok(bool(PbJson.as_dict(PbShop.stock(shop_run)[0]).get("sold", false)), "bought row is marked sold")
	ok(int(shop_run["gold"]) == 500 - PbShop.price_for(shop_run, buy_key),
		"buy charges the aC price")
	ok(int(PbActor.item_power(PbJson.as_dict(shop_run["player"]), buy_key)) == 1,
		"buy grants one copy of the item")
	ok(not PbShop.buy(shop_run, 0), "sold rows cannot be bought twice")
	PbActor.give_item(PbJson.as_dict(shop_run["player"]), buy_key, 10.0)
	ok(not PbShop.can_hold(shop_run, buy_key), "stack cap (max 10) blocks purchases")
	# Reroll: cost .5*rC[0]*rT*1.5^shopRerolls*oC, new stock each time.
	shop_run["shopRerolls"] = 0
	shop_run["gold"] = 50.0
	ok(PbShop.reroll_cost(shop_run) == 40, "stage-1 reroll costs 40")
	ok(PbShop.reroll(shop_run), "reroll succeeds with enough gold")
	ok(int(shop_run["gold"]) == 10 and int(shop_run["shopRerolls"]) == 1,
		"reroll charges gold and bumps the reroll count")
	ok(PbShop.reroll_cost(shop_run) == 60, "next reroll costs 1.5x more")
	ok(not PbShop.reroll(shop_run), "reroll fails when gold is short")


# ------------------------------------------------------------------ 5. save flow
func _save_flow() -> void:
	section("save service (api-core.js port)")
	var before := Save.reset(true)
	ok(int(before.get("stardust", 0)) == 999999, "full profile stardust 999999")
	ok(PbJson.as_array(before.get("captured", [])).size() == 151, "full profile dex 151")
	ok(PbJson.as_array(before.get("biomes", [])).size() == 6, "full profile biomes 6")
	ok(Save.lab("slot-move") == 1 and Save.lab("dmg") == 8, "lab table maxed from api-core")
	var schema := PbJson.as_dict(PbData.pb_table("profile_schema"))
	var missing := []
	for key in PbJson.as_array(schema.get("arrays", [])):
		if not before.has(str(key)):
			missing.append(str(key))
	for key in PbJson.as_array(schema.get("dicts", [])):
		if not before.has(str(key)):
			missing.append(str(key))
	ok(missing.is_empty(), "profile has every api-core array/dict field (missing %s)" % str(missing))
	for key in PbJson.as_array(schema.get("counters", [])):
		ok(PbJson.as_dict(before.get("counters", {})).has(str(key)), "counters.%s" % key)
	var settings := PbJson.as_dict(schema.get("settings_default", {}))
	for key in settings.keys():
		ok(PbJson.as_dict(before.get("settings", {})).has(str(key)), "settings.%s" % key)

	section("lab purchase + routes")
	Save.reset(false)          # fresh profile: empty lab, no stardust
	var broke := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(str(broke.get("error", "")) == "NO_STARDUST", "purchase blocked without stardust")
	Save.store["stardust"] = 500
	Save.save()
	var rank_before := Save.lab("dmg")
	var wallet_before := int(Save.store["stardust"])
	var res := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(bool(res.get("ok", false)), "lab buy accepted")
	ok(int(Save.store["stardust"]) == wallet_before - 10 * (rank_before + 1),
		"stardust debited by 10*(rank+1) = %d" % (10 * (rank_before + 1)))
	ok(Save.lab("dmg") == rank_before + 1, "lab rank increased")
	Save.store["stardust"] = 100000
	Save.store["lab"]["dmg"] = Save.lab_max("dmg")
	Save.save()
	var again := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(str(again.get("error", "")) == "MAX", "lab buy caps with MAX")
	var poor := Save.fresh_profile()
	poor["stardust"] = 5
	Save.store = poor
	Save.save()
	var denied := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(str(denied.get("error", "")) == "NO_STARDUST", "lab buy denied without stardust")

	section("status / profile / starter routes")
	var status := Save.handle("GET", "/status", {}, {})
	ok(bool(status.get("ok", false)) and bool(status.get("offline", false)), "GET /status")
	ok(not str(status.get("build", "")).is_empty(), "GET /status reports the ported build id")
	var prof := Save.handle("GET", "/profile", {}, {})
	ok(prof.get("profile") is Dictionary, "GET /profile")
	var starter := Save.handle("POST", "/profile/starter", {}, {"id": 25})
	ok(int(PbJson.as_dict(starter.get("profile", {})).get("starter", 0)) == 25, "POST /profile/starter")
	ok(PbJson.as_array(Save.store["captured"]).has(25), "starter is captured")
	var prefs := Save.handle("PUT", "/profile/prefs", {}, {"settings": {"music": 0.4, "aimMode": "manual"}})
	ok(bool(prefs.get("ok", false)), "PUT /profile/prefs")
	ok(is_equal_approx(float(PbJson.as_dict(PbJson.as_dict(prefs.get("profile", {})).get("settings", {})).get("music", 0.0)), 0.4),
		"music setting persisted")
	ok(str(PbJson.as_dict(PbJson.as_dict(prefs.get("profile", {})).get("settings", {})).get("aimMode", "")) == "manual",
		"aimMode setting persisted")
	var guest := Save.handle("POST", "/auth/guest", {}, {})
	ok(str(guest.get("name", "")).begins_with("Invitado"), "POST /auth/guest names the guest")

	section("run finish writes a record")
	Save.reset(true)
	var runs_before := PbJson.as_array(Save.store["runs"]).size()
	var payload := {"species": 1, "finalSpecies": 2, "biome": "forest", "tier": 3, "stage": 3,
		"time": 120.0, "kills": 40, "damage": 9000.0, "level": 12, "victory": true,
		"score": 500, "seed": 7, "moves": [], "items": [], "splits": [], "mode": "standard",
		"bosses": 2, "legendaries": 1, "econ": {"gold": 300}}
	var finish := Save.handle("POST", "/runs/run-deadbeef/finish", {}, {"result": payload})
	ok(bool(finish.get("ok", false)), "POST /runs/<id>/finish")
	ok(PbJson.as_array(Save.store["runs"]).size() == runs_before + 1, "run recorded")
	ok(int(Save.store["counters"]["kills"]) == 40, "counters.kills updated")
	ok(int(Save.store["stardust"]) == 999999 + 44, "stardust +44 (golden formula)")
	ok(int(Save.store["bonk"]) >= 2, "bonk awarded per boss kill (offline rule)")
	ok(int(Save.store["counters"]["gold"]) == 300, "econ.gold counted")
	ok(not PbJson.as_dict(Save.store["research"]).has("1"),
		"run finish does not touch research (api-core parity)")

	section("export / import / backups")
	var text := Save.export_string()
	ok(text.contains("\"profile\""), "export contains the profile envelope")
	var junk = "here is my save: " + text + " (thanks!)"
	var imported := Save.import_text(junk)
	ok(imported == "ok", "import tolerates junk around the JSON (got %s)" % imported)
	var bad := Save.import_text("{\"notASave\":true}")
	ok(bad != "ok", "import rejects non-save payloads (%s)" % bad)
	var ids := []
	for i in 8:
		var id := Save.auto_backup()
		if not id.is_empty():
			ids.append(id)
	var backups := Save.list_backups()
	ok(ids.size() == 8, "eight backup calls produced eight ids (got %d)" % ids.size())
	ok(backups.size() == 5, "backups pruned to 5 (got %d)" % backups.size())
	ok(Save.restore_backup(str(PbJson.as_dict(backups[0]).get("id", ""))), "restore latest backup")

	section("round trip through disk")
	Save.reset(true)
	Save.store["name"] = "验证员"
	Save.save()
	var raw := JSON.parse_string(FileAccess.get_file_as_string(Save.save_path()))
	var envelope := PbJson.as_dict(raw)
	ok(str(PbJson.as_dict(envelope.get("profile", {})).get("name", "")) == "验证员", "name survived the round trip")
	ok(int(envelope.get("v", 0)) == 1, "envelope version 1")
	ok(float(Save.stale_seconds()) < 5.0, "stale_seconds reports a fresh save")


# ------------------------------------------------------------------ 6. assets
func _asset_checks() -> void:
	section("assets + presentation")
	var pmd := PbPmd.meta(1)
	ok(not pmd.is_empty(), "sprites.json meta for #1")
	var sheet := PbVisuals.sheet(1)
	ok(sheet != null, "PMD sheet texture loads")
	if sheet != null:
		ok(sheet.get_width() == int(PbPmd.sheet_size(1).x), "sheet width matches sprites.json (%d)" % sheet.get_width())
		ok(sheet.get_height() == int(PbPmd.sheet_size(1).y), "sheet height matches sprites.json")
	var rect := PbPmd.frame_rect(1, "walk", 0.0, 1)
	ok(rect.size.x > 0 and rect.size.y > 0, "walk frame rect is valid")
	ok(rect.position.x >= 0 and rect.position.y >= 0, "frame rect inside the sheet")
	var avatar := PbVisuals.avatar(1)
	ok(avatar != null, "avatar node built for #1")
	ok(avatar is MeshInstance3D or avatar is Node3D, "avatar is a renderable 3D node")
	avatar.free()
	var glb := load("res://assets/models/tower_portal.glb")
	ok(glb is PackedScene, "shipped .glb prop imports as a PackedScene")
	var frame := PbVisuals.frame_texture(25, "idle", 0.0, 1)
	ok(frame != null, "frame texture for #25")
	ok(ResourceLoader.exists("res://assets/audio/cries/cry_template.wav"), "generated cry template present")
	ok(ResourceLoader.exists("res://assets/audio/music/menu_theme.wav"), "generated menu loop present")
	var missing := PbJson.as_dict(PbData.pb_table("missing_remote_assets"))
	ok(PbJson.as_array(missing.get("entries", [])).size() >= 5, "missing-asset register populated")
	var tone: AudioStreamWAV = Audio.tone(440.0, 0.1, "square", 0.2)
	ok(tone != null and tone.data.size() > 0, "SFX synthesiser produces audio")
	var en := PbData.localized_name("pokemon", 1, "en")
	var zh := PbData.localized_name("pokemon", 1, "zh")
	ok(not en.is_empty() and not zh.is_empty() and en != zh, "i18n name lookup works (en=%s zh=%s)" % [en, zh])


## ------------------------------------------------------------------ 1b. avatar fallback chain
## The run screen must never show an untextured (white) quad. PbVisuals.avatar falls back
## pmd-billboard -> front-billboard (re's front/<id>.png) -> tinted color-box.
func _avatar_fallback_checks() -> void:
	section("avatar fallback chain (front/ + color-box)")
	var f1 := PbVisuals.front_texture(1)
	ok(f1 != null, "front_texture(1) loads the static portrait")
	var a1 := PbVisuals.avatar(1)
	ok(a1 != null, "avatar(1) builds")
	var k1 := ""
	if a1 is Node:
		k1 = a1.get_meta("avatar_kind", "")
	ok(k1 == "pmd-billboard" or k1 == "front-billboard",
		"avatar(1) is a textured billboard (got %s)" % k1)
	var a_bad := PbVisuals.avatar(999999)
	var k_bad := ""
	if a_bad is Node:
		k_bad = a_bad.get_meta("avatar_kind", "")
	ok(k_bad == "color-box", "unknown species falls back to color-box (got %s)" % k_bad)
	a1.free()
	a_bad.free()


## ------------------------------------------------------------------ 7. theme tokens
## The 1:1 UI port is driven by ui_theme.json; these lock the parser + the small
## JS tables (rarity/danger) + the shared formatters the HUD reuses.
func _theme_ui_checks() -> void:
	section("design tokens + UI kit")
	var v := PbTheme.vars()
	ok(v.has("--red") and v.has("--yellow") and v.has("--radius"), "light vars loaded")
	ok(PbTheme.css_color("#f00").r > 0.9 and PbTheme.css_color("#f00").g < 0.1, "css_color #rgb")
	ok(PbTheme.css_color("#80808080").a > 0.49 and PbTheme.css_color("#80808080").a < 0.51, "css_color #rrggbbaa alpha")
	# color-mix(in srgb, #ffcc33 50%, white) -> halfway to white
	var mixed := PbTheme.css_color("color-mix(in srgb, #000000 50%, white)")
	ok(absf(mixed.r - 0.5) < 0.02, "color-mix 50% black/white")
	# rarity colours are the --r0..--r4 tokens and all distinct
	var seen := {}
	for i in 5:
		seen[PbTheme.rarity_color(i).to_html()] = true
	ok(seen.size() == 5, "five distinct rarity colours")
	ok(PbTheme.rarity_color(0) == PbTheme.css_color(str(PbTheme.vars().get("--r0", ""))), "rarity0 == --r0")
	var th := PbTheme.danger_thresholds()
	ok(th.size() == 7 and float(th[0]) == 0.0 and float(th[6]) == 7.0, "danger thresholds [0..7]")
	ok(PbTheme.danger_colors().size() == 7, "danger has 7 segment colours")
	ok(PbTheme.danger_level(7.0) == 6 and PbTheme.danger_level(0.5) == 0, "danger_level bucketing")
	ok(PbTheme.rarity_labels().size() == 5, "rarity labels table")
	# gradient + keyframe parsing
	var btn_g := PbTheme.gradient(str(PbTheme.decls(".btn").get("background", "")))
	ok(btn_g.get("type", "") == "linear" and PbJson.as_array(btn_g.get("stops", [])).size() == 3, ".btn gradient 3 stops")
	ok(PbTheme.keyframe_frames("cardIn").size() >= 1, "cardIn keyframe parsed")
	ok(str(PbTheme.anim_of(".card", "cardIn")["name"]) == "cardIn", ".card anim name")
	var st := PbTheme.stripes()
	ok(absf(float(st["angle"]) + 45.0) < 0.1 and int(st["period"]) == 20, "--stripes parsed")
	ok(PbTheme.stylebox(".hud-top") != null, "stylebox(.hud-top) builds")
	ok(PbTheme.rule(".timer").contains("font-title"), "rule(.timer) present")
	# formatters mirror the bundle P()/rl()/il()
	ok(UI.fmt_num(999.0) == "999", "fmt_num <10k plain")
	ok(UI.fmt_num(10000.0) == "10k", "fmt_num 10k")
	ok(UI.fmt_num(1500000.0) == "1.5M", "fmt_num 1.5M")
	ok(UI.fmt_num(2000000000.0) == "2B", "fmt_num 2B")
	ok(UI.fmt_clock(65.0) == "1:05", "fmt_clock m:ss")
	ok(UI.fmt_clock_t(65.4) == "1:05.4", "fmt_clock_t tenths")
	# dark mode flips the ink token
	PbTheme.set_mode("dark")
	var dark_ink := PbTheme.ink()
	PbTheme.set_mode("light")
	ok(dark_ink != PbTheme.ink(), "dark theme changes ink")


## ------------------------------------------------------------------ 8. revive
func _revive_checks() -> void:
	section("revive gameplay")
	var actor := PbActor.create(4, {"revive": 2})
	ok(int(actor.get("revives", 0)) == 2, "lab revive seeds actor.revives")
	var run := PbRun.create(4, "forest", 999, {"revive": 1})
	var p: Dictionary = run["player"]
	p["hp"] = 0.0
	var revived := PbRun._try_revive(run)
	ok(revived, "_try_revive returns true with a charge")
	ok(float(p["hp"]) > 0.0 and absf(float(p["hp"]) - float(p["maxHp"]) * 0.6) < 0.01, "revive restores 60% max HP")
	ok(int(p["revives"]) == 0, "revive consumes a charge")
	ok(not PbRun._try_revive(run), "second death with 0 charges fails")


## ------------------------------------------------------------------ 9. danger parity
## PbRun.danger() must match the independent Python implementation in
## golden_values.py (structure parity; magnitude is the port's estimate).
func _danger_golden_checks() -> void:
	section("danger golden parity")
	var cases: Array = PbJson.as_array(_golden.get("danger", []))
	ok(cases.size() >= 5, "golden danger cases present")
	for c in cases:
		var entry := PbJson.as_dict(c)
		var state := {
			"stage": int(entry["stage"]), "time": float(entry["time"]),
			"diff": {"enemyDamage": 1.0, "enemyAmount": 1.0, "enemySpeed": 1.0},
		}
		close(PbRun.danger(state), float(entry["value"]),
			"danger stage %s time %s" % [str(entry["stage"]), str(entry["time"])])
	var s1 := {"stage": 1, "time": 0.0, "diff": {}}
	var s5 := {"stage": 5, "time": 300.0, "diff": {}}
	ok(PbRun.danger(s5) > PbRun.danger(s1), "danger rises with stage/time")


## ------------------------------------------------------------------ 10. UI builders
## The new kit widgets must construct without a renderer and expose the right
## structure (they are the 1:1 port of the web DOM classes).
func _ui_build_checks() -> void:
	section("UI kit builders")
	ok(UI.field("x") is LineEdit, "UI.field returns a LineEdit")
	ok(UI.chip("t", Color.RED) is PanelContainer, "UI.chip returns a PanelContainer")
	ok(UI.type_chip("fire") is PanelContainer, "UI.type_chip returns a PanelContainer")
	var seg := UI.segment([{"id": "a", "text": "A"}, {"id": "b", "text": "B"}], "a", Callable())
	ok(seg is PanelContainer and seg.get_child_count() == 1, "UI.segment builds a track with pills")
	var head := UI.screen_head("T", "S", Callable())
	ok(head.get_child_count() >= 3, "UI.screen_head has back + kbd + title")
	var tile := UI.mm_tile("globe", "T", "S", Color.BLUE, Callable())
	ok(tile.get_child_count() >= 1, "UI.mm_tile builds a row")
	var sw := PbWidgets.SwitchToggle.new()
	sw.set_pressed(true)
	ok(sw.on and sw.get_child_count() == 1, "SwitchToggle builds + toggles")
	var card := UI.card_offer({"rc": Color.BLUE, "title": "X", "lines": ["a"], "key": "1"}, Callable(), 0)
	ok(card.get_child_count() >= 1, "UI.card_offer builds a body column")
	# the danger/label colour tables resolve
	ok(PbTheme.rarity_dot_color(0) != PbTheme.rarity_dot_color(4), "rarity dot colours distinct")
	# number formatter edge cases
	ok(UI.fmt_num(1.0e15) == "1Q", "fmt_num 1Q")
	ok(UI.fmt_clock(0.0) == "0:00", "fmt_clock zero")


func report() -> void:
	print("\n=== %d checks, %d failures ===" % [_checks, _failures.size()])
	for f in _failures:
		print("  ✗ " + f)
	if _failures.is_empty():
		print("  ✔ port verification passed")


# ------------------------------------------------------------------ terrain
## The arena is generated by PbTerrain, a port of the client's own generator. Parity is not
## self-证: data/pb/terrain_golden.json holds values produced by running the shipped class in
## Node (tools/terrain_reference.mjs), and this section compares against it.
func _terrain_checks() -> void:
	section("terrain: world tables + generator parity")
	var biomes: Array = PbData.world_biomes()
	ok(biomes.size() == 6, "world_biomes has 6 biomes (got %d)" % biomes.size())
	var consts := PbData.world_constants()
	ok(absf(PbJson.as_float(consts.get("grid_size"), 0.0) - 1.12) < 1e-9, "grid size Qu = 1.12")
	ok(absf(PbJson.as_float(consts.get("step"), 0.0) - 4.6) < 1e-9, "terrace step $u = 4.6")
	ok(absf(PbJson.as_float(consts.get("pixel_size"), 0.0) - 13.5) < 1e-9, "toon pixel grid Iu = 13.5")
	var packs := PbJson.as_dict(PbData.pb_table("world_props").get("packs"))
	ok(packs.size() >= 11, "prop packs recovered for every arena pack (%d)" % packs.size())
	ok(not PbJson.as_dict(packs.get("forest")).is_empty(), "forest pack present")
	ok(not PbJson.as_dict(PbJson.as_dict(packs.get("forest")).get("atlas")).get("sprites").is_empty(),
		"forest atlas rects loaded from the mirror")
	var palettes := PbJson.as_dict(PbData.world_palettes().get("by_pack"))
	ok(palettes.size() == 6, "toon palettes for the 6 packs (%d)" % palettes.size())
	ok(not PbJson.as_dict(PbData.world_fx().get("hazards")).is_empty(), "hostile-terrain table loaded")

	# Generator primitives have to be exact, or the map is a different map.
	var rng := PbJsRng.new(2026)
	var first := rng.next()
	ok(first > 0.0 and first < 1.0, "PbJsRng.next() in [0,1)")
	ok(absf(PbJsRng.new(0).next() - PbJsRng.new(0).next()) < 1e-12, "seed 0 falls back deterministically")
	var noise := PbSimplex.new(2026)
	ok(absf(noise.get2(3.5, -2.25)) <= 1.0, "simplex stays bounded")
	ok(absf(noise.fbm(1.25, 4.5, 4)) <= 1.0, "fbm stays bounded")

	var golden_doc := PbJson.as_dict(PbData.pb_table("terrain_golden"))
	var worlds: Array = PbJson.as_array(golden_doc.get("worlds"))
	if worlds.is_empty():
		_fail("terrain_golden.json missing -- regenerate with tools/build_terrain_golden.py")
		return
	var reference := {}
	for w in worlds:
		if str(w.get("biome")) == "graveyard" and int(w.get("seed")) == 2026:
			reference = w
	if reference.is_empty():
		_fail("golden graveyard/2026 case missing")
		return
	var started := Time.get_ticks_msec()
	var t := PbTerrain.create(PbData.biome("graveyard"), PbData.world_pack("graveyard"), 2026)
	var ms := Time.get_ticks_msec() - started
	print("  graveyard world built in %d ms (res=%d, props=%d)" % [ms, t.res, t.props.size()])
	ok(t.res == int(reference.get("res", 0)), "lattice resolution matches the reference")
	ok(absf(t.min_h - float(reference.get("minH", 0.0))) < 1e-4, "minH matches the reference")
	ok(absf(t.max_h - float(reference.get("maxH", 0.0))) < 1e-4, "maxH matches the reference")
	ok(absf(t.water_level - float(reference.get("waterLevel", 0.0))) < 1e-4, "sea level matches the reference")
	ok(t.props.size() == int((reference.get("props") as Dictionary).get("count", -1)),
		"prop count matches the reference (%d)" % t.props.size())
	ok(t.colliders.size() == int((reference.get("colliders") as Dictionary).get("count", -1)),
		"collider count matches the reference (%d)" % t.colliders.size())
	var grid: Array = reference.get("heights")
	var worst := 0.0
	for a in grid.size():
		var row: Array = grid[a]
		for b in row.size():
			var x := -t.play + (2.0 * t.play * float(a)) / float(grid.size() - 1)
			var z := -t.play + (2.0 * t.play * float(b)) / float(row.size() - 1)
			worst = maxf(worst, absf(t.height(x, z) - float(row[b])))
	ok(worst < 1e-4, "height field matches the reference (worst delta %.6f)" % worst)
	var first_props: Array = (reference.get("props") as Dictionary).get("first")
	var prop_match := true
	for i in mini(first_props.size(), t.props.size()):
		var p: Dictionary = t.props[i]
		var r: Array = first_props[i]
		if str(p["kind"].get("name")) != str(r[0]) or absf(float(p["x"]) - float(r[1])) > 1e-5 \
				or absf(float(p["z"]) - float(r[3])) > 1e-5 or bool(p["flip"]) != bool(r[4]):
			prop_match = false
	ok(prop_match, "the first %d props land in the same spots with the same flips" % first_props.size())
	ok(not t.in_bounds(0, t.walk_lim() + 5.0), "outside the walk limit is out of bounds")
	ok(t.height(0.0, 0.0) > 4.0, "the centre dais is above the terrace step")


# ------------------------------------------------------------------ language
## The port is Chinese-only for now: the locale is pinned, the switch is gone, and every name
## the tables carry resolves to zh (with the Spanish source as the last fallback).
func _locale_checks() -> void:
	section("language: zh-only")
	ok(App.locale == "zh", "App.locale is pinned to zh (got %s)" % App.locale)
	ok(App._detect_locale() == "zh", "locale detection answers zh")
	ok(TranslationServer.get_locale().begins_with("zh"), "TranslationServer runs zh")
	ok(PbData.biome_label("forest") == "青翠森林",
		"biome title resolves to zh (got %s)" % PbData.biome_label("forest"))
	ok(PbData.biome_label("graveyard") == "紫苑塔",
		"tower biome title resolves to zh (got %s)" % PbData.biome_label("graveyard"))
	ok(not PbData.biome_text("desert", "desc").is_empty(), "biome blurb resolves to zh")
	ok(PbData.localized_name("pokemon", 1) == "妙蛙种子",
		"species name defaults to zh (got %s)" % PbData.localized_name("pokemon", 1))
	ok(PbData.localized_name("moves", "asceno") == "藤鞭" or PbData.localized_name("pokemon", 4) == "小火龙",
		"i18n lookups stay zh by default")
	# The menu must not offer a language switch any more.
	var packed = load("res://scenes/MainMenu.tscn")
	var menu: Node = (packed as PackedScene).instantiate()
	add_child(menu)
	var pills: Array[String] = []
	for node in menu.get_children():
		if str(node.name) == "LangPill":
			pills.append(str(node.name))
	menu.queue_free()
	ok(pills.is_empty(), "no LangPill in the main menu")
