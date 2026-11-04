extends Node
## Local save/API layer -- the Godot counterpart of pokebonk-web's
## api-core.js (in-browser API) + save-manager.js (export/import/backups).
##
## Storage is a JSON file under user:// instead of localStorage:
##   user://pb.offline.profile.json          the live save (envelope {v, profile, guest, savedAt})
##   user://pb.backup.<YYYYMMDD-HHMMSS>.json automatic snapshots, newest 5 kept
##
## Field names, defaults, action types and reward formulas are ported verbatim
## from api-core.js so an exported save from the web build imports unchanged.

const STORE_KEY := "pb.offline.profile"
const BACKUP_PREFIX := "pb.backup."
const MAX_BACKUPS := 5
const KANTO_SIZE := 151
const BIOMES := ["forest", "desert", "coast", "glacier", "graveyard", "volcano"]

var store: Dictionary = {}
var guest_session := false
var _loaded := false
var _backup_seq := 0


func _ready() -> void:
	load_profile()


# ------------------------------------------------------------------- profiles
func settings_default() -> Dictionary:
	return PbJson.as_dict(_schema().get("settings_default", {}))


func lab_table() -> Array:
	## lab.json holds the upgrade ids and their max ranks, verbatim from
	## api-core.js's LAB table.
	return PbJson.as_array(PbJson.as_dict(PbData.pb_table("lab")).get("upgrades", []))


func lab_max(id: String) -> int:
	for row in lab_table():
		var entry := PbJson.as_dict(row)
		if str(entry.get("id", "")) == id:
			return int(entry.get("max", 1))
	return 1


func _schema() -> Dictionary:
	return PbJson.as_dict(PbData.pb_table("profile_schema"))


func _period() -> Dictionary:
	return {"idx": 0, "ids": [], "prog": [], "claimed": [], "rerolls": 0}


func base_profile(name: String = "Entrenador") -> Dictionary:
	return {
		"v": 1,
		"name": name,
		"created": _now_ms(),
		"stardust": 0,
		"totalStardust": 0,
		"bonk": 0,
		"totalBonk": 0,
		"unlocked": [],
		"league": 1,
		"starter": 0,
		"forms": {},
		"research": {},
		"captured": [],
		"seen": [],
		"played": {},
		"shinies": [],
		"classics": [],
		"skins": [],
		"team": [],
		"lab": {},
		"biomes": ["forest"],
		"quests": [],
		"counters": {
			"gold": 0, "runs": 0, "kills": 0, "bosses": 0, "legendaries": 0,
			"chests": 0, "maxTime": 0, "maxLevel": 0, "playtime": 0, "best_gold": 0,
		},
		"runs": [],
		"best": {},
		"times": {},
		"kills": {},
		"medals": {},
		"endless": {},
		"settings": settings_default(),
		"lastSpecies": 4,
		"lastBiome": "forest",
		"banished": [],
		"itemsOwned": [],
		"itemsOff": [],
		"daily": _period(),
		"weekly": _period(),
		"dailyStreak": 0,
		"bag": {},
		"avatar": null,
		"frame": null,
		"title": null,
		"cosmetics": [],
		"wins": 0,
		"events": {},
		"winsAll": 0,
		"treasures": {},
	}


func fresh_profile() -> Dictionary:
	return base_profile("Entrenador")


## The "full unlock" profile the offline web build starts from (README: 星尘 999999,
## 联盟 151, 研究所全满, 图鉴 151/151).
func full_profile() -> Dictionary:
	var p := base_profile("Entrenador")
	p["stardust"] = 999999
	p["totalStardust"] = 999999
	p["league"] = KANTO_SIZE
	var kanto := _kanto()
	p["unlocked"] = kanto.duplicate()
	p["captured"] = kanto.duplicate()
	p["seen"] = kanto.duplicate()
	p["biomes"] = BIOMES.duplicate()
	for row in lab_table():
		var entry := PbJson.as_dict(row)
		p["lab"][str(entry["id"])] = int(entry["max"])
	p["bag"] = {"rare-candy": 99, "lucky-egg": 1, "amulet-coin": 1}
	p["itemsOwned"] = ["toxic-orb"]
	return p


