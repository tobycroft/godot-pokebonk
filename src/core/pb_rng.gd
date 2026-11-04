class_name PbRng
extends RefCounted
## Deterministic RNG for run simulation.
##
## The web client receives a `seed` from POST /runs/start (api-core.js returns a
## random 32-bit int) and replays the run from it, so a seedable generator is the
## faithful port. Implemented as a 32-bit LCG (numerical recipes constants): all
## intermediates stay inside int64, so results are identical on every platform.

const MASK := 0xFFFFFFFF

static var _state: int = 0x9E3779B9


static func seed(value: int) -> void:
	_state = (value ^ 0x9E3779B9) & MASK
	if _state == 0:
		_state = 1


static func state() -> int:
	return _state


static func set_state(value: int) -> void:
	_state = value & MASK


static func next_u32() -> int:
	_state = (_state * 1664525 + 1013904223) & MASK
	return _state


static func randf() -> float:
	return float(next_u32() >> 8) / 16777216.0


static func chance(p: float) -> bool:
	return PbRng.randf() < p


static func randf_range(from: float, to: float) -> float:
	return from + PbRng.randf() * (to - from)


static func randi_range(from: int, to: int) -> int:
	if to <= from:
		return from
	return from + int(PbRng.randf() * float(to - from + 1))


static func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[PbRng.randi_range(0, array.size() - 1)]


static func shuffled(array: Array) -> Array:
	var out := array.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := PbRng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Weighted pick: entries are [weight, value]; returns the value.
static func weighted(entries: Array) -> Variant:
	var total := 0.0
	for e in entries:
		total += maxf(0.0, float(e[0]))
	if total <= 0.0:
		return entries[0][1] if not entries.is_empty() else null
	var roll := PbRng.randf() * total
	var acc := 0.0
	for e in entries:
		acc += maxf(0.0, float(e[0]))
		if roll <= acc:
			return e[1]
	return entries[entries.size() - 1][1]
