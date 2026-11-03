class_name PbJsRng
extends RefCounted
## Bit-exact port of the client's generator `Ol` (mulberry32).
##
## Every world-system roll in the bundle (terrain, prop scatter, landmarks, ponds) is driven
## by this generator, so the port has to reproduce it bit for bit instead of reusing the LCG
## in PbRng: the same run seed then yields the same map in Godot and in the web build.
##
## Reference: bundle offset 131470 (`Ol=class{s;constructor(e){this.s=e>>>0||2654435769}...`).

const MASK := 0xFFFFFFFF

var _s: int = 0


func _init(seed_value: int = 0) -> void:
	var u := seed_value & MASK
	_s = u if u != 0 else 2654435769


func state() -> int:
	return _s


## next(): the raw float in [0,1) the client calls `this.next()`.
func next() -> float:
	_s = (_s + 1831565813) & MASK
	var e := _s
	e = _imul(e ^ (e >> 15), e | 1)
	e = (e ^ ((e + _imul(e ^ (e >> 7), e | 61)) & MASK)) & MASK
	return float((e ^ (e >> 14)) & MASK) / 4294967296.0


func range_f(from: float, to: float) -> float:
	return from + (to - from) * next()


## int(from, to): Math.floor(range(from, to + 1)) -- inclusive upper bound.
func int_in(from: int, to: int) -> int:
	return int(floorf(range_f(float(from), float(to + 1))))


func pick(array: Array) -> Variant:
	return array[int(next() * float(array.size()))] if not array.is_empty() else null


func chance(p: float) -> bool:
	return next() < p


## shuffle(): the client's in-place Fisher-Yates, driven by next() -- the simplex permutation
## table is built with it, so it has to match exactly.
func shuffle(array: Array) -> Array:
	for i in range(array.size() - 1, 0, -1):
		var j := int(next() * float(i + 1))
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
	return array


func weighted(array: Array, weight_of: Callable) -> Variant:
	var total := 0.0
	for e in array:
		total += maxf(0.0, float(weight_of.call(e)))
	var roll := next() * total
	for e in array:
		roll -= maxf(0.0, float(weight_of.call(e)))
		if roll <= 0.0:
			return e
	return array[array.size() - 1] if not array.is_empty() else null


## Math.imul: 32-bit signed multiply; masking to 32 bits keeps the low word identical.
static func _imul(a: int, b: int) -> int:
	return (a * b) & MASK