func _kanto() -> Array:
	var out := []
	for i in KANTO_SIZE:
		out.append(i + 1)
	return out


func normalize(p: Variant) -> Dictionary:
	var base := base_profile(str(PbJson.as_dict(p).get("name", "Entrenador")) if p != null else "Entrenador")
	var incoming := PbJson.as_dict(p)
	var out := base.duplicate(true)
	for key in incoming.keys():
		out[key] = incoming[key]
	out["counters"] = base["counters"].duplicate(true)
	for key in PbJson.as_dict(incoming.get("counters", {})).keys():
		out["counters"][key] = incoming["counters"][key]
	out["settings"] = settings_default()
	for key in PbJson.as_dict(incoming.get("settings", {})).keys():
		out["settings"][key] = incoming["settings"][key]
	out["lab"] = PbJson.as_dict(incoming.get("lab", {})).duplicate(true)
	out["daily"] = _period()
	for key in PbJson.as_dict(incoming.get("daily", {})).keys():
		out["daily"][key] = incoming["daily"][key]
	out["weekly"] = _period()
	for key in PbJson.as_dict(incoming.get("weekly", {})).keys():
		out["weekly"][key] = incoming["weekly"][key]
	for key in ["unlocked", "captured", "seen", "shinies", "classics", "skins", "team",
			"banished", "itemsOwned", "itemsOff", "cosmetics", "biomes"]:
		if typeof(out.get(key)) != TYPE_ARRAY:
			out[key] = []
	if not (out.get("runs") is Array):
		out["runs"] = []
	for key in ["best", "times", "kills", "medals", "endless", "bag"]:
		if typeof(out.get(key)) != TYPE_DICTIONARY:
			out[key] = {}
	# Web saves turn `league` from a number into a starter-id array after
	# /profile/starter (api-core.js:342). The port only needs the progression
	# count, so migrate an imported array to its length; the field shape is kept.
	out["league"] = _league_count(out.get("league", 1))
	return out


# ------------------------------------------------------------------- storage
func save_path() -> String:
	return _path()


func _path() -> String:
	return "user://%s.json" % STORE_KEY


func load_profile() -> Dictionary:
	if _loaded:
		return store
	var raw := _read_text(_path())
	if raw != null and not raw.strip_edges().is_empty():
		var parsed := JSON.parse_string(raw)
		if parsed is Dictionary:
			store = normalize(PbJson.as_dict(parsed).get("profile", parsed))
			guest_session = bool(PbJson.as_dict(parsed).get("guest", false))
			_loaded = true
			return store
		push_warning("Save: corrupt %s, rebuilding full profile" % _path())
	store = full_profile()
	save()
	_loaded = true
	return store


func save() -> void:
	var envelope := {
		"v": 1,
		"profile": store,
		"guest": guest_session,
		"savedAt": _now_ms(),
	}
	if not _write_text(_path(), JSON.stringify(envelope)):
		push_warning("Save: 写入失败（磁盘或权限问题）")


func reset(to_full: bool = true) -> Dictionary:
	store = full_profile() if to_full else fresh_profile()
	guest_session = false
	save()
	return store


# ------------------------------------------------------------------- actions
func apply_actions(actions: Array) -> void:
	for raw in actions:
		var a := PbJson.as_dict(raw)
		match str(a.get("t", "")):
			"addStardust":
				store["stardust"] = int(store.get("stardust", 0)) + int(a.get("v", 0))
				store["totalStardust"] = int(store.get("totalStardust", 0)) + int(a.get("v", 0))
			"addBonk":
				store["bonk"] = int(store.get("bonk", 0)) + int(a.get("v", 0))
				store["totalBonk"] = int(store.get("totalBonk", 0)) + int(a.get("v", 0))
			"unlock":
				store["unlocked"] = _union(store["unlocked"], [int(a.get("id", 0))])
			"capture":
				store["captured"] = _union(store["captured"], [int(a.get("id", 0))])
			"joinLeague":
				# joinLeague() @1667709: a new family enters the league roster; for
				# the int-shaped offline profile this is one more selectable starter.
				var lid := int(a.get("id", 0))
				if not PbJson.as_array(store.get("captured", [])).has(lid):
					var lg = store.get("league", 1)
					if lg is Array:
						store["league"] = _union(lg, [lid])
					else:
						store["league"] = _league_count(lg) + 1
			"count":
				var ckey := str(a.get("id", ""))
				store["counters"][ckey] = int(store["counters"].get(ckey, 0)) + int(a.get("v", 1))
			"seen":
				store["seen"] = _union(store["seen"], [int(a.get("id", 0))])
			"item":
				var ids = a.get("id", [])
				store["itemsOwned"] = _union(store["itemsOwned"], ids if ids is Array else [ids])
			"bag":
				var key := str(a.get("id", ""))
				store["bag"][key] = int(store["bag"].get(key, 0)) + int(a.get("v", 0))
			"league":
				store["league"] = maxi(_league_count(store.get("league", 1)), int(a.get("v", 0)))
			"biome":
				store["biomes"] = _union(store["biomes"], [a.get("id")])
			_:
				pass


