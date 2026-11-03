class_name PbWeather
extends RefCounted
## Weather definitions recovered from the bundle (news chunk, table `s`).
##
## Weather changes damage multipliers in PbDamage.strike() (boost 1.3 / nerf 0.75)
## and is set by the moves listed in data/pb/arch_rules.json -> weather_moves.
## `hail`/`snowscape` both map to hail, matching the web `sy` table.

const BOOST_MULT := 1.3
const NERF_MULT := 0.75

var key: String = "clear"
var display_name: String = "Despejado"
var boosts: Dictionary = {}
var nerfs: Dictionary = {}

static var _table: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	var raw := PbJson.as_dict(PbData.pb_table("weather"))
	for key in raw.keys():
		var entry := PbJson.as_dict(raw[key])
		var w := PbWeather.new()
		w.key = String(key)
		w.display_name = String(entry.get("name", key))
		for t in PbJson.as_array(entry.get("boost", [])):
			w.boosts[String(t)] = true
		for t in PbJson.as_array(entry.get("nerf", [])):
			w.nerfs[String(t)] = true
		_table[String(key)] = w
	_loaded = true


static func of(key: String) -> PbWeather:
	_ensure()
	if _table.has(key):
		return _table[key]
	return _table.get("clear", PbWeather.new())


static func keys() -> Array:
	_ensure()
	return _table.keys()


func boost_mult(type_name: String) -> float:
	return BOOST_MULT if boosts.has(type_name) else 1.0


func nerf_mult(type_name: String) -> float:
	return NERF_MULT if nerfs.has(type_name) else 1.0


## Combined multiplier the web code applies as two independent ifs.
func type_mult(type_name: String) -> float:
	var m := 1.0
	if boosts.has(type_name):
		m *= BOOST_MULT
	if nerfs.has(type_name):
		m *= NERF_MULT
	return m
