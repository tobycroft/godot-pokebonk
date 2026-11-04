extends Node
## Scene router + session-level state (the port's counterpart of the web app's
## single-page view switching).
##
## i18n mirrors pokebonk-web's i18n chunk (assets/i18n-*.js):
##   - the UI dictionary is keyed by the Spanish source text (`c("Daño")`),
##   - per-language chunks live in data/i18n/ui/<lang>.json (exported by
##     tools/export_web_locales.mjs),
##   - a missing key falls back to the key itself (i.e. the Spanish original),
##   - `es` is the identity dictionary, so it has no file.
## Entity names (pokemon/moves/abilities/items/types) still come from
## data/i18n/<lang>.json through `t()`, matching `Localize.localize()` in the web.

const SCENES := {
	"menu": "res://scenes/MainMenu.tscn",
	"dex": "res://scenes/Pokedex.tscn",
	"lab": "res://scenes/Lab.tscn",
	"fusion": "res://scenes/FusionMachine.tscn",
	"run": "res://scenes/Run.tscn",
	"save": "res://scenes/SaveManager.tscn",
}

## Language list, verbatim from the web's i18n chunk (id / name / locale tag / short).
const LOCALES := [
	{"id": "es", "name": "Español", "locale": "es-ES", "short": "ES"},
	{"id": "en", "name": "English", "locale": "en-US", "short": "EN"},
	{"id": "pt", "name": "Português", "locale": "pt-BR", "short": "PT"},
	{"id": "fr", "name": "Français", "locale": "fr-FR", "short": "FR"},
	{"id": "ja", "name": "日本語", "locale": "ja-JP", "short": "JA"},
	{"id": "zh", "name": "简体中文", "locale": "zh-CN", "short": "ZH"},
	{"id": "zht", "name": "繁體中文", "locale": "zh-TW", "short": "繁"},
	{"id": "ko", "name": "한국어", "locale": "ko-KR", "short": "KO"},
	{"id": "ru", "name": "Русский", "locale": "ru-RU", "short": "RU"},
]

## Stored choice, mirroring the web's localStorage key `pokebonk.lang`. An empty
## file means "Automatic" (the web's null option): follow the OS locale.
const LANG_FILE := "user://pb.lang"

var locale := "zh"
var last_result: Dictionary = {}
var last_settle: Dictionary = {}
var selected_species := 1

var _ui: Dictionary = {}
var _ui_loaded := false

# Screenshot hook used by scripts/shot.sh: `Godot --path . res://scenes/X.tscn --
# --pb-shot /tmp/x.png` renders the scene and exits, which is how the UI port is
# visually checked without a human in the loop.
var _shot_path := ""
var _shot_frames := 0


func _ready() -> void:
	locale = _detect_locale()
	TranslationServer.set_locale(_locale_tag(locale))
	# The web keeps the light/dark choice in localStorage('pokebonk.theme'); the
	# port rides it along as an extra settings key (see Save prefs merge).
	_apply_theme_mode()
	# One Theme instance for every screen; children inherit it from the window.
	get_tree().root.theme = PbTheme.build()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--pb-shot" and i + 1 < args.size():
			_shot_path = str(args[i + 1])


## Switch the design tokens to light/dark and rebuild the shared Theme, then
## re-assert it on the window so every screen repaints (PbTheme caches clear).
func set_theme_mode(mode: String) -> void:
	var settings: Dictionary = PbJson.as_dict(Save.store.get("settings", {}))
	settings["theme"] = mode
	Save.handle("PUT", "/profile/prefs", {}, {"settings": settings})
	_apply_theme_mode()
	get_tree().root.theme = PbTheme.build()


func _apply_theme_mode() -> void:
	var settings: Dictionary = PbJson.as_dict(Save.store.get("settings", {}))
	var mode := str(settings.get("theme", "light"))
	if mode != "dark":
		mode = "light"
	PbTheme.set_mode(mode)