## `league` is an int in a fresh profile and a starter-id array after the web's
## /profile/starter route; arithmetic must read either shape.
func _league_count(value: Variant) -> int:
	if value is Array:
		return PbJson.as_array(value).size()
	if value == null:
		return 1
	return int(value)


func _union(list: Variant, add: Variant) -> Array:
	var out: Array = []
	for x in PbJson.as_array(list):
		if not out.has(x):
			out.append(x)
	for x in PbJson.as_array(add):
		if x != null and not out.has(x):
			out.append(x)
	return out


## Port of applyRunResult(): same record shape, same reward formulas.
func apply_run_result(result: Dictionary, run_id: String = "") -> Dictionary:
	var r := result
	var id := run_id if not run_id.is_empty() else str(r.get("id", "r%d" % _now_ms()))
	var rec := {
		"id": id,
		"date": _now_ms(),
		"species": r.get("species"),
		"finalSpecies": r.get("finalSpecies"),
		"biome": r.get("biome"),
		"tier": int(r.get("tier", 0)),
		"stage": int(r.get("stage", 0)),
		"time": float(r.get("time", 0.0)),
		"kills": int(r.get("kills", 0)),
		"damage": float(r.get("damage", 0.0)),
		"level": int(r.get("level", 0)),
		"victory": bool(r.get("victory", false)),
		"score": int(r.get("score", 0)),
		"seed": r.get("seed"),
		"moves": PbJson.as_array(r.get("moves", [])),
		"items": PbJson.as_array(r.get("items", [])),
		"splits": PbJson.as_array(r.get("splits", [])),
		"ranked": true,
		"mode": str(r.get("mode", "standard")),
	}
	var runs: Array = PbJson.as_array(store.get("runs", []))
	runs.insert(0, rec)
	if runs.size() > 200:
		runs.resize(200)
	store["runs"] = runs
	var counters: Dictionary = store["counters"]
	counters["runs"] = int(counters.get("runs", 0)) + 1
	counters["kills"] = int(counters.get("kills", 0)) + int(r.get("kills", 0))
	counters["maxTime"] = maxi(int(counters.get("maxTime", 0)), int(roundf(float(r.get("time", 0.0)))))
	counters["maxLevel"] = maxi(int(counters.get("maxLevel", 0)), int(r.get("level", 0)))
	counters["playtime"] = int(counters.get("playtime", 0)) + int(roundf(float(r.get("time", 0.0))))
	counters["bosses"] = int(counters.get("bosses", 0)) + int(r.get("bosses", 0))
	counters["legendaries"] = int(counters.get("legendaries", 0)) + int(r.get("legendaries", 0))
	var econ := PbJson.as_dict(r.get("econ", {}))
	if econ.has("gold"):
		counters["gold"] = int(counters.get("gold", 0)) + int(econ["gold"])
	# Stardust: the offline build is generous (api-core.js line 256).
	var gain := maxi(1, int(roundf(float(r.get("kills", 0)) * 0.5 + float(r.get("time", 0.0)) * 0.2)))
	store["stardust"] = int(store.get("stardust", 0)) + gain
	store["totalStardust"] = int(store.get("totalStardust", 0)) + gain
	# Bonk coins per boss killed (offline behaviour, README "打 Boss 直接给 1~4").
	var bosses := int(r.get("bosses", 0))
	if bosses > 0:
		var bonk := bosses * (1 + randi() % 3)
		store["bonk"] = int(store.get("bonk", 0)) + bonk
		store["totalBonk"] = int(store.get("totalBonk", 0)) + bonk
	# api-core.js applyRunResult() stops at the stardust/bonk rewards: it does not
	# touch `research`, so neither does this port (keeps saves in lock-step).
	save()
	return {"gain": gain, "record": rec}


