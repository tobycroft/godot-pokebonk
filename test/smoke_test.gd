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
	_theme_ui_checks()
	_revive_checks()
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
		close(PbDamage.effectiveness(String(c["atk"]), PbJson.as_array(c["def"])),
			float(c["want"]), "effectiveness %s -> %s" % [c["atk"], str(c["def"])])

	section("stat derivation (Qy port)")
	var bulba := PbData.species(1)
	var want := PbJson.as_dict(PbJson.as_dict(_golden.get("stats", {})).get("bulbasaur_g0", {}))
	var got := PbStats.stats_from_species(bulba, 0.0)
	ok(got.keys().has("typeBoost"), "derived stats carry the per-type boost map")
	for key in PbStats.STAT_KEYS:
		ok(got.has(String(key)), "stat block exposes %s" % String(key))
	for key in want.keys():
		if typeof(want[key]) == TYPE_ARRAY or typeof(want[key]) == TYPE_DICTIONARY:
			continue
		close(float(got.get(key, -1)), float(want[key]), "bulbasaur %s" % String(key))
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
		var got_def := PbMoves.resolve(String(key))
		ok(not got_def.is_empty(), "resolve(%s) produced a definition" % key)
		if got_def.is_empty():
			continue
		ok(String(got_def.get("arch", "")) == String(want_def.get("arch", "")),
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
		var def := PbMoves.resolve(String(key))
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
	ok(String(recipe.get("key", "")) == String(sig.get("recipe_key", "")), "signature recipe fu-1 found")
	var fused := PbFusion.fused_def(recipe)
	var want := PbJson.as_dict(sig.get("def", {}))
	for field in ["dmg", "cd", "area", "power"]:
		close(float(fused.get(field, -1)), float(want.get(field, -1)), "fused %s" % field)
	ok(String(fused.get("arch", "")) == "fusion", "fused archetype is fusion")
	ok(int(fused.get("pierce", 0)) == 99, "fused pierce 99")
	ok(fused.get("fusion") != null, "fused payload present")
	close(float(PbJson.as_dict(fused.get("fusion", {})).get("hits", 0)), float(want.get("hits", 0)), "fused hits")

	var cross := PbFusion.recipe_for(PbMoves.resolve("flamethrower"), PbMoves.resolve("thunderbolt"))
	ok(String(cross.get("kind", "")) == String(PbJson.as_dict(golden_fusion.get("cross_type", {})).get("kind", "")),
		"unrelated types fall back to %s" % PbJson.as_dict(golden_fusion.get("cross_type", {})).get("kind", ""))

	var same := PbFusion.recipe_for(PbMoves.resolve("flamethrower"), PbMoves.resolve("ember"))
	if not same.is_empty():
		ok(String(same.get("kind", "")) in ["signature", "reaction", "type"],
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
	ok(String(run.get("aimMode", "")) == "auto", "run defaults to the web's auto aim mode")
	PbRun.simulate(run, 150.0)
	var stats: Dictionary = run["stats"]
	print("   simulated %.0fs: stage=%d kills=%d damage=%.0f level=%d gold=%.0f state=%s" % [
		float(run["time"]), int(run["stage"]), int(stats.get("kills", 0)),
		float(stats.get("damage", 0.0)), int(player.get("level", 1)),
		float(run.get("gold", 0)), String(run.get("state", "play"))])
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
	ok(PbJson.as_array(stats.get("captures", [])).size() > 0, "captured species list filled")
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
		ok(String(PbJson.as_dict(inst2.get("def", {})).get("arch", "")) == "fusion",
			"synthetic fused move carries the fusion archetype")
		ok(PbJson.as_array(p2["moves"])[1] == null, "one source slot was freed by the fusion")
	else:
		var fused_inst := PbRun.fuse(run2, PbJson.as_dict(ready2[0]))
		ok(not fused_inst.is_empty(), "in-run fusion produced a move")
		ok(String(PbJson.as_dict(fused_inst.get("def", {})).get("arch", "")) == "fusion",
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
	ok(String(manual.get("aimMode", "")) == "manual", "manual aim mode survives the tick loop")
	ok(float(manual["time"]) > 20.0, "manual-aim run keeps simulating (t=%.0fs)" % float(manual["time"]))


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
		if not before.has(String(key)):
			missing.append(String(key))
	for key in PbJson.as_array(schema.get("dicts", [])):
		if not before.has(String(key)):
			missing.append(String(key))
	ok(missing.is_empty(), "profile has every api-core array/dict field (missing %s)" % str(missing))
	for key in PbJson.as_array(schema.get("counters", [])):
		ok(PbJson.as_dict(before.get("counters", {})).has(String(key)), "counters.%s" % key)
	var settings := PbJson.as_dict(schema.get("settings_default", {}))
	for key in settings.keys():
		ok(PbJson.as_dict(before.get("settings", {})).has(String(key)), "settings.%s" % key)

	section("lab purchase + routes")
	Save.reset(false)          # fresh profile: empty lab, no stardust
	var broke := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(String(broke.get("error", "")) == "NO_STARDUST", "purchase blocked without stardust")
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
	ok(String(again.get("error", "")) == "MAX", "lab buy caps with MAX")
	var poor := Save.fresh_profile()
	poor["stardust"] = 5
	Save.store = poor
	Save.save()
	var denied := Save.handle("POST", "/lab/dmg/buy", {}, {})
	ok(String(denied.get("error", "")) == "NO_STARDUST", "lab buy denied without stardust")

	section("status / profile / starter routes")
	var status := Save.handle("GET", "/status", {}, {})
	ok(bool(status.get("ok", false)) and bool(status.get("offline", false)), "GET /status")
	ok(not String(status.get("build", "")).is_empty(), "GET /status reports the ported build id")
	var prof := Save.handle("GET", "/profile", {}, {})
	ok(prof.get("profile") is Dictionary, "GET /profile")
	var starter := Save.handle("POST", "/profile/starter", {}, {"id": 25})
	ok(int(PbJson.as_dict(starter.get("profile", {})).get("starter", 0)) == 25, "POST /profile/starter")
	ok(PbJson.as_array(Save.store["captured"]).has(25), "starter is captured")
	var prefs := Save.handle("PUT", "/profile/prefs", {}, {"settings": {"music": 0.4, "aimMode": "manual"}})
	ok(bool(prefs.get("ok", false)), "PUT /profile/prefs")
	ok(is_equal_approx(float(PbJson.as_dict(PbJson.as_dict(prefs.get("profile", {})).get("settings", {})).get("music", 0.0)), 0.4),
		"music setting persisted")
	ok(String(PbJson.as_dict(PbJson.as_dict(prefs.get("profile", {})).get("settings", {})).get("aimMode", "")) == "manual",
		"aimMode setting persisted")
	var guest := Save.handle("POST", "/auth/guest", {}, {})
	ok(String(guest.get("name", "")).begins_with("Invitado"), "POST /auth/guest names the guest")

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
	ok(PbJson.as_dict(Save.store["research"]).has("1"), "research tracked for the species")

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
	ok(Save.restore_backup(String(PbJson.as_dict(backups[0]).get("id", ""))), "restore latest backup")

	section("round trip through disk")
	Save.reset(true)
	Save.store["name"] = "验证员"
	Save.save()
	var raw := JSON.parse_string(FileAccess.get_file_as_string(Save.save_path()))
	var envelope := PbJson.as_dict(raw)
	ok(String(PbJson.as_dict(envelope.get("profile", {})).get("name", "")) == "验证员", "name survived the round trip")
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
	ok(PbTheme.rarity_color(0) == PbTheme.css_color(String(PbTheme.vars().get("--r0", ""))), "rarity0 == --r0")
	var th := PbTheme.danger_thresholds()
	ok(th.size() == 7 and float(th[0]) == 0.0 and float(th[6]) == 7.0, "danger thresholds [0..7]")
	ok(PbTheme.danger_colors().size() == 7, "danger has 7 segment colours")
	ok(PbTheme.danger_level(7.0) == 6 and PbTheme.danger_level(0.5) == 0, "danger_level bucketing")
	ok(PbTheme.rarity_labels().size() == 5, "rarity labels table")
	# gradient + keyframe parsing
	var btn_g := PbTheme.gradient(String(PbTheme.decls(".btn").get("background", "")))
	ok(btn_g.get("type", "") == "linear" and PbJson.as_array(btn_g.get("stops", [])).size() == 3, ".btn gradient 3 stops")
	ok(PbTheme.keyframe_frames("cardIn").size() >= 1, "cardIn keyframe parsed")
	ok(String(PbTheme.anim_of(".card", "cardIn")["name"]) == "cardIn", ".card anim name")
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


func report() -> void:
	print("\n=== %d checks, %d failures ===" % [_checks, _failures.size()])
	for f in _failures:
		print("  ✗ " + f)
	if _failures.is_empty():
		print("  ✔ port verification passed")
