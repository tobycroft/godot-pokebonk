class_name PbXp
extends RefCounted
## Experience curve and level-up bookkeeping.
##
## Ported from the bundle: ``Cb = e => Math.round(8 + e*5.5 + e**1.8)``
## (offset 834827), consumed by Ob.addXp()/gainLevel()/xpFor() (offset 843511).

## XP needed to go from `level` to `level+1`.
static func need(level: int) -> int:
	var l := float(maxi(1, level))
	return int(round(8.0 + l * 5.5 + pow(l, 1.8)))


## xpFor() @843305: `Math.round(Cb(level) * (run.endless ? Pn(level) : 1))`.
## Pn is the news-chunk `mr` = `e => 1.008 ** Math.max(0, e - 60)` @news:104131.
static func need_for_mode(level: int, endless: bool = false) -> int:
	var base := float(need(level))
	if endless:
		base *= PbCombat.endless_xp_mult(level)
	return int(round(base))


## addXp(): returns the number of levels gained.
static func grant(state: Dictionary, amount: float, xp_gain_mult: float = 1.0, diff_xp_mult: float = 1.0,
		endless: bool = false) -> int:
	var xp := float(state.get("xp", 0.0)) + amount * xp_gain_mult * diff_xp_mult
	var level := int(state.get("level", 1))
	var next := int(state.get("xpNext", need(level)))
	var gained := 0
	while xp >= float(next) and gained < 64:
		xp -= float(next)
		level += 1
		next = need_for_mode(level, endless)
		gained += 1
	state["xp"] = xp
	state["level"] = level
	state["xpNext"] = next
	return gained
