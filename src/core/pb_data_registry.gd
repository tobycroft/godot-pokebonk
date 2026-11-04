class_name PbDataRegistry
extends Node
## Singleton that owns every static table ported from pokebonk-web.
##
## Registered as the "Data" autoload. Two families of tables:
##   res://data/*     -- copied verbatim from pokebonk-web/data (the game's own JSON)
##   res://data/pb/*  -- recovered from the minified bundle by tools-re/build_pb_data.py
##
## Loading is lazy: a table is parsed the first time it is requested, so a
## headless smoke test only pays for what it touches.

const KANTO_SIZE := 151

var _cache := {}
var _by_key := {}
var _move_by_key := {}
var _move_by_id := {}
var _type_index := {}
var _children_of := {}


func _ready() -> void:
	# Warm the indexes the whole game depends on.
	types_table()
	pokemon_list()
	moves_list()


# ------------------------------------------------------------------ raw tables
func types_table() -> Dictionary:
	return _cached_dict("types", "res://data/types.json")


func pokemon_list() -> Array:
	var list := _cached_array("pokemon", "res://data/pokemon.json")
	if _by_key.is_empty():
		for p in list:
			_by_key[int(p["id"])] = p
			_by_key[str(p["key"])] = p
			var from = p.get("evoFrom")
			if from != null:
				var parent := int(from)
				if not _children_of.has(parent):
					_children_of[parent] = []
				_children_of[parent].append(p)
	return list


func moves_list() -> Array:
	var list := _cached_array("moves", "res://data/moves.json")
	if _move_by_key.is_empty():
		for m in list:
			_move_by_key[str(m["key"])] = m
			_move_by_id[int(m["id"])] = m
	return list


func abilities_map() -> Dictionary:
	return _cached_dict("abilities", "res://data/abilities.json")


func items_map() -> Dictionary:
	return _cached_dict("items", "res://data/items.json")


## Run items table (web `wt`/`cr`), exported from the bundle's `Yr` array.
func items_game_map() -> Dictionary:
	var cache_key := "items_game_by_key"
	if not _by_key.has(cache_key):
		var map := {}
		for raw in PbJson.as_array(pb_table("items_game")):
			var def := PbJson.as_dict(raw)
			map[str(def.get("key", ""))] = def
		_by_key[cache_key] = map
	return _by_key[cache_key]


func item_game(key: String) -> Dictionary:
	return PbJson.as_dict(items_game_map().get(key, {}))


func learnsets_map() -> Dictionary:
	return _cached_dict("learnsets", "res://data/learnsets.json")


func sprites_map() -> Dictionary:
	return _cached_dict("sprites", "res://data/sprites.json")


func pb_table(name: String) -> Variant:
	return _cached_value("pb_" + name, "res://data/pb/%s.json" % name)


func constants() -> Dictionary:
	return PbJson.as_dict(pb_table("constants"))


func const_of(path: String, default: Variant = null) -> Variant:
	## constants_of("player_stats.hp_base") style lookups used across the port.
	var node: Variant = constants()
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return default
		node = node[part]
	return node


# ------------------------------------------------------------------ accessors
func species(id_or_key: Variant) -> Dictionary:
	pokemon_list()
	var found = _by_key.get(int(id_or_key) if typeof(id_or_key) != TYPE_STRING else id_or_key)
	return found if found is Dictionary else {}


func move_def(key: String) -> Dictionary:
	moves_list()
	return _move_by_key.get(key, {})


## learnsets.json references moves by *id*, so an id index is needed too.
func move_by_id(move_id: int) -> Dictionary:
	moves_list()
	return _move_by_id.get(move_id, {})


func ability(id_or_key: Variant) -> Dictionary:
	var table := abilities_map()
	if typeof(id_or_key) == TYPE_STRING:
		for key in table.keys():
			if str(table[key].get("key", "")) == str(id_or_key):
				return table[key]
		return {}
	return PbJson.as_dict(table.get(str(int(id_or_key)), {}))


func learnset(species_id: int) -> Array:
	## Entries are [moveId, level] exactly as shipped in learnsets.json.
	return PbJson.as_array(learnsets_map().get(str(species_id), []))


func evolutions_of(species_id: int) -> Array:
	pokemon_list()
	return _children_of.get(species_id, [])


func evo_chain_root(species_id: int) -> int:
	var current := species(species_id)
	while current.get("evoFrom") != null:
		current = species(int(current["evoFrom"]))
	return int(current.get("id", species_id))


func dex_ids(gen: int = 1) -> Array:
	var out := []
	for p in pokemon_list():
		if int(p.get("gen", 1)) <= gen:
			out.append(int(p["id"]))
	return out


