class_name PbCombat
extends RefCounted
## Combat tuning recovered 1:1 from the shipped web build (main-C5MieX6g-mvpjh5lt.js
## and its news-BJhqkt7g shared chunk). Every table below carries the offset of the
## code it was read from; anything the build does not expose is marked 待确认.
##
## Sources
##   director.Ab.hpCurve/hpMult/dmgMult/toughness/speedMult  @878271
##   director.Ab.update(credits/caps/elites)                 @884400
##   enemy pool spawn()                                      @346928
##   Wv.strike()                                             @746724
##   player hurt()                                           @846019
##   Qy() stats                                              @812367
##   news chunk tables (credit rate / tier table)            @news:1e55a

## Ab.caps(): enemies the director wants alive. Portal keeps its own ceiling.
const MAX_ENEMIES := 1400           # Ab.maxEnemies @1507181 (co-op: 800)
const COOP_MAX_ENEMIES := 800
const MAX_SPAWNS_PER_SEC := 1800.0  # Ab.MAX_SPAWNS_PER_SEC @876500
const SPAWN_ALLOWANCE_CAP := 180.0  # 0.1 * MAX_SPAWNS_PER_SEC

## Ab.effTime(): stage 2/3 start with a head start once 20s have elapsed.
const BONUS_SECONDS := [0.0, 75.0, 150.0]      # news `Ut`
const HP_AMOUNT := [1.0, 5.5, 13.0, 20.0]      # Ab.hpCurve amount
const HP_RATE := [0.15, 0.07, 0.05, 0.05]      # Ab.hpCurve quadratic rate
const STAGE_DAMAGE := [1.0, 2.0, 3.1, 3.4]     # news `Gt` (director.dmgMult)
const TIER_AMOUNT := [1.0, 1.3, 1.6]           # tier table amount
const TIER_ELITE := [0.0, 0.04, 0.08]           # tier table elite
const TIER_CAP := [1.0, 1.15, 1.3]              # tier table cap
const TIER_LATE := [1.0, 1.12, 1.25]            # tier table late (stage>=2 dmg)
const TIER_EARLY := [0.0, 15.0, 30.0]           # tier table early (timeline head start)
## The port runs a single difficulty tier, so it reads row 0 of the tier table.
const DEFAULT_TIER := 0

## Flag word from the enemy pool (offset 346928) -- the old port dictionary had the
## bit values shuffled. 12290 = Alpha|Totem|Summoner, the "elite-like" family used
## by presage / razor-fang / the eliteDamage branch.
const FLAG_ELITE := 1
const FLAG_ALPHA := 2
const FLAG_BOSS := 4
const FLAG_CAPTURE := 128
const FLAG_TOTEM := 4096
const FLAG_SUMMONER := 8192
const FLAG_TREASURE := 16384
const ELITE_FAMILY := 12290

## spawn() tier -> multipliers @346928.
const TIERS := {
	"wild": {"flags": 0, "hp": 1.0, "dmg": 1.0, "speed": 1.0, "xp": 1.0},
	"elite": {"flags": FLAG_ELITE, "hp": 4.5, "dmg": 1.4, "speed": 1.0, "xp": 6.0},
	"alpha": {"flags": FLAG_ALPHA, "hp": 22.0, "dmg": 1.8, "speed": 0.9, "xp": 25.0},
	"boss": {"flags": FLAG_BOSS, "hp": 70.0, "dmg": 2.2, "speed": 0.85, "xp": 60.0},
	"legendary": {"flags": FLAG_BOSS, "hp": 70.0, "dmg": 2.2, "speed": 0.85, "xp": 60.0},
	"totem": {"flags": FLAG_TOTEM, "hp": 30.0, "dmg": 1.6, "speed": 0.9, "xp": 35.0},
	"summoner": {"flags": FLAG_SUMMONER, "hp": 14.0, "dmg": 1.2, "speed": 1.0, "xp": 20.0},
	"treasure": {"flags": FLAG_TREASURE, "hp": 9.0, "dmg": 1.0, "speed": 1.0, "xp": 1.0},
}

## ab[ability].dmgTaken @846268 / @814693 / @826070 / @826176 / @832693 / @833596.
const ABILITY_DMG_TAKEN := {
	"sludge-body": 0.85, "phantom": 0.8, "water-absorb": 0.85,
	"volt-absorb": 0.85, "fluffy": 0.8, "bulletproof": 0.85,
}

