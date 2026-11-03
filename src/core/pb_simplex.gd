class_name PbSimplex
extends RefCounted
## Bit-exact port of the client's 2D simplex noise `iu`.
##
## The terrain height field, the plateau edges, the grass/rock blending and the prop
## scatter filters all sample this generator, so the permutation table (built with PbJsRng's
## shuffle) and the simplex kernel are reproduced verbatim rather than substituted with
## FastNoiseLite -- a different lattice would give a different map for the same run seed.
##
## Reference: bundle offset 181841 (`var tu=.5*(Math.sqrt(3)-1),nu=...,ru=[...],iu=class{...}`).

const F2 := 0.36602540378443865   # tu = .5*(sqrt(3)-1)
const G2 := 0.21132486540518711   # nu = (3-sqrt(3))/6
# ru: the eight gradient directions the reference indexes with `& 7`.
const GRAD_X := [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 0.0, 0.0]
const GRAD_Y := [1.0, 1.0, -1.0, -1.0, 0.0, 0.0, 1.0, -1.0]

var _perm := PackedByteArray()


func _init(seed_value: int = 0) -> void:
	var rng := PbJsRng.new(seed_value)
	var table: Array = []
	table.resize(256)
	for i in 256:
		table[i] = i
	rng.shuffle(table)
	_perm.resize(512)
	for i in 512:
		_perm[i] = table[i & 255]


func get2(x: float, y: float) -> float:
	var sk := (x + y) * F2
	var i := floori(x + sk)
	var j := floori(y + sk)
	var t := float(i + j) * G2
	var sx := x - float(i - t)
	var sy := y - float(j - t)
	var l := 1 if sx > sy else 0
	var u := 0 if sx > sy else 1
	var d0 := sx - float(l) + G2
	var f0 := sy - float(u) + G2
	var p0 := sx - 1.0 + 2.0 * G2
	var m0 := sy - 1.0 + 2.0 * G2
	var h := i & 255
	var g := j & 255
	var acc := 0.0

	var v := 0.5 - sx * sx - sy * sy
	if v > 0.0:
		var gi := _perm[h + _perm[g]] & 7
		v *= v
		acc += v * v * (GRAD_X[gi] * sx + GRAD_Y[gi] * sy)
	var w := 0.5 - d0 * d0 - f0 * f0
	if w > 0.0:
		var gj := _perm[h + l + _perm[g + u]] & 7
		w *= w
		acc += w * w * (GRAD_X[gj] * d0 + GRAD_Y[gj] * f0)
	var q := 0.5 - p0 * p0 - m0 * m0
	if q > 0.0:
		var gk := _perm[h + 1 + _perm[g + 1]] & 7
		q *= q
		acc += q * q * (GRAD_X[gk] * p0 + GRAD_Y[gk] * m0)
	return 70.0 * acc


## fbm(x, y, octaves, lacunarity, gain), normalised by the amplitude sum exactly as the
## client does (`s/c`).
func fbm(x: float, y: float, octaves: int = 4, lacunarity: float = 2.0, gain: float = 0.5) -> float:
	var amp := 1.0
	var freq := 1.0
	var sum := 0.0
	var norm := 0.0
	for i in octaves:
		sum += amp * get2(x * freq, y * freq)
		norm += amp
		amp *= gain
		freq *= lacunarity
	return sum / norm