# ------------------------------------------------------------------- lab
func lab(id: String) -> int:
	return int(PbJson.as_dict(store.get("lab", {})).get(id, 0))


## POST /lab/<id>/buy in api-core.js: cost = 10 * (current + 1).
func lab_buy(id: String) -> Dictionary:
	load_profile()
	var max_rank := lab_max(id)
	var cur := lab(id)
	if cur >= max_rank:
		return {"ok": false, "error": "MAX"}
	var cost := 10 * (cur + 1)
	if int(store.get("stardust", 0)) < cost:
		return {"ok": false, "error": "NO_STARDUST"}
	store["stardust"] = int(store["stardust"]) - cost
	PbJson.as_dict(store["lab"])[id] = cur + 1
	save()
	return {"ok": true, "profile": store, "cost": cost}


## The stat deltas the lab grants at run start (api-core labStats() equivalent).
## Mapping of upgrade id -> stat delta was read off the bundle's stat table
## (offset 812367: maxHp/regen/armor/evasion/moveSpeed/damage/... names);
## the per-level magnitude is our estimate -- TODO(verify) against live values.
func lab_deltas() -> Dictionary:
	var out := {}
	out["damage"] = 0.06 * lab("dmg")
	out["maxHp"] = 8.0 * lab("hp")
	out["moveSpeed"] = 0.03 * lab("spd")
	out["xpGain"] = 0.08 * lab("xp")
	out["gold"] = 0.08 * lab("gold")
	out["luck"] = 3.0 * lab("luck")
	out["pickupRange"] = 0.8 * lab("magnet")
	out["regen"] = 0.12 * lab("regen")
	out["armor"] = 2.0 * lab("armor")
	out["area"] = 0.06 * lab("area")
	out["critChance"] = 0.015 * lab("crit")
	out["attackSpeed"] = 0.05 * lab("atkspd")
	out["moveSlots"] = 1 if lab("slot-move") > 0 else 0
	out["vitaminSlots"] = lab("slot-vit")
	return out