## ab[ability].lowHp @814531 (torrent-shell), @816320 (bone-keeper), @832859 (defiant).
const ABILITY_LOW_HP := {"torrent-shell": 1.4, "bone-keeper": 1.35, "defiant": 1.4}


## ---------------------------------------------------------------- director
static func eff_time(stage: int, stage_t: float) -> float:
	if stage < 2 or stage > 3:
		return stage_t
	return stage_t + float(BONUS_SECONDS[stage - 1]) * minf(1.0, stage_t / 20.0)


static func hp_curve(stage: int, t: float) -> float:
	var idx := mini(maxi(stage - 1, 0), 3)
	var amount := float(HP_AMOUNT[idx])
	var rate := float(HP_RATE[idx])
	var i := maxf(0.0, t - (1.5 if stage == 1 else 0.0))
	return (1.0 + t * 0.3 + i * i * rate) * amount


## Ab.hpMult() @878271: `hpCurve(stage, max(t, effTime()/60)) * diff.enemyHp *
## player.stats.difficulty * swarmMult(4)`. Endless uses its own curve (`Wt` @news,
## not recovered -> 待确认); the port only runs standard mode.
static func hp_mult(stage: int, stage_t: float, diff: Dictionary, difficulty: float = 1.0) -> float:
	var e := eff_time(stage, stage_t)
	var t := maxf(e / 60.0, 0.0)
	return hp_curve(stage, t) * float(diff.get("enemyHp", 1.0)) * difficulty


## Ab.dmgMult(): base stage factor [1,2,3.1,3.4] times the per-minute ramp.
static func dmg_mult(stage: int, stage_t: float, late_tier: int = DEFAULT_TIER) -> float:
	var e := eff_time(stage, stage_t)
	var n := e / 60.0
	var late := 1.0
	if stage >= 2:
		late = float(TIER_LATE[late_tier])
	return (1.0 + n * 0.13) * float(STAGE_DAMAGE[mini(maxi(stage - 1, 0), 3)]) * late


## Ab.toughness() @878271: `1.35 + 1.05*max(0, 1 - effTime/480)`, evaluated on the
## current effective stage time (not fixed at 0). Only wild spawns use it.
static func toughness(effective_time: float) -> float:
	return 1.35 + 1.05 * maxf(0.0, 1.0 - effective_time / 480.0)


static func speed_mult(stage: int, stage_t: float) -> float:
	var e := eff_time(stage, stage_t)
	return minf(1.3, 1.0 + 0.02 * (e / 60.0) + 0.06 * float(stage - 1))


## Ab.caps(): round() of the desired live population.
static func enemy_cap(stage: int, stage_t: float) -> int:
	var e := eff_time(stage, stage_t)
	var base := 10.0 + e * 0.65 + pow(e / 60.0, 2.0) * 4.5
	base *= 1.0 + float(stage - 1) * 0.6
	base *= float(TIER_CAP[DEFAULT_TIER])
	return int(round(base))


## news `Kt`: credit income per second at a given effective time.
static func credit_rate_base(effective_time: float) -> float:
	return 0.7 + 0.014 * effective_time + 0.5 * pow(effective_time / 60.0, 1.75)


## Ab.update(): credits += ft(effTime) * (1+(stage-1)*0.35) * difficulty * enemyAmount
static func credit_rate(stage: int, stage_t: float, difficulty: float, enemy_amount: float) -> float:
	var e := eff_time(stage, stage_t)
	return credit_rate_base(e) * (1.0 + float(stage - 1) * 0.35) * difficulty * enemy_amount


## Ab.update(): wild-spawn card cost @884400 (`1 + bst/220`).
static func spawn_cost(bst: float) -> float:
	return 1.0 + bst / 220.0


## Ab.update(): elite chance per spawn. Stage 1 waits 90s before any elite.
static func elite_chance(stage: int, stage_t: float, difficulty: float, elite_spawn: float,
		tier: int = DEFAULT_TIER) -> float:
	if stage == 1 and stage_t < 90.0:
		return 0.0
	var base := 0.012 + stage_t / 60.0 * 0.004 + float(stage - 1) * 0.03
	base += float(TIER_ELITE[tier]) + (difficulty - 1.0) * 0.05
	return base * elite_spawn


