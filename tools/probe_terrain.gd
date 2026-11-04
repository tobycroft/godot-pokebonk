extends SceneTree
## Headless probe: how long does PbTerrain take, and does it match the reference?
##
##   Godot --headless --path . --script res://tools/probe_terrain.gd [biome] [seed]
##
## Autoloads are not available in --script mode, so the tables are read straight from
## res://data/pb with PbJson (PbTerrain itself only depends on PbJson/PbJsRng/PbSimplex).

const EPS := 1e-5


func _initialize() -> void:
	var biomes_doc := PbJson.as_dict(PbJson.pb("world_biomes.json"))
	var props_doc := PbJson.as_dict(PbJson.pb("world_props.json"))
	var golden_doc := PbJson.as_dict(PbJson.pb("terrain_golden.json"))
	var biomes: Array = PbJson.as_array(biomes_doc.get("biomes"))
	var packs: Dictionary = PbJson.as_dict(props_doc.get("packs"))
	var worlds: Array = PbJson.as_array(golden_doc.get("worlds"))

	var user_args := OS.get_cmdline_user_args()
	var want_biome := str(user_args[0]) if user_args.size() > 0 else ""
	var want_seed := int(user_args[1]) if user_args.size() > 1 else -1

	var cases: Array = []
	for w in worlds:
		if want_biome != "" and str(w["biome"]) != want_biome:
			continue
		if want_seed >= 0 and int(w["seed"]) != want_seed:
			continue
		cases.append(w)
	if cases.is_empty():
		print("no cases (terrain_golden.json empty or filter too narrow)")
		quit(1)
		return

	var failures := 0
	for reference in cases:
		var biome_dict := {}
		for b in biomes:
			if str(b["id"]) == str(reference["biome"]):
				biome_dict = b
				break
		var t: PbTerrain = PbTerrain.new()
		var started := Time.get_ticks_msec()
		t.setup(biome_dict, PbJson.as_dict(packs.get(str(reference["biome"]))), int(reference["seed"]))
		var ms := Time.get_ticks_msec() - started
		var problems := compare(t, reference)
		var status := "OK" if problems.is_empty() else "FAIL"
		print("%s %s seed=%s  %d ms  res=%d props=%d colliders=%d" % [
			status, reference["biome"], reference["seed"], ms, t.res, t.props.size(), t.colliders.size()])
		if problems.is_empty():
			continue
		failures += 1
		for p in problems.slice(0, 12):
			print("    - ", p)
	print("\n%d/%d cases matched the reference exactly" % [cases.size() - failures, cases.size()])
	quit(1 if failures > 0 else 0)


func compare(t: PbTerrain, reference: Dictionary) -> Array[String]:
	var out: Array[String] = []
	_check(out, "world", t.world, float(reference["world"]))
	_check(out, "res", float(t.res), float(reference["res"]))
	_check(out, "cell", t.cell, float(reference["cell"]), 1e-6)
	_check(out, "minH", t.min_h, float(reference["minH"]))
	_check(out, "maxH", t.max_h, float(reference["maxH"]))
	_check(out, "waterLevel", t.water_level, float(reference["waterLevel"]))
	_check(out, "spawnY", t.spawn.y, float((reference["spawn"] as Array)[1]))
	_check(out, "propCount", float(t.props.size()), float((reference["props"] as Dictionary)["count"]))
	_check(out, "colliderCount", float(t.colliders.size()), float((reference["colliders"] as Dictionary)["count"]))
	_check(out, "ponds", float(t.ponds.size()), float((reference["ponds"] as Array).size()))
	var pmass: Array = reference["massifs"]
	for i in mini(pmass.size(), t.massifs.size()):
		var row: Array = pmass[i]
		_check(out, "massif[%d].x" % i, float(t.massifs[i]["x"]), float(row[0]))
		_check(out, "massif[%d].z" % i, float(t.massifs[i]["z"]), float(row[1]))
		_check(out, "massif[%d].r" % i, float(t.massifs[i]["r"]), float(row[2]))
	var ppond: Array = reference["ponds"]
	for i in mini(ppond.size(), t.ponds.size()):
		var prow: Array = ppond[i]
		for c in 6:
			_check(out, "pond[%d][%d]" % [i, c], float([t.ponds[i]["x"], t.ponds[i]["z"], t.ponds[i]["r"],
				t.ponds[i]["h"], t.ponds[i]["level"], t.ponds[i]["seed"]][c]), float(prow[c]))
	_check(out, "landmarks", float(t.landmarks.size()), float((reference["landmarks"] as Array).size()))
	var rlattice := 0
	for h in t.heights:
		rlattice += int(floorf(h * 1000.0 + 0.5))
	_check(out, "lattice", float(rlattice), float(reference.get("lattice", 0)), 0.5)
	if int(reference.get("latticePre", 0)) != 0:
		_check(out, "latticePre", float(t.lattice_pre), float(reference["latticePre"]), 0.5)
	var rramps: Array = reference.get("ramps", [])
	for i in rramps.size():
		if i >= t.ramp_log.size():
			out.append("ramp[%d] missing" % i)
			continue
		for c in 4:
			if int(rramps[i][c]) != int(t.ramp_log[i][c]):
				out.append("ramp[%d][%d]: %d != %d" % [i, c, t.ramp_log[i][c], rramps[i][c]])
	var grid: Array = reference["heights"]
	for a in grid.size():
		var row: Array = grid[a]
		for b in row.size():
			var x := -t.play + (2.0 * t.play * float(a)) / float(grid.size() - 1)
			var z := -t.play + (2.0 * t.play * float(b)) / float(row.size() - 1)
			_check(out, "height[%d][%d]" % [a, b], t.height(x, z), float(row[b]))
	var first: Array = (reference["props"] as Dictionary)["first"]
	for i in mini(first.size(), t.props.size()):
		var p: Dictionary = t.props[i]
		var ref: Array = first[i]
		_check(out, "prop[%d].x" % i, float(p["x"]), float(ref[1]))
		_check(out, "prop[%d].z" % i, float(p["z"]), float(ref[3]))
		_check(out, "prop[%d].s" % i, float(p["s"]), float(ref[5]))
		if str(p["kind"].get("name")) != str(ref[0]):
			out.append("prop[%d].kind: %s != %s" % [i, p["kind"].get("name"), ref[0]])
		if bool(p["flip"]) != bool(ref[4]):
			out.append("prop[%d].flip mismatch" % i)
	var coll: Array = (reference["colliders"] as Dictionary)["first"]
	for i in mini(coll.size(), t.colliders.size()):
		_check(out, "collider[%d].x" % i, float(t.colliders[i]["x"]), float((coll[i] as Array)[0]))
		_check(out, "collider[%d].r" % i, float(t.colliders[i]["r"]), float((coll[i] as Array)[2]))
	return out


func _check(out: Array[String], label: String, got: float, want: float, eps: float = EPS) -> void:
	if absf(got - want) > eps:
		out.append("%s: %.6f != %.6f" % [label, got, want])