# ------------------------------------------------------------------- api router
## Port of api-core.js handle(): same routes, same payloads. The UI calls this
## instead of talking to a server, exactly like the offline web build does.
func handle(method: String, path: String, query: Dictionary = {}, body: Dictionary = {}) -> Dictionary:
	load_profile()
	if method == "GET" and path == "/status":
		return {
			"ok": true, "build": _build_id(), "version": _version(), "offline": true,
			"maintenance": {"on": false, "msg": ""}, "bypass": false,
			"registration": {"inviteOnly": false, "open": true},
			"players": 1, "online": 1, "server": "godot-port",
		}
	if method == "GET" and path == "/version.json":
		return {"build": _build_id(), "version": _version()}
	if method == "POST" and path == "/auth/guest":
		guest_session = true
		if str(store.get("name", "")).is_empty() or store.get("name") == "Entrenador":
			store["name"] = "Invitado%04d" % (randi() % 10000)
		save()
		return _account()
	if method == "GET" and path == "/auth/me":
		return _account()
	if method == "GET" and path == "/auth/name":
		var name := str(query.get("name", "")).strip_edges()
		var ok := name.length() >= 3
		return {"ok": ok, "free": ok, "taken": not ok, "available": ok, "name": name}
	if method == "POST" and path in ["/auth/register", "/auth/login", "/auth/guest-name"]:
		var new_name := str(body.get("name", "")).strip_edges()
		if not new_name.is_empty():
			store["name"] = new_name.substr(0, mini(16, new_name.length()))
		guest_session = false
		save()
		var acc := _account()
		acc["guest"] = false
		return acc
	if method == "POST" and path == "/auth/logout":
		return {"ok": true}
	if method == "GET" and path == "/profile":
		return {"now": _now_ms(), "profile": store}
	if method == "PUT" and path == "/profile/prefs":
		for key in ["lastSpecies", "lastBiome", "avatar", "frame", "title"]:
			if body.has(key):
				store[key] = body[key]
		if body.get("settings") is Dictionary:
			for key in PbJson.as_dict(body["settings"]).keys():
				store["settings"][key] = body["settings"][key]
		if body.get("skins") is Array:
			store["skins"] = body["skins"]
		if body.get("team") is Array:
			store["team"] = body["team"]
		save()
		return {"ok": true, "profile": store}
	if method == "POST" and path == "/profile/starter":
		var id := int(body.get("id", 0))
		if id <= 0:
			id = 4
		store["starter"] = id
		store["lastSpecies"] = id
		store["team"] = _union(store["team"], [id])
		store["captured"] = _union(store["captured"], [id])
		store["seen"] = _union(store["seen"], [id])
		# api-core.js:342-343: the first starter replaces the numeric league
		# counter with an array of starter ids.
		if typeof(store.get("league")) != TYPE_ARRAY:
			store["league"] = []
		var league: Array = store["league"]
		if not league.has(id):
			league.append(id)
		save()
		return {"ok": true, "profile": store}
	if method == "POST" and path == "/runs/start":
		return {"id": "run-%x" % (randi()), "seed": int(randi()), "started": _now_ms()}
	if method == "POST" and path.begins_with("/runs/") and path.ends_with("/finish"):
		var run_id := path.split("/")[2]
		var res := apply_run_result(PbJson.as_dict(body.get("result", body)), run_id)
		return {"ok": true, "record": res["record"], "reward": {"stardust": res["gain"]}}
	if method == "POST" and (path.ends_with("/checkpoint") or path.ends_with("/abandon")):
		return {"ok": true}
	if method == "GET" and path == "/runs":
		return {"runs": PbJson.as_array(store.get("runs", [])).slice(0, 50)}
	if method == "POST" and path.begins_with("/lab/") and path.ends_with("/buy"):
		return lab_buy(path.split("/")[2])
	if method == "GET" and path in ["/quests", "/tasks"]:
		return {"list": [], "claimed": []}
	if method == "GET" and (path.begins_with("/seasons") or path.begins_with("/events") \
			or path.begins_with("/leaderboard") or path.begins_with("/news")):
		return {"list": [], "ok": true}
	if method in ["POST", "PUT", "PATCH"]:
		return {"ok": true}
	return {"ok": true}


func _account() -> Dictionary:
	return {
		"id": "local-1",
		"name": store.get("name", "Entrenador"),
		"guest": guest_session,
		"created": store.get("created", 0),
		"token": "pb-godot-local",
	}


func _build_id() -> String:
	return str(_pb_meta().get("build", "godot-port"))


func _version() -> String:
	return str(_pb_meta().get("version", "0.0.0"))


static var _meta_cache := {}


func _pb_meta() -> Dictionary:
	if _meta_cache.is_empty():
		var raw := _read_text("res://data/pb/port_meta.json")
		if raw != null:
			var parsed := JSON.parse_string(raw)
			if parsed is Dictionary:
				_meta_cache = parsed
		if _meta_cache.is_empty():
			_meta_cache = {"build": "godot-port", "version": "unknown"}
	return _meta_cache


# ------------------------------------------------------------------- backups
func _stamp() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d-%02d%02d%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]


## Backup ids need sub-second resolution: unlike a human clicking the web panel,
## a test loop can create several snapshots in the same second, and colliding ids
## would silently overwrite (the web build has the same second-granularity key).
func _stamp_unique() -> String:
	_backup_seq += 1
	return "%s-%03d" % [_stamp(), _backup_seq % 1000]


func auto_backup() -> String:
	var raw := _read_text(_path())
	if raw == null or raw.is_empty():
		return ""
	var id := BACKUP_PREFIX + _stamp_unique()
	if not _write_text("user://%s.json" % id, raw):
		return ""
	_prune_backups()
	return id