## spawn() @346928: one enemy's combat numbers.
## hp_mult/dmg_mult come from the director; `weight` is the spawn mass (`o`).
static func enemy_numbers(species: Dictionary, tier_name: String, hp_multiplier: float,
		dmg_multiplier: float, weight: float = 1.0, tough: float = 1.0,
		speed_scale: float = 1.0) -> Dictionary:
	var raw := PbJson.as_dict(species.get("stats", {}))
	var bst := float(species.get("bst", 300.0))
	var atk := float(raw.get("atk", 50.0))
	var spa := float(raw.get("spa", 50.0))
	var spe := float(raw.get("spe", 50.0))
	var tier: Dictionary = TIERS.get(tier_name, TIERS["wild"])
	var tiered := int(tier["flags"]) != 0
	var effective_tough := tough
	if tiered:
		effective_tough = 1.0
	var hp := minf(3.0e38, (12.0 + bst * 0.055) * hp_multiplier * effective_tough * weight)
	# Speed: `min(6.2,(3+spe/55)*(o>2500?.8:1))*(boss?.85:alpha/totem?.9:1)`.
	var base_speed := minf(6.2, (3.0 + spe / 55.0) * (0.8 if weight > 2500.0 else 1.0))
	var speed := base_speed * float(tier["speed"]) * speed_scale
	var dmg := minf(1.0e38, (5.0 + atk / 16.0 + spa / 24.0) * dmg_multiplier * float(tier["dmg"]))
	var xp := (1.0 + bst / 300.0) * (1.0 + (effective_tough - 1.0) * 0.35) * float(tier["xp"]) * weight
	return {
		"hp": hp, "dmg": dmg, "speed": speed, "xp": xp,
		"weight": weight, "flags": int(tier["flags"]),
	}


## ---------------------------------------------------------------- growth
## Ob.checkGrowth() @836543: growth index = thresholds at level 24 and 44.
static func growth_index(level: int) -> int:
	return (1 if level >= 24 else 0) + (1 if level >= 44 else 0)


## ---------------------------------------------------------------- abilities
static func dmg_taken(ability: String) -> float:
	return float(ABILITY_DMG_TAKEN.get(ability, 1.0))


## player.bonusDamageMult() @841430. Items/metronome/aura timers are not modelled
## by the port; those parts are 待确认 and read as 1.0.
static func bonus_damage_mult(player: Dictionary, run: Dictionary, weather: String) -> float:
	var ability := str(player.get("ability", ""))
	var mul := 1.0
	if ABILITY_LOW_HP.has(ability):
		var max_hp := maxf(1.0, float(player.get("maxHp", 1.0)))
		if float(player.get("hp", 0.0)) / max_hp < 0.4:
			mul *= float(ABILITY_LOW_HP[ability])
	if ability == "gem-hoarder":
		mul *= 1.0 + minf(0.25, maxf(0.0, float(run.get("gold", 0.0))) / 2500.0)
	if (ability == "chlorophyll" and weather == "sun") or (ability == "swift-swim" and weather == "rain"):
		mul *= 1.2
	# speed-boost/moxie/horn-pride use speedBoostT, aura use auraStacks, anger uses
	# angerT: none of those timers exist in the headless run -> unchanged (待确认).
	return mul


## Av(ability).hitMul @743016 and friends.
static func ability_hit_mul(ability: String, movedef: Dictionary, actor: Dictionary,
		target_flags: int = 0) -> float:
	var key := str(movedef.get("key", ""))
	var arch := str(movedef.get("arch", ""))
	var move_type := str(movedef.get("type", ""))
	match ability:
		"leek-master":
			# @720402: 4% of hits become a x8 "¡Bonk!" (stacks with the Leek item).
			return 8.0 if PbRng.chance(0.04) else 1.0
		"rock-head":
			return 1.3 if arch == "dash" else 1.0
		"hyper-cutter":
			# @726142: every 5th strike is a pincer (species 99: every 4th). The
			# counter lives in the web combat state; the port keeps the +20% floor.
			return 1.2 if arch == "strike" else 1.0
		"limber-kicks":
			return 1.2 if key.contains("kick") else 1.0
		"iron-fist":
			return 1.2 if key.contains("punch") else 1.0
		"spiral-shell":
			return 1.15 if move_type in ["rock", "water"] else 1.0
		"battle-armor":
			if int(actor.get("species_id", 0)) == 141 and arch in ["strike", "boomerang"]:
				return 1.2
			return 1.0
		"mold-breaker":
			# Av(mold-breaker).hitMul @738063: `flags & (Boss|12290) ? 1.2 : 1`.
			return 1.2 if target_flags & (FLAG_BOSS | ELITE_FAMILY) != 0 else 1.0
	return 1.0


