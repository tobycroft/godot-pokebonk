class_name PbStatus
extends RefCounted
## Status effects carried by the enemy pool and the player.
##
## The set of tracked statuses comes from the enemy SoA fields (offset 346928:
## burn/poison/poisonStacks/poisonDps/para/stun/chill/chillT/frozen/wet/sleep/
## confuse/curse/healBlock/charm/root/pull) and the player's `pstat`
## (offset 834827: para/sleep/charm/frozen/bound).
##
## Multipliers that the damage code applies are marked "verified" with their
## bundle offset; durations and tick damage were inside closures that never made
## it into a data table, so they are documented estimates (TODO) rather than
## silent guesses.

const KINDS := ["burn", "poison", "paralysis", "freeze", "wet", "sleep",
	"confusion", "curse", "healblock", "charm", "root", "knock", "stun"]

## Verified multipliers found in Wv.strike / the player hurt path.
const VERIFIED := {
	"frozen_damage_taken": 1.2,       # offset 748000 area, s*=1.2 while frozen
	"asleep_damage_taken": 1.8,       # s*=1.8 while asleep
	"asleep_ghost_dark_bonus": 1.7,   # nightmare follow-up
	"curse_damage_taken": 1.25,       # i.curse[e]>0 -> s*=1.25
	"veil_damage_taken": 0.25,        # i.veil[e]==1 -> s*=.25
	"paralysis_beacon_bonus": 1.25,   # attacker ability == beacon
	"poison_venom_sting": 1.2,        # attacker ability == venom-sting
}

## TODO(reverse): durations are per-status closures in the bundle; these defaults
## keep the simulation running and are flagged for later verification.
const DEFAULTS := {
	"burn": {"duration": 6.0, "dps_ratio": 0.02, "verified": false},
	"poison": {"duration": 5.0, "dps_ratio": 0.015, "stack_cap": 5, "verified": false},
	"paralysis": {"duration": 3.0, "speed_mult": 0.5, "verified": false},
	"freeze": {"duration": 2.5, "speed_mult": 0.0, "verified": false},
	"wet": {"duration": 6.0, "verified": false},
	"sleep": {"duration": 3.5, "verified": false},
	"confusion": {"duration": 3.0, "self_hit_chance": 0.2, "verified": false},
	"curse": {"duration": 8.0, "verified": false},
	"healblock": {"duration": 5.0, "verified": false},
	"charm": {"duration": 3.0, "verified": false},
	"root": {"duration": 4.0, "verified": false},
	"knock": {"duration": 0.25, "verified": false},
	"stun": {"duration": 0.8, "verified": false},
}


static func exists(kind: String) -> bool:
	return DEFAULTS.has(kind)


static func duration(kind: String) -> float:
	return float(PbJson.as_dict(DEFAULTS.get(kind, {})).get("duration", 0.0))


static func dps_ratio(kind: String) -> float:
	return float(PbJson.as_dict(DEFAULTS.get(kind, {})).get("dps_ratio", 0.0))


## Status a hit inflicts, given the move's status and its rolled chance.
static func roll(status: Variant, chance: float) -> bool:
	if status == null or String(status).is_empty():
		return false
	return PbRng.chance(chance)