func kanto_ids() -> Array:
	var out := []
	for p in pokemon_list():
		var id := int(p["id"])
		if id >= 1 and id <= KANTO_SIZE:
			out.append(id)
	return out


# ------------------------------------------------------------------ type chart
func type_index(type_name: String) -> int:
	if _type_index.is_empty():
		var names: Array = PbJson.as_array(types_table().get("types", []))
		for i in names.size():
			_type_index[str(names[i])] = i
	return _type_index.get(type_name, -1)


func type_names() -> Array:
	return PbJson.as_array(types_table().get("types", []))


func chart_cell(atk: String, def: String) -> float:
	## Raw Pokemon chart value (0 / 0.5 / 1 / 2); PokeBonk remaps it in PbDamage.
	var chart := PbJson.as_array(types_table().get("chart", []))
	var ai := type_index(atk)
	var di := type_index(def)
	if ai < 0 or di < 0 or chart.is_empty():
		return 1.0
	var row := PbJson.as_array(chart[ai])
	if di >= row.size():
		return 1.0
	return float(row[di])


func type_label(type_name: String) -> String:
	return str(PbJson.as_dict(types_table().get("names", {})).get(type_name, type_name))


# ------------------------------------------------------------------ sprite data
func pmd_meta(species_id: int) -> Dictionary:
	return PbJson.as_dict(sprites_map().get(str(species_id), {}))


# ------------------------------------------------------------------ world / terrain
## Tables recovered from the offline mirror by tools/extract_world.py. They drive
## PbTerrain (height field, props, colliders) and the arena renderer.
func world_biomes() -> Array:
	return PbJson.as_array(PbJson.as_dict(pb_table("world_biomes")).get("biomes"))


func biome(id: String) -> Dictionary:
	for b in world_biomes():
		var entry := PbJson.as_dict(b)
		if str(entry.get("id", "")) == id:
			return entry
	push_warning("Data: unknown biome %s" % id)
	return world_biomes()[0] if not world_biomes().is_empty() else {}


func world_pack(pack: String) -> Dictionary:
	return PbJson.as_dict(PbJson.as_dict(pb_table("world_props")).get("packs")).get(pack, {})


func world_constants() -> Dictionary:
	return PbJson.as_dict(pb_table("world_constants"))


func world_palettes() -> Dictionary:
	return PbJson.as_dict(pb_table("world_palettes"))


func world_fx() -> Dictionary:
	return PbJson.as_dict(pb_table("world_fx"))


## Biome titles come with es/en/zh/zht variants straight from the mirror's locale chunks. The
## port is zh-only for now, so zh wins and the Spanish source string is the last resort.
func biome_label(id: String, locale: String = "zh") -> String:
	var raw = biome(id).get("name", {})
	if raw is Dictionary:
		for key in [locale, "zh", "zht", "es"]:
			var text := PbJson.as_string(raw.get(key, ""))
			if not text.is_empty():
				return text
	return PbJson.as_string(raw, id)


## Same fallback order for the free text the tables carry (biome blurbs, zone and hazard names).
func biome_text(id: String, key: String, locale: String = "zh") -> String:
	var raw = biome(id).get(key, {})
	if raw is Dictionary:
		for k in [locale, "zh", "zht", "es"]:
			var text := PbJson.as_string(raw.get(k, ""))
			if not text.is_empty():
				return text
	return PbJson.as_string(raw, "")


# ------------------------------------------------------------------ i18n
func i18n(locale: String) -> Dictionary:
	# The web ships no data/i18n chunk for `es` (Spanish is the source text) or
	# `ko` (UI-only translation); missing files fall back to the original names
	# instead of logging an error.
	var path := "res://data/i18n/%s.json" % locale
	if not FileAccess.file_exists(path):
		return {}
	return _cached_dict("i18n_" + locale, path)


## `locale` defaults to the port's pinned language.
func localized_name(kind: String, id_or_key: Variant, locale: String = "zh") -> String:
	var table := i18n(locale)
	var section := PbJson.as_dict(table.get(kind, {}))
	var key := str(int(id_or_key)) if typeof(id_or_key) != TYPE_STRING else str(id_or_key)
	return str(section.get(key, ""))


# ------------------------------------------------------------------ plumbing
func _cached_value(tag: String, path: String) -> Variant:
	if not _cache.has(tag):
		_cache[tag] = PbJson.read_json(path)
	var value = _cache[tag]
	if value == null:
		push_error("Data: table '%s' unavailable at %s" % [tag, path])
	return value


func _cached_dict(tag: String, path: String) -> Dictionary:
	return PbJson.as_dict(_cached_value(tag, path))


func _cached_array(tag: String, path: String) -> Array:
	return PbJson.as_array(_cached_value(tag, path))