## Av(ability).critAdd @738077 (mold-breaker) / @738807 (download).
static func ability_crit_add(ability: String, movedef: Dictionary) -> float:
	if ability == "mold-breaker" and str(movedef.get("key", "")) == "storm-throw":
		return 1.0
	return 0.0


## Av(ability).hurtMod @743016: battle-armor softens big hits by 3+0.3*level.
static func ability_hurt_mod(ability: String, incoming: float, level: int) -> float:
	if ability == "battle-armor":
		return maxf(incoming * 0.25, incoming - (3.0 + float(level) * 0.3))
	return incoming


## ---------------------------------------------------------------- boss
## Ab.BOSS_ZONE_HP @881613: boss hp factor by stage [.8,.55,.5,.5]; the spawn
## also applies a flat 1.6 to `hpMult()` (@1022916).
const BOSS_ZONE_HP := [0.8, 0.55, 0.5, 0.5]
const BOSS_HP_BONUS := 1.6
## Ex @1023449: fight seconds before a boss is exhausted (legendary/guardian).
const BOSS_FIGHT_SECS := 60.0


## Boss.exhaust() @1024583: once `fightT - 2*fightSecs` is positive, every 20s
## doubles the damage the boss takes (capped at 1e9).
static func boss_exhaust(fight_t: float, fight_secs: float = BOSS_FIGHT_SECS) -> float:
	var t := fight_t - fight_secs * 2.0
	if t <= 0.0:
		return 1.0
	return minf(1.0e9, pow(2.0, t / 20.0))


## ---------------------------------------------------------------- endless
## siegeMult @1399900 (`v(max(camp,idle))` in the shipped build): from t>=300s
## the multiplier falls from 1 to .3 across 20s grace + 40s ramp.
static func siege_mult(idle: float, run_time: float, endless: bool) -> float:
	if not endless or run_time < 300.0:
		return 1.0
	var ramp := clampf((idle - 20.0) / 40.0, 0.0, 1.0)
	return 1.0 - (1.0 - 0.3) * ramp


## news `tn`: endless xp requirement curve (used by PbXp.xp_for).
static func endless_xp_mult(level: int) -> float:
	return pow(1.008, float(maxi(0, level - 60)))


## ---------------------------------------------------------------- status

## Wv.strike status block @746900: durations are multipliers of stats.duration.
## `resist` = .35 for bosses, .6 for the 12290 family, else 1.
static func status_resist(flags: int) -> float:
	if flags & FLAG_BOSS != 0:
		return 0.35
	if flags & ELITE_FAMILY != 0:
		return 0.6
	return 1.0


static func status_seconds(kind: String, duration_stat: float, resist: float,
		black_sludge: bool = false) -> float:
	var a := duration_stat
	match kind:
		"burn": return 3.0 * a
		"poison": return 5.0 * a * (1.25 if black_sludge else 1.0)
		"paralysis": return 3.0 * a
		"freeze": return 1.6 * a * resist
		"sleep": return 3.0 * a * resist
		"confusion": return 3.0 * a * resist
		"wet": return 5.0 * a
		"curse": return 4.0 * a
		"healblock": return 6.0 * a
		"charm": return 3.0 * a * resist
		"root": return 2.0 * a * resist
		"stun": return 0.5 * resist
	return 0.0


## DoT strengths @746900: they scale with the damage of the hit that applied them.
const BURN_DPS_RATIO := 0.3     # burnDps = hit * .3 * stats.statusDamage
const POISON_DPS_RATIO := 0.12  # poisonDps = hit * .12 * stats.statusDamage
const POISON_STACK_CAP := 10
