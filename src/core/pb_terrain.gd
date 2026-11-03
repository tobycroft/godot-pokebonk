class_name PbTerrain
extends RefCounted
## Port of the client's world generator (`cd` in the recovered bundle).
##
## This is not a "similar" terrain: it is the same algorithm, in the same order, on the same
## generator (PbJsRng) and the same lattice (PbSimplex), so a run seed produces the *same*
## map in Godot as in the web build. Parity is asserted against `data/pb/terrain_golden.json`
## -- values produced by running the real class in Node (tools/terrain_reference.mjs).
##
## What is covered: the open-world path used by every normal run (random-walk valleys,
## massif plateaus stepped by `step`, terrace blending, ponds carved into plateau tops,
## ramp carving between plateaus, the border wall, the centre dais, water/lava level,
## landmark layout (groves, arches, hollows, meadows, boulder fields, fairy rings), the
## prop scatter with its reservation rules, prop colliders, the ground-shadow mask and the
## cliff max/min attributes the toon shader needs.
##
## What is not: arena/sanctuary layouts (`generateArena`, `generateTower`, `placeArenaEnv`)
## -- those need the per-arena layout tables, which are not extracted yet. `create()` refuses
## an arena and the Run screen keeps the open world.
##
## Reference offsets (bundle `main-CPuTGAQ--mvlr7rzv.js`): terrain class 214534,
## constants 214307 (`Qu=1.12,$u=4.6,...`), prop catalogues 182615, RNG 131470, noise 181841.

const GRID := 1.12          # Qu: target cell size in world units
const STEP := 4.6           # $u: height of one terrace level
const SHORE_DROP := 0.3     # td
const SHORE_BAND := 0.22    # nd
const COAST_BASE := -0.45   # rd
const COAST_SHORE := 1.2    # id
const COAST_BIAS := 0.35    # ad
const GLACIER_BIAS := 0.2   # od
const PIXELS_PER_UNIT := 13.5   # Iu: the toon pixel grid
const DEFAULT_WORLD := 280.0
const DEFAULT_LEVELS := 4.0
# ed: the radius each landmark kind claims (also its reservation radius).
const LANDMARK_RADII := {"grove": 9.0, "fairy": 6.5, "arch": 6.0, "hollow": 6.0,
	"meadow": 9.0, "boulders": 7.5, "pond": 10.0}

var biome: Dictionary = {}
var pack: Dictionary = {}
var seed_value: int = 0
var biome_id: String = "forest"

var world: float = DEFAULT_WORLD
var res: int = 0
var cell: float = 1.0
var play: float = 0.0
var area_mul: float = 1.0

var heights := PackedFloat32Array()
var path_mask := PackedFloat32Array()
var colliders: Array = []
var solid_boxes: Array = []
var clear_zones: Array = []
var massifs: Array = []
var landmarks: Array = []
var ponds: Array = []
var pads: Array = []
var props: Array = []
## Debug aid: the ramp pairs connect_plateaus() carved, in order (grid coordinates).
var ramp_log: Array = []
## Debug aid: hash of the height lattice before connect_plateaus() lowered its ramps,
## so a divergence can be attributed to the field or to the plateau linking.
var lattice_pre: int = 0

var water_level: float = -99.0
var base_water: float = -99.0
var has_water: bool = false
var is_lava: bool = false
var frozen: bool = false
var has_relief: bool = false
var levels: float = DEFAULT_LEVELS
var base_water_band: float = -1.0
var min_h: float = 0.0
var max_h: float = 1.0
var spawn: Vector3 = Vector3.ZERO

var _noise: PbSimplex
var _noise2: PbSimplex
var _col_grid: Dictionary = {}
# Random-walk polylines flattened into segments (float64: the reference never leaves double).
var _seg_x0 := PackedFloat64Array()
var _seg_z0 := PackedFloat64Array()
var _seg_dx := PackedFloat64Array()
var _seg_dz := PackedFloat64Array()
var _seg_l2 := PackedFloat64Array()


## Build one world. `biome_dict`/`pack_dict` come from data/pb/world_biomes.json and
## world_props.json (see PbData); passing empty dictionaries is a caller error.
static func create(biome_dict: Dictionary, pack_dict: Dictionary, seed: int) -> PbTerrain:
	var t := PbTerrain.new()
	t.setup(biome_dict, pack_dict, seed)
	return t


func setup(biome_dict: Dictionary, pack_dict: Dictionary, seed: int) -> void:
	biome = biome_dict
	pack = pack_dict
	seed_value = seed & 0xFFFFFFFF
	biome_id = String(biome.get("id", "forest"))
	world = PbJson.as_float(biome.get("size"), DEFAULT_WORLD)
	var is_arena := false
	res = js_roundf(world / GRID)
	cell = world / float(res)
	play = world / 2.0 - 12.0
	area_mul = pow(world / 280.0, 2.0)
	heights.resize((res + 1) * (res + 1))
	path_mask.resize((res + 1) * (res + 1))
	_noise = PbSimplex.new(seed_value)
	_noise2 = PbSimplex.new(seed_value ^ 1540483477)
	var water: Variant = biome.get("water")
	has_water = (not is_arena) and water != null
	is_lava = (not is_arena) and water != null and int(water) == -1
	frozen = (not is_arena) and biome_id == "glacier"
	var relief: Dictionary = PbJson.as_dict(biome.get("relief"))
	has_relief = not relief.is_empty()
	levels = PbJson.as_float(relief.get("levels"), DEFAULT_LEVELS)
	generate()
	plan_landmarks()
	place_props()


