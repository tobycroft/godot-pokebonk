class_name PbJson
extends RefCounted
## Small helpers for reading the ported JSON tables.
##
## All game data lives under res://data (copied 1:1 from pokebonk-web/data) and
## res://data/pb (tables reverse-engineered from the web bundle by
## pokebonk-web/tools-re/build_pb_data.py).

const DATA_DIR := "res://data"
const PB_DIR := "res://data/pb"


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("PbJson: missing file %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("PbJson: empty file %s" % path)
		return null
	var parsed := JSON.parse_string(text)
	if parsed == null:
		push_error("PbJson: failed to parse %s" % path)
	return parsed


static func data(name: String) -> Variant:
	return read_json(DATA_DIR.path_join(name))


static func pb(name: String) -> Variant:
	return read_json(PB_DIR.path_join(name))


static func as_dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


## str() cannot convert null (it raises a parse-time constructor error), and
## the JSON tables are full of explicit nulls (e.g. type_status.dragon = null),
## so every string read goes through here.
static func as_string(value: Variant, fallback: String = "") -> String:
	return fallback if value == null else str(value)


static func as_float(value: Variant, fallback: float = 0.0) -> float:
	return fallback if value == null else float(value)


static func as_int(value: Variant, fallback: int = 0) -> int:
	return fallback if value == null else int(value)


static func as_bool(value: Variant, fallback: bool = false) -> bool:
	return fallback if value == null else bool(value)
