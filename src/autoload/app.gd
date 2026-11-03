extends Node
## Scene router + session-level state (the port's counterpart of the web app's
## single-page view switching).

const SCENES := {
	"menu": "res://scenes/MainMenu.tscn",
	"dex": "res://scenes/Pokedex.tscn",
	"lab": "res://scenes/Lab.tscn",
	"fusion": "res://scenes/FusionMachine.tscn",
	"run": "res://scenes/Run.tscn",
	"save": "res://scenes/SaveManager.tscn",
}

var locale := "en"
var last_result: Dictionary = {}
var last_settle: Dictionary = {}
var selected_species := 1

# Screenshot hook used by scripts/shot.sh: `Godot --path . res://scenes/X.tscn --
# --pb-shot /tmp/x.png` renders the scene and exits, which is how the UI port is
# visually checked without a human in the loop.
var _shot_path := ""
var _shot_frames := 0


func _ready() -> void:
	locale = _detect_locale()
	TranslationServer.set_locale(locale)
	# The web keeps the light/dark choice in localStorage('pokebonk.theme'); the
	# port rides it along as an extra settings key (see Save prefs merge).
	_apply_theme_mode()
	# One Theme instance for every screen; children inherit it from the window.
	get_tree().root.theme = PbTheme.build()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--pb-shot" and i + 1 < args.size():
			_shot_path = String(args[i + 1])


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
	var mode := String(settings.get("theme", "light"))
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
	var path := String(SCENES.get(view, SCENES["menu"]))
	get_tree().change_scene_to_file(path)
	# change_scene resets nothing about the window theme, but re-assert it so a
	# scene created before the first frame still inherits the ported Theme.
	await get_tree().process_frame
	get_tree().root.theme = PbTheme.build()


func back_to_menu() -> void:
	last_result = {}
	goto("menu")


func _detect_locale() -> String:
	var tag := TranslationServer.get_locale().split("_")[0]
	for available in ["en", "zh", "zht", "ja", "ko", "fr", "pt", "ru"]:
		if tag == available:
			return available
	return "en"


func t(kind: String, id: Variant, fallback: String = "") -> String:
	var localized := PbData.localized_name(kind, id, locale)
	if not localized.is_empty():
		return localized
	return fallback if not fallback.is_empty() else String(id)