# ------------------------------------------------------------------- JS semantics
## Math.round: half toward +inf (Godot's roundi rounds away from zero).
static func js_roundf(v: float) -> int:
	return int(floorf(v + 0.5))


## qs(): smoothstep that also accepts an inverted edge pair (used as a ramp mask).
static func sstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func clmp(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


func idx(gx: int, gz: int) -> int:
	return gz * (res + 1) + gx


# ------------------------------------------------------------------- queries
func height(x: float, z: float) -> float:
	var half := world / 2.0
	var r := clmp((x + half) / cell, 0.0, float(res) - 0.001)
	var s := clmp((z + half) / cell, 0.0, float(res) - 0.001)
	var a := int(floorf(r))
	var b := int(floorf(s))
	var fr := r - float(a)
	var fs := s - float(b)
	var h00 := heights[idx(a, b)]
	var h10 := heights[idx(a + 1, b)]
	var h01 := heights[idx(a, b + 1)]
	var h11 := heights[idx(a + 1, b + 1)]
	return (h00 * (1.0 - fr) + h10 * fr) * (1.0 - fs) + (h01 * (1.0 - fr) + h11 * fr) * fs


func normal_at(x: float, z: float) -> Vector3:
	var r := 0.5
	return Vector3(
		height(x - r, z) - height(x + r, z),
		2.0 * r,
		height(x, z - r) - height(x, z + r)
	).normalized()


func water_at(x: float, z: float) -> float:
	if not has_water:
		return -99.0
	if not has_relief:
		return water_level
	for p in ponds:
		var dx: float = x - float(p["x"])
		var dz: float = z - float(p["z"])
		var rr: float = float(p["r"]) * 1.3
		if dx * dx + dz * dz < rr * rr:
			return float(p["level"])
	return -99.0


func surface(x: float, z: float) -> float:
	var h := height(x, z)
	var w := water_at(x, z)
	return w if h < w else h


func in_water(x: float, z: float) -> bool:
	return height(x, z) < water_at(x, z) - 0.3


func walk_lim() -> float:
	return play - 2.0


func in_bounds(x: float, z: float, pad: float = 0.0) -> bool:
	var lim := play - pad
	return x > -lim and x < lim and z > -lim and z < lim


func is_flat_open(x: float, z: float) -> bool:
	return normal_at(x, z).y > 0.94 and not height(x, z) < water_at(x, z) + 0.25


func reserve(x: float, z: float, r: float) -> void:
	clear_zones.append({"x": x, "z": z, "r": r})


func is_reserved(x: float, z: float, pad: float = 0.0) -> bool:
	for c in clear_zones:
		var dx: float = x - float(c["x"])
		var dz: float = z - float(c["z"])
		var rr: float = float(c["r"]) + pad
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


static func cell_key(x: float, z: float) -> int:
	return (int(floorf(x / 8.0)) + 1000) * 4096 + (int(floorf(z / 8.0)) + 1000)


func add_collider(collider: Dictionary) -> void:
	colliders.append(collider)
	var key := cell_key(float(collider["x"]), float(collider["z"]))
	if not _col_grid.has(key):
		_col_grid[key] = []
	(_col_grid[key] as Array).append(collider)


## hitProp(): is (x,z) blocked by a prop collider, given the actor's feet height and radius?
func hit_prop(x: float, z: float, y: float, radius: float) -> bool:
	var gx := int(floorf(x / 8.0))
	var gz := int(floorf(z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var bucket = _col_grid.get((gx + dx + 1000) * 4096 + (gz + dz + 1000))
			if bucket == null:
				continue
			for c in bucket:
				if y > float(c["h"]) or bool(c.get("off", false)):
					continue
				var ax: float = x - float(c["x"])
				var az: float = z - float(c["z"])
				var rr: float = float(c["r"]) + radius
				if ax * ax + az * az < rr * rr:
					return true
	return false


# ------------------------------------------------------------------- generation
func generate() -> void:
	var e := PbJsRng.new(seed_value)
	var polys: Array = []
	var walks := 4 + e.int_in(0, 2)
	for w in walks:
		var pts := PackedFloat64Array()
		pts.resize(2)
		var ang := float(w) / float(walks) * TAU + e.range_f(-0.4, 0.4)
		var ox := 0.0
		var oz := 0.0
		var steps := js_roundf(play / 13.0)
		for s in steps:
			ang += e.range_f(-0.55, 0.55)
			ox += cos(ang) * 15.0
			oz += sin(ang) * 15.0
			pts.append(ox)
			pts.append(oz)
		polys.append(pts)

	var relief: Dictionary = PbJson.as_dict(biome.get("relief"))
	var want_massifs := int(PbJson.as_float(relief.get("massifs"), 0.0))
	for attempt in 60:
		if want_massifs <= 0:
			break
		var ang := e.range_f(0.0, TAU)
		var rad := e.range_f(0.4, 0.68) * play
		var big_r := e.range_f(44.0, 50.0)
		var mx := cos(ang) * rad
		var mz := sin(ang) * rad
		if sqrt(mx * mx + mz * mz) < big_r + 22.0:
			continue
		var clash := false
		for m in massifs:
			var dx: float = float(m["x"]) - mx
			var dz: float = float(m["z"]) - mz
			if sqrt(dx * dx + dz * dz) < float(m["r"]) + big_r + 30.0:
				clash = true
				break
		if clash:
			continue
		massifs.append({"x": mx, "z": mz, "r": big_r})
		var spiral := PackedFloat64Array()
		var u := e.range_f(0.0, TAU)
		var dir := 1.0 if e.chance(0.5) else -1.0
		for k in 23:
			var t := float(k) / 22.0
			var n := u + dir * t * TAU * 2.3
			var rr := big_r * (1.12 - t * 0.95)
			spiral.append(mx + cos(n) * rr)
			spiral.append(mz + sin(n) * rr)
		polys.append(spiral)
		want_massifs -= 1
	_build_segments(polys)

	var is_coast := biome_id == "coast"
	var is_glacier := biome_id == "glacier"
	base_water_band = -1.0
	if has_water and not has_relief:
		base_water_band = 0.15 if is_coast else 0.17
	if has_water and has_relief:
		plan_ponds(e)

	var half := world / 2.0
	for gz in res + 1:
		for gx in res + 1:
			var x := float(gx) * cell - half
			var z := float(gz) * cell - half
			path_mask[idx(gx, gz)] = 0.0
			var h := _base_height(x, z, is_coast, is_glacier)
			for p in ponds:
				var px: float = x - float(p["x"])
				var pz: float = z - float(p["z"])
				var dist := sqrt(px * px + pz * pz)
				var pr: float = float(p["r"])
				if dist > pr + 7.0:
					continue
				var ang2 := atan2(pz, px)
				var seed_off: float = float(p["seed"])
				var wob := _noise2.get2(cos(ang2) * 1.2 + seed_off, sin(ang2) * 1.2 - seed_off)
				var c := pr * (0.82 + 0.3 * wob)
				var l := sstep(pr + 7.0, pr + 3.0, dist)
				h = h * (1.0 - l) + float(p["h"]) * l
				if dist < c:
					h = minf(h, float(p["level"]) - 0.06 - 0.39 * sstep(c, c - 3.2, dist))
			var centre := sstep(18.0, 9.0, sqrt(x * x + z * z))
			h = h * (1.0 - centre) + STEP * 1.0 * centre
			h += _noise2.get2(x * 0.07, z * 0.07) * 0.12
			var edge := maxf(absf(x), absf(z))
			h += sstep(play - 4.0, play + 10.0, edge) * (18.0 + _noise.get2(x * 0.05, z * 0.05) * 8.0)
			heights[idx(gx, gz)] = h

	_smooth_lattice()
	if has_relief:
		connect_plateaus()
	if has_water and not has_relief:
		water_level = COAST_BASE if is_coast else base_water_band * levels * STEP - 0.9
	base_water = water_level
	min_h = 1e9
	max_h = -1e9
	for v in heights:
		if v < min_h:
			min_h = v
		if v > max_h:
			max_h = v
	spawn = Vector3(0.0, height(0.0, 0.0), 0.0)


## The `f(e,r)` closure: fbm valleys, massif plateaus, terrace stepping, valley floor blend.
func _base_height(x: float, z: float, is_coast: bool, is_glacier: bool) -> float:
	var i := _noise.fbm(x * 0.011, z * 0.011, 4) * 0.5 + 0.5
	i += _noise2.fbm(x * 0.03, z * 0.03, 2) * 0.04
	if is_coast:
		i -= COAST_BIAS
	if is_glacier:
		i -= GLACIER_BIAS
	i = clmp(i, 0.0, 1.0)
	for m in massifs:
		var dx: float = x - float(m["x"])
		var dz: float = z - float(m["z"])
		var mr: float = float(m["r"])
		var d := sqrt(dx * dx + dz * dz) + _noise2.get2(x * 0.05, z * 0.05) * 6.0
		var s := clmp((mr - d) / (mr * 0.85), 0.0, 1.0)
		i += s * ((levels + 1.35) / levels - i)
	var c := sstep(0.25, 0.55, _noise2.get2(x * 0.014 + 40.0, z * 0.014 - 17.0))
	var f2 := i * levels
	var p := floorf(f2)
	var mfrac := f2 - p
	var hh := 0.035 + c * 0.4
	var g := (p + sstep(0.5 - hh, 0.5 + hh, mfrac)) * STEP
	if is_coast and i >= base_water_band and i < SHORE_BAND:
		g = minf(g, 0.0)
	if i < base_water_band:
		g -= (base_water_band - i) * 18.0
	var u := sstep(8.0, 3.0, _path_distance(x, z)) * (0.55 + 0.45 * sstep(-0.2, 0.3, _noise2.get2(x * 0.02, z * 0.02)))
	var v := i * levels * STEP
	return g * (1.0 - u * 0.92) + v * u * 0.92


func _build_segments(polys: Array) -> void:
	_seg_x0.clear()
	_seg_z0.clear()
	_seg_dx.clear()
	_seg_dz.clear()
	_seg_l2.clear()
	for pts in polys:
		var arr: PackedFloat64Array = pts
		for s in range(arr.size() / 2 - 1):
			var ax: float = arr[s * 2]
			var az: float = arr[s * 2 + 1]
			var bx: float = arr[s * 2 + 2]
			var bz: float = arr[s * 2 + 3]
			_seg_x0.append(ax)
			_seg_z0.append(az)
			_seg_dx.append(bx - ax)
			_seg_dz.append(bz - az)
			_seg_l2.append((bx - ax) * (bx - ax) + (bz - az) * (bz - az))


## Distance to the nearest random-walk path (the valley floor the terrain blends into).
func _path_distance(x: float, z: float) -> float:
	var best := 1e9
	for s in _seg_x0.size():
		var dx: float = _seg_dx[s]
		var dz: float = _seg_dz[s]
		var l2: float = _seg_l2[s]
		if l2 == 0.0:
			l2 = 1e-6
		var ox: float = x - _seg_x0[s]
		var oz: float = z - _seg_z0[s]
		var t := clmp((ox * dx + oz * dz) / l2, 0.0, 1.0)
		var fx := _seg_x0[s] + dx * t - x
		var fz := _seg_z0[s] + dz * t - z
		var d2 := fx * fx + fz * fz
		if d2 < best:
			best = d2
	return sqrt(best)


## 3x3 weighted blur (4/2/1 over 16) applied once from a snapshot of the lattice.
func _smooth_lattice() -> void:
	var src := heights.duplicate()
	for gz in range(1, res):
		for gx in range(1, res):
			var acc := 0.0
			for iz in range(-1, 2):
				for ix in range(-1, 2):
					var w := 4.0 if (ix == 0 and iz == 0) else (2.0 if (ix == 0 or iz == 0) else 1.0)
					acc += src[idx(gx + ix, gz + iz)] * w
			heights[idx(gx, gz)] = acc / 16.0


func plan_ponds(e: PbJsRng) -> void:
	var target := js_roundf(6.0 * sqrt(area_mul)) + e.int_in(0, 1)
	var tries := 0
	while tries < 600 and ponds.size() < target:
		tries += 1
		var r := e.range_f(6.0, 11.0)
		var x := e.range_f(-play + r + 12.0, play - r - 12.0)
		var z := e.range_f(-play + r + 12.0, play - r - 12.0)
		if sqrt(x * x + z * z) < 26.0 + r:
			continue
		var near_massif := false
		for m in massifs:
			var dx: float = float(m["x"]) - x
			var dz: float = float(m["z"]) - z
			if sqrt(dx * dx + dz * dz) < float(m["r"]) + r + 8.0:
				near_massif = true
				break
		if near_massif:
			continue
		var near_pond := false
		for p in ponds:
			var px: float = float(p["x"]) - x
			var pz: float = float(p["z"]) - z
			if sqrt(px * px + pz * pz) < float(p["r"]) + r + 30.0:
				near_pond = true
				break
		if near_pond:
			continue
		var a := _base_height(x, z, biome_id == "coast", biome_id == "glacier")
		var o := float(js_roundf(a / STEP)) * STEP
		if o < STEP * 0.5 or absf(a - o) > 0.4:
			continue
		var bad := 0
		for k in 12:
			var ang := float(k) / 12.0 * TAU
			var b := _base_height(x + cos(ang) * (r + 3.0), z + sin(ang) * (r + 3.0),
					biome_id == "coast", biome_id == "glacier")
			if absf(b - o) > 1.0:
				bad += 1
		if bad > 2:
			continue
		ponds.append({"x": x, "z": z, "r": r, "h": o, "level": o - SHORE_DROP, "seed": e.range_f(0.0, 100.0)})
	for p in ponds:
		landmarks.append({"kind": "pond", "x": float(p["x"]), "z": float(p["z"]), "r": float(p["r"]) * 1.15})


## Flood the walkable lattice from the centre, then ramp the biggest isolated plateaus down
## to it -- the reason a massif is reachable instead of a wall.
func connect_plateaus() -> void:
	for h in heights:
		lattice_pre += int(floorf(h * 1000.0 + 0.5))
	var n := res + 1
	# Math.floor in the reference (not round): the inner window decides which cells are
	# plateau candidates and which are the main walkable region.
	var limit_i := int(floorf((play - 3.0 + world / 2.0) / cell))
	var limit_a := n - 1 - limit_i
	var inside := func(gx: int, gz: int) -> bool:
		return gx >= limit_a and gx <= limit_i and gz >= limit_a and gz <= limit_i
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var banned := PackedByteArray()
	banned.resize(n * n)
	for _round in 40:
		var seen := PackedByteArray()
		seen.resize(n * n)
		var centre := idx(js_roundf((world / 2.0) / cell), js_roundf((world / 2.0) / cell))
		var queue: Array[int] = [centre]
		seen[centre] = 1
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			var cx := cur % n
			var cz := (cur - cx) / n
			for s in steps:
				var nx := cx + s.x
				var nz := cz + s.y
				if not inside.call(nx, nz):
					continue
				var ni := nz * n + nx
				if seen[ni] != 0:
					continue
				if absf(heights[cur] - heights[ni]) > 0.9:
					continue
				seen[ni] = 1
				queue.append(ni)
		var visited := PackedByteArray()
		visited.resize(n * n)
		var biggest: Array[int] = []
		for gz in range(limit_a, limit_i + 1):
			for gx in range(limit_a, limit_i + 1):
				var start := gz * n + gx
				if seen[start] != 0 or visited[start] != 0 or banned[start] != 0:
					continue
				var comp: Array[int] = [start]
				visited[start] = 1
				var h2 := 0
				while h2 < comp.size():
					var cur := comp[h2]
					h2 += 1
					var cx := cur % n
					var cz := (cur - cx) / n
					for s in steps:
						var nx := cx + s.x
						var nz := cz + s.y
						if not inside.call(nx, nz):
							continue
						var ni := nz * n + nx
						if visited[ni] != 0 or seen[ni] != 0:
							continue
						if absf(heights[cur] - heights[ni]) > 0.9:
							continue
						visited[ni] = 1
						comp.append(ni)
				if comp.size() >= 70 and comp.size() > biggest.size():
					biggest = comp
		if biggest.is_empty():
			break
		var best_i := -1
		var best_j := -1
		var best_cost := 1e9
		var reach := int(ceilf(34.0 / cell))
		var r := 0
		while r < biggest.size():
			var iso := biggest[r]
			var ix := iso % n
			var iz := (iso - ix) / n
			var dr := -reach
			while dr <= reach:
				var dc := -reach
				while dc <= reach:
					var gx := ix + dc
					var gz := iz + dr
					if not inside.call(gx, gz):
						dc += 2
						continue
					var ni := gz * n + gx
					if seen[ni] == 0:
						dc += 2
						continue
					var dist := sqrt(float(dc * dc + dr * dr)) * cell
					var diff := absf(heights[iso] - heights[ni]) / 0.42
					if dist < diff or dist < 6.0:
						dc += 2
						continue
					var cost := dist + (dist - diff) * 0.5
					if cost < best_cost:
						best_cost = cost
						best_i = iso
						best_j = ni
					dc += 2
				dr += 2
			r += 3
		if best_i < 0:
			for e in biggest:
				banned[e] = 1
		else:
			carve_ramp(best_i % n, (best_i - best_i % n) / n, best_j % n, (best_j - best_j % n) / n)


## Carve a walkable ramp between two lattice cells (grid coordinates).
func carve_ramp(gx0: int, gz0: int, gx1: int, gz1: int) -> void:
	ramp_log.append([gx0, gz0, gx1, gz1])
	var n := res + 1
	var h0: float = heights[gz0 * n + gx0]
	var h1: float = heights[gz1 * n + gx1]
	var dx := float(gx1 - gx0)
	var dz := float(gz1 - gz0)
	var dl2 := dx * dx + dz * dz
	var w_main := 2.25 / cell
	var w_fade := 1.6 / cell
	var x0 := maxi(0, mini(gx0, gx1) - 6)
	var x1 := mini(n - 1, maxi(gx0, gx1) + 6)
	var z0 := maxi(0, mini(gz0, gz1) - 6)
	var z1 := mini(n - 1, maxi(gz0, gz1) + 6)
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var t := clmp((float(gx - gx0) * dx + float(gz - gz0) * dz) / dl2, -0.06, 1.06)
			var ox := float(gx0) + dx * t - float(gx)
			var oz := float(gz0) + dz * t - float(gz)
			var dist := sqrt(ox * ox + oz * oz)
			if dist > w_main + w_fade:
				continue
			var w := 1.0 if dist <= w_main else 1.0 - (dist - w_main) / w_fade
			var vv := clmp(t, 0.0, 1.0)
			var target := h0 + (h1 - h0) * vv
			var i := gz * n + gx
			heights[i] = heights[i] * (1.0 - w) + target * w


# ------------------------------------------------------------------- landmarks & props
func plan_landmarks() -> void:
	if not pack.has("landmarks"):
		return
	var e := PbJsRng.new(seed_value ^ 1715004)
	var radii: Dictionary = LANDMARK_RADII
	# Landmarks already planned (ponds) reserve their space first.
	for l in landmarks:
		reserve(float(l["x"]), float(l["z"]), float(l["r"]))
	var massif_kinds := ["grove", "fairy"]
	for i in mini(2, massifs.size()):
		var kind: String = String(massif_kinds[i])
		_add_landmark(kind, float(massifs[i]["x"]), float(massifs[i]["z"]), PbJson.as_float(radii.get(kind, 6.0)))
	var pool: Array = []
	for k in ["arch", "hollow", "meadow", "boulders", "fairy"]:
		var taken := false
		for l in landmarks:
			if String(l["kind"]) == k:
				taken = true
				break
		if not taken:
			pool.append(k)
	for i in range(pool.size() - 1, 0, -1):
		var j := e.int_in(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for k in pool.slice(0, 4):
		var r := PbJson.as_float(radii.get(k, 6.0))
		var best := {}
		var best_gap := -1e9
		for _t in 40:
			var pt := _random_point(e, 0.0, 0.0, 35.0, play - 14.0)
			if not _landmark_fits(pt.x, pt.z, r) or is_reserved(pt.x, pt.z, r):
				continue
			var gap := 1e9
			for l in landmarks:
				gap = minf(gap, sqrt(pow(float(l["x"]) - pt.x, 2.0) + pow(float(l["z"]) - pt.z, 2.0)) - float(l["r"]))
			for m in massifs:
				gap = minf(gap, sqrt(pow(float(m["x"]) - pt.x, 2.0) + pow(float(m["z"]) - pt.z, 2.0)) - float(m["r"]))
			if gap > best_gap:
				best_gap = gap
				best = {"x": pt.x, "z": pt.z}
		if not best.is_empty():
			_add_landmark(String(k), float(best["x"]), float(best["z"]), r)


func _add_landmark(kind: String, x: float, z: float, r: float) -> void:
	landmarks.append({"kind": kind, "x": x, "z": z, "r": r})
	reserve(x, z, r)


func _landmark_fits(x: float, z: float, r: float) -> bool:
	var base := height(x, z)
	for i in 10:
		var ang := float(i) / 10.0 * TAU
		var px := x + cos(ang) * r * 0.7
		var pz := z + sin(ang) * r * 0.7
		if not is_flat_open(px, pz) or absf(height(px, pz) - base) > 0.7:
			return false
	return is_flat_open(x, z)


## randomPoint(): the client's rejection sampler (300 tries inside an annulus).
func _random_point(e: PbJsRng, cx: float, cz: float, inner: float, outer: float) -> Vector3:
	for _i in 300:
		var ang := e.range_f(0.0, TAU)
		var rad := e.range_f(inner, outer)
		var x := cx + cos(ang) * rad
		var z := cz + sin(ang) * rad
		if not in_bounds(x, z, 6.0) or not is_flat_open(x, z):
			continue
		if normal_at(x + 2.0, z).y < 0.9 or normal_at(x - 2.0, z).y < 0.9 \
				or normal_at(x, z + 2.0).y < 0.9 or normal_at(x, z - 2.0).y < 0.9:
			continue
		return Vector3(x, height(x, z), z)
	return Vector3(cx, height(cx, cz), cz)


func _kind_by_name(name: String) -> Dictionary:
	for list_key in ["trees", "big", "small", "landmarks"]:
		for k in PbJson.as_array(pack.get(list_key)):
			var kind: Dictionary = PbJson.as_dict(k)
			if String(kind.get("name", "")) == name:
				return kind
	return {}


## placeEnv(): the open-world scatter. Prop order, scales and flips are seed-deterministic.
func place_props() -> void:
	var e := PbJsRng.new(seed_value ^ 11259375)
	props.clear()
	if pack.has("landmarks"):
		_place_landmark_clusters(e)
	var density := PbJson.as_float(biome.get("propDensity"), 1.0)
	_scatter(e, PbJson.as_array(pack.get("trees")), js_roundf(380.0 * density * area_mul), 18.0,
		func(x: float, z: float) -> bool: return _noise.get2(x * 0.025, z * 0.025) > -0.1, 2.0)
	_scatter(e, PbJson.as_array(pack.get("big")), js_roundf(260.0 * area_mul), 14.0,
		func(_x: float, _z: float) -> bool: return true, 2.0)
	_scatter(e, PbJson.as_array(pack.get("small")), js_roundf(2200.0 * area_mul), 6.0,
		func(x: float, z: float) -> bool: return _noise2.get2(x * 0.05, z * 0.05) > -0.15, 0.0)


func _scatter(e: PbJsRng, kinds: Array, count: int, min_dist: float, ok: Callable, pad: float) -> void:
	var tries := 0
	var remaining := count
	while tries < remaining * 4 and remaining > 0:
		tries += 1
		var x := e.range_f(-play + 2.0, play - 2.0)
		var z := e.range_f(-play + 2.0, play - 2.0)
		if sqrt(x * x + z * z) < min_dist or not is_flat_open(x, z) or not ok.call(x, z) \
				or is_reserved(x, z, pad):
			continue
		var gx := js_roundf((x + world / 2.0) / cell)
		var gz := js_roundf((z + world / 2.0) / cell)
		if path_mask[idx(gx, gz)] > 0.3:
			continue
		if pad > 1.0 and (normal_at(x + 1.5, z).y < 0.9 or normal_at(x - 1.5, z).y < 0.9
				or normal_at(x, z + 1.5).y < 0.9 or normal_at(x, z - 1.5).y < 0.9):
			continue
		var kind: Dictionary = PbJson.as_dict(e.pick(kinds))
		var scale := e.range_f(0.85, 1.2)
		var y := height(x, z) - 0.08
		props.append({"kind": kind, "x": x, "y": y, "z": z, "flip": e.chance(0.5), "s": scale})
		if PbJson.as_float(kind.get("collider")) > 0.0:
			add_collider({"x": x, "z": z, "r": PbJson.as_float(kind.get("collider")) * scale, "h": y + 6.0})
		remaining -= 1


## placeLandmarks(): the themed clusters (grove, fairy ring, arch, hollow, meadow, boulders).
func _place_landmark_clusters(_e: PbJsRng) -> void:
	var n := PbJsRng.new(seed_value ^ 30673)
	var put := func(kind: Dictionary, x: float, z: float, s: float, collidable: bool = true) -> void:
		if kind.is_empty() or not is_flat_open(x, z):
			return
		var y := height(x, z) - 0.08
		props.append({"kind": kind, "x": x, "y": y, "z": z, "flip": n.chance(0.5), "s": s})
		if collidable and PbJson.as_float(kind.get("collider")) > 0.0:
			add_collider({"x": x, "z": z, "r": PbJson.as_float(kind.get("collider")) * s, "h": y + 8.0})
	var ring := func(names: Array, count: int, rmin: float, rmax: float, cx: float, cz: float,
			lo: float = 0.85, hi: float = 1.15) -> void:
		for _i in count:
			var ang := n.range_f(0.0, TAU)
			var rad := rmin + sqrt(n.next()) * (rmax - rmin)
			var pick_name := String(n.pick(names))
			put.call(_kind_by_name(pick_name), cx + cos(ang) * rad, cz + sin(ang) * rad, n.range_f(lo, hi))
	var flowers := ["flowersA", "flowersB", "sunflower", "tallgrass", "fern"]
	for l in landmarks:
		var kind := String(l["kind"])
		var lx: float = float(l["x"])
		var lz: float = float(l["z"])
		match kind:
			"grove":
				put.call(_kind_by_name("oak"), lx, lz, 1.0)
				var base_ang := n.range_f(0.0, 6.28)
				var candidates: Array = []
				for t in PbJson.as_array(pack.get("trees")):
					if String(PbJson.as_dict(t).get("name", "")) != "tree2":
						candidates.append(t)
				for i in 7:
					var ang := base_ang + float(i) / 7.0 * TAU + n.range_f(-0.2, 0.2)
					var rad := n.range_f(6.5, 8.5)
					var chosen: Dictionary = PbJson.as_dict(n.pick(candidates))
					put.call(chosen, lx + cos(ang) * rad, lz + sin(ang) * rad, n.range_f(0.95, 1.15))
				ring.call(["fern", "flowersA", "flowersB", "mushrooms"], 26, 2.8, 8.0, lx, lz)
			"fairy":
				put.call(_kind_by_name("glowshrooms"), lx, lz, 1.0)
				for i in 12:
					var ang := float(i) / 12.0 * TAU
					put.call(_kind_by_name("mushrooms"), lx + cos(ang) * 4.3, lz + sin(ang) * 4.3, n.range_f(0.85, 1.05))
				ring.call(["flowersA", "flowersB", "fern"], 10, 1.8, 3.4, lx, lz)
				ring.call(["fern", "tallgrass"], 10, 5.0, 6.5, lx, lz)
			"arch":
				put.call(_kind_by_name("arch"), lx, lz, 1.0)
				ring.call(["boulder"], 2, 3.5, 5.0, lx, lz, 0.9, 1.3)
				ring.call(["fern", "tallgrass", "rocks", "flowersA"], 18, 2.0, 6.0, lx, lz)
			"hollow":
				put.call(_kind_by_name("hollowlog"), lx, lz, 1.0)
				ring.call(["stump"], 2, 3.5, 5.0, lx, lz)
				ring.call(["mushrooms", "fern", "tallgrass"], 18, 2.5, 6.0, lx, lz)
			"meadow":
				ring.call(flowers, 75, 0.0, 9.0, lx, lz, 0.9, 1.2)
			"boulders":
				ring.call(["boulder"], 7, 1.0, 6.0, lx, lz, 1.3, 2.2)
				ring.call(["rocks", "fern", "tallgrass"], 16, 1.0, 7.0, lx, lz)
			"pond":
				ring.call(["tallgrass", "tallgrass", "fern", "flowersA", "flowersB"], 34,
					float(l["r"]) * 0.85, float(l["r"]) + 3.0, lx, lz, 0.85, 1.15)
				ring.call(["boulder"], n.int_in(1, 2), float(l["r"]) * 0.9, float(l["r"]) + 2.0, lx, lz, 0.8, 1.2)
	_build_pads(PbJsRng.new(seed_value ^ 39578))


## buildPads(): lily pads on pond surfaces (positions only -- the client draws them as
## instanced geometry, the renderer here uses the same data).
func _build_pads(e: PbJsRng) -> void:
	pads.clear()
	for l in landmarks:
		if String(l["kind"]) != "pond":
			continue
		var lr: float = float(l["r"])
		var tries := 0
		var placed := 0
		while tries < 40 and placed < 6:
			tries += 1
			var ang := e.range_f(0.0, TAU)
			var rad := sqrt(e.next()) * lr * 0.75
			var x := float(l["x"]) + cos(ang) * rad
			var z := float(l["z"]) + sin(ang) * rad
			var w := water_at(x, z)
			if height(x, z) > w - 0.2:
				continue
			var clash := false
			for p in pads:
				var dx: float = float(p["x"]) - x
				var dz: float = float(p["z"]) - z
				if sqrt(dx * dx + dz * dz) < 1.5:
					clash = true
					break
			if clash:
				continue
			pads.append({"x": x, "z": z, "rot": e.range_f(0.0, TAU), "s": e.range_f(0.5, 0.85), "y": w})
			placed += 1


# ------------------------------------------------------------------- renderer inputs
## shadeTex(): the ground-shadow mask the terrain shader samples (world*2 px, one byte each).
func shade_mask(source: Array) -> PackedByteArray:
	var size := js_roundf(world * 2.0)
	var mask := PackedByteArray()
	mask.resize(size * size)
	for p in source:
		var kind: Dictionary = p["kind"]
		var r := PbJson.as_float(kind.get("shadow")) * float(p["s"]) * 0.5
		if r <= 0.0:
			continue
		var cx := (float(p["x"]) + world / 2.0 - 0.25 * r) * 2.0
		var cz := (float(p["z"]) + world / 2.0 - 0.2 * r) * 2.0
		var rx := r * 2.0
		var rz := r * 1.5
		var y0 := maxi(0, int(floorf(cz - rz)))
		var y1 := mini(size - 1, int(ceilf(cz + rz)))
		var x0 := maxi(0, int(floorf(cx - rx)))
		var x1 := mini(size - 1, int(ceilf(cx + rx)))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var d := sqrt(pow((float(x) - cx) / rx, 2.0) + pow((float(y) - cz) / rz, 2.0))
				var v := js_roundf(clmp((1.15 - d) / 0.4, 0.0, 1.0) * 255.0)
				var i := y * size + x
				if v > mask[i]:
					mask[i] = v
	return mask


## Per-vertex data the terrain mesh needs: path mask, colour variation, cliff max/min.
## cliffAttribs() in the reference: two separable passes of a +-2.5 m window max/min, which the
## toon shader uses for wall ambient occlusion and the grass that hangs over cliff tops.
func vertex_attributes() -> Dictionary:
	var n := res + 1
	var count := n * n
	var paths := PackedFloat32Array()
	paths.resize(count)
	var vars_ := PackedFloat32Array()
	vars_.resize(count)
	var cliff_max := PackedFloat32Array()
	cliff_max.resize(count)
	var cliff_min := PackedFloat32Array()
	cliff_min.resize(count)
	var half := world / 2.0
	var span := maxi(1, js_roundf(2.5 / cell))
	for gz in n:
		for gx in n:
			var i := gz * n + gx
			vars_[i] = _noise.get2(float(gx) * cell - half, float(gz) * cell - half) * 0.5 + 0.5
			paths[i] = path_mask[i]
	var hi := PackedFloat32Array()
	hi.resize(count)
	for gz in n:
		for gx in n:
			var m := heights[gz * n + gx]
			for c in range(maxi(0, gx - span), mini(n - 1, gx + span) + 1):
				m = maxf(m, heights[gz * n + c])
			hi[gz * n + gx] = m
	for gz in n:
		for gx in n:
			var i := gz * n + gx
			var m := hi[i]
			for r in range(maxi(0, gz - span), mini(n - 1, gz + span) + 1):
				m = maxf(m, hi[r * n + gx])
			cliff_max[i] = m
	var lo := PackedFloat32Array()
	lo.resize(count)
	for gz in n:
		for gx in n:
			var m := heights[gz * n + gx]
			for c in range(maxi(0, gx - span), mini(n - 1, gx + span) + 1):
				m = minf(m, heights[gz * n + c])
			lo[gz * n + gx] = m
	for gz in n:
		for gx in n:
			var i := gz * n + gx
			var m := lo[i]
			for r in range(maxi(0, gz - span), mini(n - 1, gz + span) + 1):
				m = minf(m, lo[r * n + gx])
			cliff_min[i] = m
	return {"path": paths, "var": vars_, "cliff_max": cliff_max, "cliff_min": cliff_min}