func _process(_delta: float) -> void:
	if _shot_path.is_empty():
		return
	_shot_frames += 1
	# Wait for fonts/textures to settle, then capture once and quit.
	if _shot_frames < 30:
		return
	var image := get_tree().root.get_texture().get_image()
	var err := image.save_png(_shot_path)
	print("[shot] %s -> %s (%dx%d) err=%d" % [_shot_path, "saved" if err == OK else "failed",
		image.get_width(), image.get_height(), err])
	get_tree().quit(0)


func goto(view: String) -> void:
	var path := str(SCENES.get(view, SCENES["menu"]))
	get_tree().change_scene_to_file(path)
	# change_scene resets nothing about the window theme, but re-assert it so a
	# scene created before the first frame still inherits the ported Theme.
	await get_tree().process_frame
	get_tree().root.theme = PbTheme.build()
	_fade_in()


## `.screen{animation:.25s ease-out fadeIn}`: the incoming view paints over the page
## colour and fades in. A CanvasLayer keeps this working for Node3D roots (Run).
func _fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var veil := ColorRect.new()
	veil.color = PbTheme.page_bg()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(veil)
	get_tree().root.add_child(layer)
	var tw := veil.create_tween()
	tw.tween_property(veil, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)


func back_to_menu() -> void:
	last_result = {}
	goto("menu")


## Language selection mirrors the web: `pokebonk.lang` holds the id, while an
## absent value means Automatic (navigator in the web, OS locale here).
func _detect_locale() -> String:
	var stored := _stored_locale()
	if not stored.is_empty():
		return stored
	return _system_locale()


func _stored_locale() -> String:
	if not FileAccess.file_exists(LANG_FILE):
		return ""
	var raw := FileAccess.get_file_as_string(LANG_FILE).strip_edges().to_lower()
	return raw if is_valid_locale(raw) else ""


## Public view of the persisted choice ("" = Automatic), used by the settings row.
func stored_locale() -> String:
	return _stored_locale()


func _system_locale() -> String:
	var raw := OS.get_locale().replace("-", "_").to_lower()
	var parts := raw.split("_")
	var base := parts[0]
	if base == "zh" and parts.size() > 1 and parts[1] in ["tw", "hk", "mo", "hant"]:
		return "zht"
	return base if is_valid_locale(base) else "en"


func is_valid_locale(id: String) -> bool:
	for row in LOCALES:
		if str(PbJson.as_dict(row).get("id", "")) == id:
			return true
	return false


func locale_tag(id: String) -> String:
	return _locale_tag(id)


func _locale_tag(id: String) -> String:
	for row in LOCALES:
		var entry := PbJson.as_dict(row)
		if str(entry.get("id", "")) == id:
			return str(entry.get("locale", id))
	return id


## Persist the choice and rebuild the current screen, matching the web's
## `ZN()` (write + location.reload()). Pass "" for Automatic.
func set_locale(id: String) -> void:
	var chosen := id if is_valid_locale(id) else ""
	var f := FileAccess.open(LANG_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(chosen)
		f = null
	locale = _detect_locale()
	TranslationServer.set_locale(_locale_tag(locale))
	_ui.clear()
	_ui_loaded = false
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


func tr_lang() -> String:
	return locale


## `c()` from the web i18n chunk: look up a UI string by its Spanish source text,
## then apply `{name}` interpolation. A missing key returns the key unchanged
## (the Spanish original), exactly like the web.
func ui(key: String, vars: Dictionary = {}) -> String:
	if not _ui_loaded:
		_ui_loaded = true
		if locale != "es":
			_ui = PbJson.as_dict(PbJson.read_json("res://data/i18n/ui/%s.json" % locale))
	var text := str(_ui.get(key, key))
	if vars.is_empty():
		return text
	var out := text
	for name in vars.keys():
		out = out.replace("{%s}" % str(name), str(vars[name]))
	return out


## Entity-name lookup (`App.t("pokemon", 4)`), backed by data/i18n/<lang>.json.
## Keeps the web's behaviour: a missing entry keeps the Spanish table value,
## which is what `fallback` (or the raw id) should be.
func t(kind: String, id: Variant, fallback: String = "") -> String:
	var localized := PbData.localized_name(kind, id, locale)
	if not localized.is_empty():
		return localized
	return fallback if not fallback.is_empty() else str(id)