func list_backups() -> Array:
	var out := []
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with(BACKUP_PREFIX) and f.ends_with(".json"):
			var id := f.trim_suffix(".json")
			var text := _read_text("user://%s" % f)
			var sum := {}
			if text != null:
				var parsed := PbJson.as_dict(JSON.parse_string(text))
				var p := PbJson.as_dict(parsed.get("profile", parsed))
				sum = {"name": p.get("name"), "stardust": p.get("stardust"),
					"league": p.get("league") if not (p.get("league") is Array) else PbJson.as_array(p["league"]).size()}
			out.append({"id": id, "time": id.trim_prefix(BACKUP_PREFIX), "summary": sum})
	out.sort_custom(func(a, b): return str(a["time"]) > str(b["time"]))
	return out


func _prune_backups() -> void:
	var ids := []
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with(BACKUP_PREFIX) and f.ends_with(".json"):
			ids.append(f)
	ids.sort()
	while ids.size() > MAX_BACKUPS:
		var oldest := str(ids.pop_front())
		dir.remove(oldest)


func restore_backup(id: String) -> bool:
	var text := _read_text("user://%s.json" % id)
	if text == null:
		return false
	return import_text(text) == "ok"


# ------------------------------------------------------------------- export/import
func summary() -> Dictionary:
	var text := _read_text(_path())
	if text == null:
		return {}
	var parsed := PbJson.as_dict(JSON.parse_string(text))
	var p := PbJson.as_dict(parsed.get("profile", parsed))
	var league = p.get("league", 0)
	return {
		"name": p.get("name", "?"),
		"starter": p.get("starter", 0),
		"stardust": p.get("stardust", 0),
		"bonk": p.get("bonk", 0),
		"league": PbJson.as_array(league).size() if league is Array else int(league),
		"captured": PbJson.as_array(p.get("captured", [])).size(),
		"runs": PbJson.as_array(p.get("runs", [])).size(),
		"savedAt": parsed.get("savedAt", null),
	}


func export_string() -> String:
	var text := _read_text(_path())
	if text == null or text.is_empty():
		save()
		text = _read_text(_path())
	var parsed := PbJson.as_dict(JSON.parse_string(text))
	parsed["__exported"] = Time.get_datetime_string_from_system(true)
	parsed["__version"] = _version()
	return JSON.stringify(parsed)


func export_to_file(path: String = "") -> String:
	var s := summary()
	var target := path
	if target.is_empty():
		var who := str(s.get("name", "save")).replace(" ", "-")
		target = "user://pokebonk-save-%s-%s.json" % [who, _stamp()]
	_write_text(target, export_string())
	return target


## Port of importFromText(): tolerates pasted text with surrounding junk and
## backs up the current save first.
func import_text(value: String) -> String:
	if value == null or value.strip_edges().is_empty():
		return "空内容"
	var s := value.strip_edges()
	if not s.begins_with("{"):
		var i := s.find("{")
		var j := s.rfind("}")
		if i >= 0 and j > i:
			s = s.substr(i, j - i + 1)
	var parsed := JSON.parse_string(s)
	if parsed == null:
		return "JSON 解析失败"
	var obj := PbJson.as_dict(parsed)
	var p = obj.get("profile", obj)
	if not (p is Dictionary) or (p as Dictionary).is_empty():
		return "格式不对"
	if not (p as Dictionary).has("name") and not (p as Dictionary).has("stardust"):
		return "看起来不是存档"
	auto_backup()
	store = normalize(p)
	guest_session = bool(obj.get("guest", false))
	save()
	return "ok"


func stale_seconds() -> float:
	var s := summary()
	if s.is_empty() or s.get("savedAt") == null:
		return 0.0
	return maxf(0.0, (float(Time.get_unix_time_from_system() * 1000.0) - float(s["savedAt"])) / 1000.0)


# ------------------------------------------------------------------- io helpers
func _read_text(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_string(path)


func _write_text(path: String, content: String) -> bool:
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		push_error("Save: cannot open %s for writing (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	fh.store_string(content)
	fh.close()
	return true


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
