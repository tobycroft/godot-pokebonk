extends Control
## Main menu, rebuilt node-for-node from the web build's start screen (v0.8.59,
## mirrored in pokebonk-web). The absolute layout follows the `.mm` rules:
##   .mm-top    fixed top-left/top-right pills + trainer bar
##   .mm-left   left gutter, width `--mm-w`, top 52%, translateY(-50%)
##   .mm-season right inset `clamp(22,3vw,56)`, width `clamp(340,26vw,400)`,
##              max-height `min(640, 100dvh - 170)`
##   .mm-foot   absolute bottom:10, white 12/800 + shadow
## Every size/colour comes from the extracted CSS tokens (PbTheme); the `_on_resized`
## handler re-applies the `@media (max-height:760px)` compact set so 720p never overflows,
## and the left column is wrapped in a ScrollContainer as the fallback for shorter windows.
##
## Port-only extras (derived stats, move list, sliders, locale picker, recent runs) live
## inside the `Ajustes` modal, which is where the web keeps its own secondary content.
##
## Data flows through the ported API routes exactly as the web client does:
## GET /profile, POST /profile/starter, PUT /profile/prefs.


const SKEW := 0.10510423526  # tan(6deg): `.mm-item{transform:skew(-6deg)}`

var _wallet: HBoxContainer
var _wallet_name: Label
var _wallet_sub: Label
var _wallet_avatar: TextureRect
var _play_sub: Label
var _play_title: Label
var _play_sprite: PmdSprite
var _showcase_sprite: PmdSprite
var _showcase_name: Label
var _showcase_meta: Label
var _showcase_types: HBoxContainer
var _stat_grid: GridContainer
var _moves_box: VBoxContainer
var _recent: VBoxContainer
var _settings_scrim: PanelContainer
var _starter := 4

# --- `.mm` layout nodes (sizes applied in _on_resized) ---
var _mm: Control
var _top_row_ctrl: HBoxContainer
var _left_area: Control
var _left_scroll: ScrollContainer
var _left_col: VBoxContainer
var _brand: Control
var _logo_node: Control
var _brand_word: Control
var _brand_poke: Label
var _brand_bonk: Label
var _brand_ball: TextureRect
var _brand_ver: PanelContainer
var _nav_box: VBoxContainer
var _modes_row: HBoxContainer
var _pair_box: VBoxContainer
var _today_row: HBoxContainer
var _tiles_row: HBoxContainer
var _small_row: HBoxContainer
var _season_wrap: Control
var _season_card: PanelContainer
var _season_box: VBoxContainer
var _footer: VBoxContainer
var _legal: Label
var _hint_row: HBoxContainer

var _tile_store: Array = []
var _anim_items: Array = []
var _anim_i := 0
var _compact := false
var _viewport := Vector2(1280, 720)


func _ready() -> void:
	UI.fill(self)
	var root := UI.screen()
	add_child(root)
	UI.fill(root)
	_mm = Control.new()
	_mm.name = "MM"
	root.add_child(_mm)
	UI.fill(_mm)

	_build_top()
	_build_left()
	_build_season()
	_build_footer()

	resized.connect(_on_resized)
	_on_resized()

	_build_settings_modal()

	_starter = int(Save.store.get("starter", 0))
	if _starter <= 0:
		_starter = int(Save.store.get("lastSpecies", 4))
	Audio.apply_profile_settings(PbJson.as_dict(Save.store.get("settings", {})))
	Audio.play_music("menu")
	refresh()
	_play_entrance.call_deferred()
	if "--pb-debug" in OS.get_cmdline_user_args():
		_debug_layout.call_deferred()
	# QA hook for screenshots: open the starter picker immediately.
	if "--pb-starter-demo" in OS.get_cmdline_user_args():
		_open_starter_picker.call_deferred()
	if "--pb-settings-demo" in OS.get_cmdline_user_args():
		_open_settings.call_deferred()


func _debug_layout() -> void:
	print("DBG self.size=", size, " viewport=", get_viewport_rect().size)
	for node in _collect():
		print("DBG  ", node.name, " ", node.get_class(), " size=", node.size, " min=", node.get_combined_minimum_size())


func _collect() -> Array:
	var out := []
	var stack := [self]
	while stack:
		var n = stack.pop_back()
		out.append(n)
		stack.append_array(n.get_children())
	return out


func _unhandled_input(event: InputEvent) -> void:
	# Edge-triggered (the web's Esc): close the top-most overlay, else leave the page.
	if not (event is InputEventKey) or not event.pressed or event.keycode != KEY_ESCAPE:
		return
	if _settings_scrim != null and _settings_scrim.visible:
		_close_settings()
	elif _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
		_picker = null
	else:
		get_tree().quit()


# ------------------------------------------------------------------- layout
## Re-applies the `.mm` clamps and the `@media (max-height:760px)` compact set.
func _on_resized() -> void:
	_viewport = get_viewport_rect().size
	var vw := _viewport.x
	var vh := _viewport.y
	_compact = vh <= 760.0

	var gutter := PbTheme.gutter(vw)                      # clamp(22,5vw,84)
	var mm_w := minf(520.0, vw - 2.0 * gutter)           # --mm-w
	var brand_fs := clampf(48.0, 9.0 * vh / 100.0, 70.0) if _compact \
		else clampf(72.0, 9.5 * vw / 100.0, 156.0)

	# Top bar: absolute top:18 left:22 right:22.
	_top_row_ctrl.offset_left = 22.0
	_top_row_ctrl.offset_right = -22.0
	_top_row_ctrl.offset_top = 18.0
	_top_row_ctrl.offset_bottom = 18.0

	# Left column area, centred like top:52% / translateY(-50%).
	_left_area.offset_left = gutter
	_left_area.offset_right = gutter + mm_w
	_left_area.offset_top = 84.0
	_left_area.offset_bottom = -46.0
	_left_col.custom_minimum_size = Vector2(mm_w, 0)
	_left_col.add_theme_constant_override("separation", 12 if _compact else 18)

	_layout_brand(brand_fs, mm_w)
	_nav_box.add_theme_constant_override("separation", 10 if _compact else 12)
	_modes_row.custom_minimum_size.y = 100.0 if _compact \
		else clampf(14.0 * vh / 100.0, 100.0, 124.0)
	_today_row.custom_minimum_size.y = 64.0 if _compact else 72.0
	_layout_tiles(mm_w)

	# Season column: right:clamp(22,3vw,56), width:clamp(340,26vw,400),
	# max-height:min(640,100dvh - 170).
	var season_w := clampf(26.0 * vw / 100.0, 340.0, 400.0)
	var season_inset := clampf(3.0 * vw / 100.0, 22.0, 56.0)
	var season_cap := minf(640.0, vh - 170.0)
	_season_wrap.offset_left = -(season_w + season_inset)
	_season_wrap.offset_right = -season_inset
	_season_wrap.offset_top = -season_cap * 0.5
	_season_wrap.offset_bottom = season_cap * 0.5
	_season_card.custom_minimum_size = Vector2(season_w, 0)
	_season_wrap.visible = vw >= 1000.0

	# `.mm-foot{position:absolute;bottom:10px;left:0;right:0}`.
	_footer.offset_left = 0.0
	_footer.offset_right = 0.0
	_footer.offset_bottom = -10.0
	_footer.offset_top = -10.0
	_legal.custom_minimum_size.x = minf(980.0, vw - 48.0)


## `.logo-word` font clamp + ball/version placements.
func _layout_brand(fs: float, mm_w: float) -> void:
	for label in [_brand_poke, _brand_bonk]:
		label.add_theme_font_size_override("font_size", int(fs))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_constant_override("shadow_offset_y", 7)
	var sz1 := _brand_poke.get_combined_minimum_size()
	var sz2 := _brand_bonk.get_combined_minimum_size()
	_brand_poke.position = Vector2.ZERO
	_brand_bonk.position = Vector2(sz1.x, 0.0)
	var word_h := maxf(sz1.y, sz2.y)
	var word_w := sz1.x + sz2.x
	_brand_word.position = Vector2.ZERO
	_brand_word.size = Vector2(word_w, word_h)
	_brand_word.pivot_offset = _brand_word.size * 0.5
	_brand_word.rotation = deg_to_rad(-3.0)
	# `.logo-ball{width:.6em;top:-.18em;right:-.42em}`.
	_brand_ball.position = Vector2(word_w - fs * 0.18, -fs * 0.18)
	_brand_ball.size = Vector2(fs * 0.6, fs * 0.6)
	_brand_ball.pivot_offset = _brand_ball.size * 0.5
	_logo_node.size = Vector2(word_w, word_h)
	_brand_ver.reset_size()
	_brand_ver.position = Vector2(8.0, word_h - 2.0)
	_brand_ver.pivot_offset = _brand_ver.size * 0.5
	_brand.custom_minimum_size = Vector2(mm_w, word_h + 22.0)


## `.mm-item.tile` padding/icon/font set: title size = min(14.5, width / (n * .66)).
func _layout_tiles(mm_w: float) -> void:
	var tile_w := (mm_w - 4.0 * 8.0) / 5.0
	var pad_top := 8 if _compact else 10
	var pad_bottom := 11 if _compact else 13
	var icon_px := 40 if _compact else 44
	for rec in _tile_store:
		var mc: MarginContainer = rec["mc"]
		mc.add_theme_constant_override("margin_top", pad_top)
		mc.add_theme_constant_override("margin_bottom", pad_bottom)
		var ic: PanelContainer = rec["ic"]
		ic.custom_minimum_size = Vector2(icon_px, icon_px)
		var font := int(minf(14.5, tile_w / (float(rec["n"]) * 0.66)))
		font = maxi(font, 10)
		var title: Label = rec["title"]
		title.add_theme_font_size_override("font_size", font)
		var tile: Control = rec["tile"]
		tile.custom_minimum_size.y = float(pad_top + icon_px + 3 + int(font * 1.20) + 3 + 14 + pad_bottom)


# ------------------------------------------------------------------- header
## `.mm-top`: the fullscreen pill on the left (the language pill stays hidden), trainer right.
func _build_top() -> void:
	_top_row_ctrl = UI.hbox(10)
	_top_row_ctrl.name = "MMTop"
	_top_row_ctrl.grow_vertical = Control.GROW_DIRECTION_END
	_mm.add_child(_top_row_ctrl)
	_top_row_ctrl.set_anchors_preset(Control.PRESET_TOP_WIDE)

	var fs := UI.small_button("⛶", _toggle_fullscreen, "blue")
	fs.name = "FullscreenPill"
	_top_row_ctrl.add_child(fs)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_row_ctrl.add_child(spacer)
	_top_row_ctrl.add_child(_trainer_bar())


## `.trainer`: avatar + name + subtitle, then the wallet pills and the two actions.
func _trainer_bar() -> Control:
	var bar := UI.panel(10)
	bar.name = "TrainerBar"
	var row := UI.hbox(10)
	bar.add_child(row)

	_wallet_avatar = TextureRect.new()
	_wallet_avatar.custom_minimum_size = Vector2(44, 44)
	_wallet_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallet_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_wallet_avatar)

	var who := UI.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet_name = UI.label("?", 17, PbTheme.ink())
	_wallet_name.add_theme_font_override("font", PbTheme.font("title"))
	who.add_child(_wallet_name)
	_wallet_sub = UI.dim("")
	who.add_child(_wallet_sub)
	row.add_child(who)

	_wallet = UI.hbox(6)
	row.add_child(_wallet)
	row.add_child(UI.button(App.ui("Guardar en cuenta"), _ask_account, false, "blue", true))
	row.add_child(UI.button(App.ui("Salir"), _quit, false, "blue", true))
	return bar


func _quit() -> void:
	Audio.sfx("ui")
	get_tree().quit()


func _ask_account() -> void:
	# The mirror's backend has no account flow for guests; the web offers the same button and
	# the port keeps it honest rather than inventing a signup.
	UI.toast(self, "离线镜像：游客存档保存在本地，用「存档管理」导出")
	Audio.sfx("deny")


func _toggle_fullscreen() -> void:
	var win := get_window()
	win.mode = Window.MODE_FULLSCREEN if win.mode != Window.MODE_FULLSCREEN else Window.MODE_MAXIMIZED


# ------------------------------------------------------------------- wordmark
## `.logo.hero`: `Poké` + yellow `Bonk` with 4px stroke, 7px shadow, -3deg and the
## 3.4s float; the `.logo-ver` capsule sits at `top:100%;left:8px`.
func _build_left() -> void:
	_left_area = Control.new()
	_left_area.name = "MMLeft"
	_left_area.anchor_top = 0.0
	_left_area.anchor_bottom = 1.0
	_mm.add_child(_left_area)

	_left_scroll = UI.scroll()
	_left_scroll.name = "MMLeftScroll"
	_left_area.add_child(_left_scroll)
	UI.fill(_left_scroll)

	# CenterContainer keeps the 52% vertical centring; it grows past the viewport
	# when the content is taller, which is what makes the ScrollContainer scroll.
	var center := CenterContainer.new()
	center.name = "MMLeftCenter"
	_left_scroll.add_child(center)

	_left_col = UI.vbox(18)
	_left_col.name = "MMLeftColumn"
	center.add_child(_left_col)

	_left_col.add_child(_brand_block())

	_nav_box = UI.vbox(12)
	_nav_box.name = "MMNav"
	_left_col.add_child(_nav_box)
	_build_nav()


func _brand_block() -> Control:
	_brand = Control.new()
	_brand.name = "Logo"
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_node = Control.new()
	_logo_node.name = "LogoInner"
	_logo_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand.add_child(_logo_node)

	_brand_word = Control.new()
	_brand_word.name = "LogoWord"
	_brand_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_node.add_child(_brand_word)
	_brand_poke = _brand_label("Poké", Color.WHITE)
	_brand_bonk = _brand_label("Bonk", PbTheme.css_color(PbTheme.v("--yellow", "#fc3"), Color("#fc3")))
	_brand_word.add_child(_brand_poke)
	_brand_word.add_child(_brand_bonk)
	_brand_ball = UI.icon_rect("poke-ball", 0)
	_brand_ball.name = "LogoBall"
	_brand_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_word.add_child(_brand_ball)

	_brand_ver = _version_pill()
	_logo_node.add_child(_brand_ver)

	# `.logo{animation:3.4s ease-in-out infinite float}`: translateY(-6) at 50%.
	var fl := create_tween().set_loops()
	fl.tween_property(_logo_node, "position:y", -6.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fl.tween_property(_logo_node, "position:y", 0.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# `.logo-ball{animation:2.6s ease-in-out infinite wobble}`.
	var wob := create_tween().set_loops()
	wob.tween_interval(1.664)
	wob.tween_property(_brand_ball, "rotation", deg_to_rad(-16.0), 0.156)
	wob.tween_property(_brand_ball, "rotation", deg_to_rad(14.0), 0.208)
	wob.tween_property(_brand_ball, "rotation", deg_to_rad(-6.0), 0.208)
	wob.tween_property(_brand_ball, "rotation", 0.0, 0.364)
	return _brand


## `.logo-word`: stroke 4px #2a2a7a, shadow 0 7px #2a2a7a, line-height .92.
func _brand_label(text: String, color: Color) -> Label:
	var l := UI.label(text, 72, color)
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color("#2a2a7a"))
	l.add_theme_color_override("font_shadow_color", Color("#2a2a7a"))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 7)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## `.logo-ver` + `.logo-ver b`: white capsule, orange BETA chip, 15/800.
func _version_pill() -> PanelContainer:
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
	var pill := PanelContainer.new()
	pill.name = "LogoVersion"
	pill.add_theme_stylebox_override("panel", _pill_style())
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pill.rotation = deg_to_rad(-3.0)
	pill.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_version(meta))

	var row := UI.hbox(6)
	pill.add_child(row)

	var beta_label := UI.label(App.ui("Beta").to_upper(), 12, Color.WHITE)
	beta_label.add_theme_font_override("font", PbTheme.font("title"))
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(beta_label.get_combined_minimum_size().x + 18.0, 19.0)
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.corner = 99.0
	band.setup(PbTheme.gradient("linear-gradient(#ff8a4a,#e84a2a)"), null, false)
	chip.add_child(band)
	beta_label.position = Vector2(9.0, (chip.custom_minimum_size.y - beta_label.get_combined_minimum_size().y) * 0.5)
	chip.add_child(beta_label)
	row.add_child(chip)

	var ver := UI.label("v%s" % str(meta.get("site_version", "?")), 15, PbTheme.ink2())
	ver.add_theme_font_override("font", PbTheme.font("body_bold"))
	row.add_child(ver)
	return pill


## `.logo-ver`: `background:var(--w94); border-radius:99px; padding:4px 13px 4px 5px;
## box-shadow:0 3px #2a2a7a59`. The extractor does not ship this selector, so the values
## are applied here straight from the stylesheet.
func _pill_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PbTheme.css_color(PbTheme.v("--w94", "#ffffffef"), Color("#ffffffef"))
	s.set_corner_radius_all(99)
	s.corner_detail = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.content_margin_left = 5
	s.content_margin_right = 13
	s.border_width_bottom = 3
	s.border_color = Color("#2a2a7a59")
	s.anti_aliasing = true
	return s


func _show_version(meta: Dictionary) -> void:
	Audio.sfx("ui")
	UI.toast(self, "PokéBonk v%s · build %s · Godot 移植版" % [
		str(meta.get("site_version", "?")), str(meta.get("site_build", "?"))])


# ------------------------------------------------------------------- nav
## DOM: `.mm-modes` (Play + `.mm-pair`) -> `.mm-today` -> `.mm-tiles` (5) -> `.mm-small` (4).
func _build_nav() -> void:
	_modes_row = UI.hbox(10)
	_modes_row.name = "MMModes"
	_nav_box.add_child(_modes_row)
	_modes_row.add_child(_play_tile())

	_pair_box = UI.vbox(8)
	_pair_box.name = "MMPair"
	_pair_box.custom_minimum_size = Vector2(172, 0)
	_modes_row.add_child(_pair_box)
	_register_anim(_pair_box, "dock")
	var purple := PbTheme.accent_color("purple", "c")
	_pair_box.add_child(_pair_item("moon-stone", App.ui("Supervivencia"), App.ui("Modo infinito"),
		purple, Color("#8a7aff"), Color("#5a4cd8"), Color("#2e2070"), Color("#24185a"),
		Color("#3b2a9a66"), Color("#aa96ff8c"), _start_endless))
	_pair_box.add_child(_pair_item("friends", App.ui("Cooperativo"), App.ui("Con amigos · 2-4"),
		PbTheme.accent_color("green", "c"), Color("#5ae0a0"), Color("#1fa86a"), Color("#0e6a48"),
		Color("#0b4a32"), Color("#148c5a66"), Color("#78ffbe8c"), _todo_coop))

	_today_row = UI.hbox(10)
	_today_row.name = "MMToday"
	_nav_box.add_child(_today_row)
	var event := _event_tile()
	event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event.size_flags_stretch_ratio = 1.45
	_today_row.add_child(event)
	var tasks := _tasks_tile()
	tasks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_today_row.add_child(tasks)

	_tiles_row = UI.hbox(8)
	_tiles_row.name = "MMTiles"
	_nav_box.add_child(_tiles_row)
	_tiles_row.add_child(_tile("globe", App.ui("Pokédex"), "%d/151" % int(Save.summary().get("captured", 0)),
		PbTheme.accent_color("blue", "c"), func(): App.goto("dex")))
	_tiles_row.add_child(_tile("stardust", App.ui("Laboratorio"), "%d" % int(Save.summary().get("league", 0)),
		PbTheme.accent_color("green", "c"), func(): App.goto("lab")))
	_tiles_row.add_child(_tile("crown", App.ui("Logros"), "0/228", PbTheme.accent_color("red", "c"),
		_todo_achievements))
	_tiles_row.add_child(_tile("gold", App.ui("Ranking"), "14 d", PbTheme.accent_color("yellow", "c"),
		_todo_ranking))
	_tiles_row.add_child(_tile("clan", App.ui("Clan"), App.ui("Sin clan"), PbTheme.accent_color("purple", "c"),
		_todo_clan))

	_small_row = UI.hbox(8)
	_small_row.name = "MMSmall"
	_small_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_nav_box.add_child(_small_row)
	_small_row.add_child(_mini("brush", App.ui("Ajustes"), PbTheme.accent_color("blue", "c"), _open_settings))
	_small_row.add_child(_mini("bug", App.ui("Reportar"), PbTheme.accent_color("orange", "c"), _todo_report))
	_small_row.add_child(_mini("chat", "Discord", PbTheme.accent_color("purple", "c"), _todo_discord))
	_small_row.add_child(_mini("megaphone", "Charcher", PbTheme.accent_color("green", "c"), _todo_dev))


## `.mm-item.play`: white inner ring 4px, hard red edge 6px, red glow 14px, 70px icon.
func _play_tile() -> Control:
	var cfg := {
		"name": "PlayTile",
		"grad": "linear-gradient(180deg, #ff7a7e, var(--red) 58%, var(--red-d))",
		"stripes": true,
		"strip": PbTheme.accent_color("red", "c"),
		"inset": Color("#ffffffe6"),
		"inset_width": 4,
		"hard": Color("#a81c2c"),
		"hard_offset": 6,
		"glow": Color("#e0303e66"),
		"glow_size": 20.0,
		"pad": [0, 16, 0, 14],
		"gap": 16,
		"icon": "poke-ball",
		"icon_size": 70,
		"icon_px": 52,
		"icon_bg": PbTheme.paper(),
		"icon_radius": 35,
		"icon_top_inset": 4,
		"icon_shadow": Color("#780a144d"),
		"title": App.ui("Jugar"),
		"title_size": 34,
		"title_color": Color.WHITE,
		"sub": App.ui("Modo clásico · {n}/{total} en tu Liga", {"n": 0, "total": 151}),
		"sub_size": 13,
		"sub_color": Color("#fffffff2"),
		"sub_wrap": true,
		"expand_h": true,
		"expand_v": true,
		"anim": "in",
		"tip": "",
	}
	var tile := _make_item(cfg)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_play_title = tile.get_meta("title_label")
	_play_sub = tile.get_meta("sub_label")
	_play_sprite = PmdSprite.new()
	_play_sprite.custom_minimum_size = Vector2(64, 64)
	var partner := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#ffffff38")
	ps.set_corner_radius_all(18)
	ps.set_border_width_all(2)
	ps.border_color = Color("#ffffff59")
	ps.content_margin_left = 4
	ps.content_margin_right = 4
	ps.content_margin_top = 4
	ps.content_margin_bottom = 4
	partner.add_theme_stylebox_override("panel", ps)
	partner.custom_minimum_size = Vector2(64, 64)
	partner.add_child(_play_sprite)
	var body: BoxContainer = tile.get_meta("body")
	body.add_child(partner)
	tile.pressed.connect(_start_run)
	_register_anim(tile, "in")
	return tile


## `.mm-pair>.mm-item.endless`: 34px circular icon, 13px title, 10px caption.
func _pair_item(icon_name: String, title_text: String, sub_text: String, accent: Color,
		c0: Color, c1: Color, c2: Color, hard: Color, glow: Color, icon_glow: Color,
		on_click: Callable) -> Control:
	# `linear-gradient(160deg, c0, c1 50%, c2)` from `.mm-item.endless`.
	var grad := {"type": "linear", "angle": 160.0, "stops": [
		{"color": c0, "pos": 0.0}, {"color": c1, "pos": 50.0}, {"color": c2, "pos": 100.0}]}
	var cfg := {
		"name": "PairItem",
		"grad_dict": grad,
		"stripes": true,
		"hard": hard,
		"hard_offset": 6,
		"glow": glow,
		"glow_size": 18.0,
		"pad": [4, 10, 4, 6],
		"gap": 8,
		"icon": icon_name,
		"icon_size": 34,
		"icon_px": 28,
		"icon_bg": Color("#ffffff2e"),
		"icon_radius": 17,
		"icon_ring": Color("#ffffff59"),
		"icon_glow": icon_glow,
		"title": title_text,
		"title_size": 13,
		"title_color": Color.WHITE,
		"sub": sub_text,
		"sub_size": 10,
		"sub_color": Color("#ffffffeb"),
		"expand_h": true,
		"expand_v": true,
		"anim": "dock",
		"accent": Color.WHITE,
	}
	var tile := _make_item(cfg)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if on_click.is_valid():
		tile.pressed.connect(on_click)
	return tile


## `.mm-item.event`: the `.mm-today` hero (small caption on top of the title).
func _event_tile() -> Control:
	var cfg := {
		"name": "TodayEvent",
		"grad": "linear-gradient(100deg, #2a1a4ef0, #4a2c82c7 55%, #7a4ac873)",
		"fill": Color("#3a2668"),
		"strip": Color(0, 0, 0, 0),
		"strip_grad": "linear-gradient(#ffb04a,#9a6aff)",
		"hard": Color("#24164a"),
		"hard_offset": 5,
		"glow": Color("#9a6aff66"),
		"glow_size": 16.0,
		"pad": [8, 12, 8, 10],
		"gap": 10,
		"icon": "map-boss",
		"icon_size": 50,
		"icon_px": 38,
		"icon_bg": Color("#ffffff24"),
		"icon_radius": 25,
		"icon_ring": Color("#ffd68c8c"),
		"icon_glow": Color("#ffb04a73"),
		"title": "Lavanda 之夜",
		"title_size": 15,
		"title_color": Color.WHITE,
		"sub": "活动 · 14 天后结束",
		"sub_size": 11,
		"sub_color": Color("#ffd88a"),
		"sub_before": true,
		"expand_h": true,
		"expand_v": true,
		"anim": "in",
		"tip": "",
	}
	var tile := _make_item(cfg)
	tile.pressed.connect(_todo_event)
	return tile


## `.mm-item.tasks`: striped paper card + three `.mm-pips` progress dots.
func _tasks_tile() -> Control:
	var cfg := {
		"name": "TodayTasks",
		"grad": "linear-gradient(100deg, var(--paper) 55%, var(--k-fff3d0))",
		"stripes": true,
		"strip": PbTheme.accent_color("yellow", "c"),
		"hard": Color("#1a124633"),
		"hard_offset": 4,
		"glow": Color(0, 0, 0, 0),
		"pad": [8, 12, 8, 12],
		"gap": 10,
		"icon": "mission",
		"icon_size": 44,
		"icon_px": 34,
		"icon_bg": PbTheme.mix(PbTheme.accent_color("yellow", "c"), PbTheme.paper(), 0.16),
		"icon_radius": 14,
		"title": App.ui("Encargos"),
		"title_size": 16,
		"title_color": PbTheme.ink(),
		"sub": "3 项 · 19 小时后刷新",
		"sub_size": 11,
		"sub_color": PbTheme.ink2(),
		"pips": 3,
		"expand_h": true,
		"expand_v": true,
		"anim": "in",
		"tip": "",
	}
	var tile := _make_item(cfg)
	tile.pressed.connect(_todo_tasks)
	return tile


## `.mm-item.tile`: the five vertical destination tiles.
func _tile(icon_name: String, title_text: String, value_text: String, accent: Color,
		on_click: Callable) -> Control:
	var cfg := {
		"name": "Tile",
		"vertical": true,
		"fill": PbTheme.paper(),
		"strip": accent,
		"strip_side": "bottom",
		"strip_size": 5.0,
		"hard": Color("#1a124633"),
		"hard_offset": 4,
		"glow": Color(0, 0, 0, 0),
		"pad": [10, 4, 13, 4],
		"gap": 3,
		"icon": icon_name,
		"icon_size": 44,
		"icon_px": 32,
		"icon_bg": PbTheme.mix(accent, PbTheme.paper(), 0.16),
		"icon_radius": 14,
		"title": title_text,
		"title_size": 14,
		"title_color": PbTheme.ink(),
		"sub": value_text,
		"sub_size": 11,
		"sub_color": PbTheme.ink2(),
		"expand_h": true,
		"expand_v": true,
		"anim": "in",
		"accent": accent,
		"tip": title_text,
		"responsive": true,
		"n": _tile_n(title_text),
	}
	var tile := _make_item(cfg)
	tile.custom_minimum_size = Vector2(0, 100)
	_tile_store.append({
		"tile": tile,
		"mc": tile.get_meta("margins"),
		"ic": tile.get_meta("icon_box"),
		"title": tile.get_meta("title_label"),
		"n": _tile_n(title_text),
	})
	if on_click.is_valid():
		tile.pressed.connect(on_click)
	return tile


## `.mm-item.mini`: 999px pill, 34px round icon, 15px title, no caption.
func _mini(icon_name: String, title_text: String, accent: Color, on_click: Callable) -> Control:
	var cfg := {
		"name": "Mini",
		"fill": PbTheme.paper(),
		"radius": 999.0,
		"pad": [5, 18, 5, 5],
		"gap": 8,
		"icon": icon_name,
		"icon_size": 34,
		"icon_px": 26,
		"icon_bg": PbTheme.mix(accent, PbTheme.paper(), 0.16),
		"icon_radius": 17,
		"title": title_text,
		"title_size": 15,
		"title_color": PbTheme.ink(),
		"hard": Color("#1a124633"),
		"hard_offset": 4,
		"anim": "pop",
		"accent": accent,
		"tip": title_text,
	}
	var tile := _make_item(cfg)
	tile.custom_minimum_size = Vector2(0, 44)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if on_click.is_valid():
		tile.pressed.connect(on_click)
	return tile


func _tile_n(text: String) -> float:
	var n := 0.0
	for ch in text:
		var code := ch.unicode_at(0)
		var wide := (code >= 0x3000 and code <= 0x9FFF) or (code >= 0xAC00 and code <= 0xD7AF)
		n += 1.8 if wide else 1.0
	return maxf(6.0, n)


## Shared builder for every `.mm-item` variant.
func _make_item(cfg: Dictionary) -> SkewTile:
	var tile := SkewTile.new()
	tile.name = str(cfg.get("name", "MMItem"))
	tile.fill = cfg.get("fill", PbTheme.paper())
	tile.radius = float(cfg.get("radius", 18.0))
	tile.stripes = bool(cfg.get("stripes", false))
	tile.strip = cfg.get("strip", Color(0, 0, 0, 0))
	tile.strip_side = str(cfg.get("strip_side", "left"))
	tile.strip_size = float(cfg.get("strip_size", 7.0))
	tile.inset = cfg.get("inset", Color(0, 0, 0, 0))
	tile.inset_width = float(cfg.get("inset_width", 4.0))
	tile.hard = cfg.get("hard", Color(0, 0, 0, 0))
	tile.hard_offset = int(cfg.get("hard_offset", 4))
	tile.glow = cfg.get("glow", Color(0, 0, 0, 0))
	tile.glow_size = float(cfg.get("glow_size", 14.0))
	tile.accent = cfg.get("accent", Color(0, 0, 0, 0))
	tile.tooltip_text = str(cfg.get("tip", ""))
	var grad_css := str(cfg.get("grad", ""))
	if not grad_css.is_empty():
		tile.grad = PbTheme.gradient(grad_css)
	elif cfg.has("grad_dict"):
		tile.grad = cfg["grad_dict"]
	if tile.stripes:
		tile.stripe_period = float(PbTheme.stripes().get("period", 20.0))
	var strip_css := str(cfg.get("strip_grad", ""))
	if not strip_css.is_empty():
		tile.strip_grad = PbTheme.gradient(strip_css)
	if bool(cfg.get("expand_h", false)):
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(cfg.get("expand_v", false)):
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad: Array = cfg.get("pad", [10, 14, 10, 12])
	var mc := MarginContainer.new()
	mc.name = "Margins"
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_top", int(pad[0]))
	mc.add_theme_constant_override("margin_right", int(pad[1]))
	mc.add_theme_constant_override("margin_bottom", int(pad[2]))
	mc.add_theme_constant_override("margin_left", int(pad[3]))
	tile.add_child(mc)

	var vertical := bool(cfg.get("vertical", false))
	var body: BoxContainer = UI.vbox(int(cfg.get("gap", 12))) if vertical \
		else UI.hbox(int(cfg.get("gap", 12)))
	body.name = "Body"
	mc.add_child(body)

	var icon_name := str(cfg.get("icon", ""))
	if not icon_name.is_empty():
		var box := _icon_box(cfg)
		if vertical:
			box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(box)
		tile.set_meta("icon_box", box)

	var tx := UI.vbox(2)
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not vertical:
		body.add_child(tx)

	var sub_before := bool(cfg.get("sub_before", false))
	var sub := str(cfg.get("sub", ""))
	if sub_before and not sub.is_empty():
		tx.add_child(_sub_label(cfg))
	if not str(cfg.get("title", "")).is_empty():
		var title := UI.label(str(cfg.get("title", "")), int(cfg.get("title_size", 19)),
			cfg.get("title_color", PbTheme.ink()))
		title.add_theme_font_override("font", PbTheme.font("title"))
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if vertical:
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.add_child(title)
		tile.set_meta("title_label", title)
	var pips := int(cfg.get("pips", 0))
	if pips > 0:
		tx.add_child(_pips_row(pips))
	if not sub_before and not sub.is_empty():
		tx.add_child(_sub_label(cfg))
	if vertical:
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.alignment = BoxContainer.ALIGNMENT_CENTER
		body.add_child(tx)

	tile.set_meta("margins", mc)
	tile.set_meta("body", body)
	tile.set_meta("sub_label", tx.get_child(tx.get_child_count() - 1) if not sub_before and not sub.is_empty() else null)
	return tile


func _sub_label(cfg: Dictionary) -> Label:
	var label := UI.label(str(cfg.get("sub", "")), int(cfg.get("sub_size", 12)),
		cfg.get("sub_color", PbTheme.ink2()))
	label.add_theme_font_override("font", PbTheme.font("body_bold"))
	if bool(cfg.get("sub_wrap", false)):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## `.mm-ic`: rounded/circular badge behind the item icon.
func _icon_box(cfg: Dictionary) -> PanelContainer:
	var size := float(cfg.get("icon_size", 48))
	var box := PanelContainer.new()
	box.name = "MMIcon"
	var style := StyleBoxFlat.new()
	style.bg_color = cfg.get("icon_bg", PbTheme.paper())
	var r := float(cfg.get("icon_radius", 14))
	style.set_corner_radius_all(int(r))
	if r > 20.0:
		style.corner_detail = 12
	if cfg.has("icon_ring"):
		style.set_border_width_all(int(cfg.get("icon_ring_w", 3)))
		style.border_color = cfg["icon_ring"]
	var top_inset := int(cfg.get("icon_top_inset", 0))
	if top_inset > 0:
		style.border_width_top = top_inset
		style.border_color = Color("#00000014")
	if cfg.has("icon_shadow"):
		style.shadow_color = cfg["icon_shadow"]
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 3)
	if cfg.has("icon_glow"):
		style.shadow_color = cfg["icon_glow"]
		style.shadow_size = 12
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(size, size)
	box.add_child(UI.icon_rect(str(cfg.get("icon", "")), int(cfg.get("icon_px", 30))))
	return box


## `.mm-pips`: 12px rings, the first `on` dot filled.
func _pips_row(count: int) -> HBoxContainer:
	var row := UI.hbox(4)
	row.name = "MMPips"
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for i in count:
		var dot := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.corner_detail = 8
		if i == 0:
			s.bg_color = PbTheme.accent_color("yellow", "c")
		else:
			s.bg_color = Color(0, 0, 0, 0)
			s.set_border_width_all(2)
			s.border_color = PbTheme.accent_color("yellow", "c")
		dot.add_theme_stylebox_override("panel", s)
		dot.custom_minimum_size = Vector2(12, 12)
		row.add_child(dot)
	return row


# ------------------------------------------------------------------- season
## `.mm-season`: width/inset clamps from `_on_resized`; content scrolls inside the cap.
func _build_season() -> void:
	_season_wrap = Control.new()
	_season_wrap.name = "SeasonColumn"
	_season_wrap.anchor_left = 1.0
	_season_wrap.anchor_right = 1.0
	_season_wrap.anchor_top = 0.5
	_season_wrap.anchor_bottom = 0.5
	_season_wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_season_wrap.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mm.add_child(_season_wrap)
	_season_wrap.add_child(_season_card_node())
	UI.fill(_season_card)


func _season_card_node() -> PanelContainer:
	_season_card = PanelContainer.new()
	_season_card.name = "SeasonCard"
	_season_card.add_theme_stylebox_override("panel", PbTheme.stylebox(".mm-season"))
	_season_box = UI.vbox(8)
	_season_card.add_child(_season_box)

	var head := UI.hbox(8)
	var word := UI.label(App.ui("Temporada {n}", {"n": 2}), 20, Color.WHITE)
	word.add_theme_font_override("font", PbTheme.font("title"))
	head.add_child(word)
	var head_sp := Control.new()
	head_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_sp)
	head.add_child(UI.label(App.ui("Termina en {time}", {"time": "14 d"}), 12, Color(1, 1, 1, 0.92)))
	_season_box.add_child(_banner(58, head))

	var scroll := UI.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_season_box.add_child(scroll)
	var box := UI.vbox(8)
	scroll.add_child(box)

	box.add_child(UI.segment([
		{"id": "kills", "text": App.ui("Bajas")},
		{"id": "endless", "text": App.ui("Supervivencia")},
		{"id": "race", "text": App.ui("Contrarreloj")},
		{"id": "clans", "text": App.ui("Clanes")},
	], "kills", func(_id): _todo_ranking()))
	box.add_child(UI.mm_tile("globe", App.ui("Global"), "所有地区合计", PbTheme.accent_color("purple", "c"), _todo_ranking))
	box.add_child(UI.dim_block("还没有人打过本赛季 —— 开一局就能直接进前 100。"))

	var mine := UI.panel(12)
	mine.name = "SeasonMine"
	var mbox := UI.vbox(4)
	mine.add_child(mbox)
	mbox.add_child(UI.section(App.ui("Tu temporada")))
	mbox.add_child(UI.paragraph("游客不计入排行榜。", 14, PbTheme.ink(), 2))
	box.add_child(mine)

	box.add_child(UI.dim_block("奖励：前 100 名获得徽章、边框与星尘"))
	# Flow layout: six pill chips would force the card past its 340px minimum width;
	# wrapping keeps `.mm-season{width:clamp(340,26vw,400)}` honest.
	var prizes := HFlowContainer.new()
	prizes.add_theme_constant_override("h_separation", 6)
	prizes.add_theme_constant_override("v_separation", 6)
	for label_text in ["#1", "#2-3", "#4-10", "#11-25", "#26-50", "#51-100"]:
		prizes.add_child(UI.chip(label_text, PbTheme.accent_color("yellow", "c")))
	box.add_child(prizes)
	box.add_child(UI.button(App.ui("Ver clasificación completa"), _todo_ranking, false, "blue"))
	return _season_card


## A striped gradient band (the web's `.lab-top` / season header trick): GradRect fills a fixed
## height box and the content row is overlaid on top of it.
func _banner(height: int, content: Control) -> Control:
	var wrap := UI.panel(0)
	wrap.custom_minimum_size = Vector2(0, height)
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	# GradRect paints the gradient + stripes itself; handing it a StyleBoxFlat draws
	# outside _draw and trips "canvas_item is null", so only the corner radius is set.
	band.corner = 18.0
	band.setup(PbTheme.gradient("linear-gradient(135deg, #ffb04a, #ff8a2f)"), null, true)
	wrap.add_child(band)
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margins.add_theme_constant_override(side, 10)
	margins.add_child(content)
	wrap.add_child(margins)
	return wrap


# ------------------------------------------------------------------- footer
## `.mm-foot`: absolute bottom:10, centered, white 12/800 + `0 1px 3px #000c` shadow.
func _build_footer() -> void:
	_footer = UI.vbox(6)
	_footer.name = "MMFoot"
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mm.add_child(_footer)
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)

	_hint_row = UI.hbox(8)
	_hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_child(_hint_row)
	# H-16: the captions mirror what run_screen.gd actually binds (R fusion, F reroll...).
	_add_hint("WASD", "移动")
	_add_hint("R", "融合")
	_add_hint("Q", "瞄准")
	_add_hint("P", "暂停")
	_add_hint("1-4", "选卡")
	_add_hint("F", "刷新")
	_add_hint("X", "跳过")
	_add_hint("Z", "放逐")

	_legal = _legal_footer()
	_footer.add_child(_legal)


func _add_hint(caption: String, label_text: String) -> void:
	var kbd := UI.kbd(caption)
	_hint_row.add_child(kbd)
	var text := UI.label(label_text, 12, Color.WHITE)
	text.add_theme_font_override("font", PbTheme.font("body_bold"))
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("shadow_offset_y", 1)
	_hint_row.add_child(text)


func _legal_footer() -> Label:
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
	var text := UI.paragraph(
		"PokéBonk 是非官方同人作品，无广告、无内购、无盈利意图，与 Nintendo / Creatures / GAME FREAK 无关。"
		+ "宝可梦名称与角色为各自权利所有者的商标 · © 1995-2026 · 精灵图来自 PMD SpriteCollab (CC BY-NC 4.0)。"
		+ "移植来源：上游 Web 项目 build %s / 版本 %s" % [str(meta.get("site_build", "?")),
			str(meta.get("site_version", "?"))],
		11, Color(1, 1, 1, 0.82), 3)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("shadow_offset_x", 0)
	text.add_theme_constant_override("shadow_offset_y", 1)
	text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return text


# ------------------------------------------------------------------- entrance
func _register_anim(node: Control, kind: String) -> void:
	_anim_items.append({"node": node, "kind": kind, "i": _anim_i})
	_anim_i += 1


## mmIn / mmPop / mmDock: fade + scale, 0.06s cascade, 0.5s back-ease.
func _play_entrance() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for entry in _anim_items:
		var node: Control = entry["node"]
		if not is_instance_valid(node) or node.size.x <= 0.0:
			continue
		node.pivot_offset = node.size * 0.5
		var from := 0.94
		var shift := 16.0
		match str(entry["kind"]):
			"pop":
				from = 0.6
				shift = 0.0
			"dock":
				from = 0.8
				shift = 0.0
		node.modulate.a = 0.0
		node.scale = Vector2(from, from)
		var tw := node.create_tween()
		tw.tween_interval(0.06 * float(entry["i"]))
		tw.tween_property(node, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if shift > 0.0:
			var base_y := node.position.y
			node.position.y = base_y + shift
			tw.parallel().tween_property(node, "position:y", base_y, 0.5) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------- showcase
func _showcase_card() -> Control:
	var card := UI.panel(18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UI.vbox(8)
	card.add_child(box)
	box.add_child(UI.subtitle("当前伙伴"))

	var head := UI.hbox(12)
	box.add_child(head)
	_showcase_sprite = PmdSprite.new()
	_showcase_sprite.setup(_starter, "walk", 4.0, 2)
	head.add_child(_showcase_sprite)

	var info := UI.vbox(2)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_showcase_name = UI.title("—", 26)
	info.add_child(_showcase_name)
	_showcase_meta = UI.dim("")
	info.add_child(_showcase_meta)
	_showcase_types = UI.hbox(4)
	info.add_child(_showcase_types)

	_stat_grid = UI.grid(4, 4)
	box.add_child(_stat_grid)
	box.add_child(HSeparator.new())
	box.add_child(UI.dim("开局招式（由 moves.json + learnsets.json 实时化解析）"))
	_moves_box = UI.vbox(2)
	box.add_child(_moves_box)
	return card


# ------------------------------------------------------------------- settings
func _settings_card() -> Control:
	var card := UI.panel(18)
	card.custom_minimum_size = Vector2(300, 0)
	var box := UI.vbox(8)
	card.add_child(box)
	box.add_child(UI.subtitle(App.ui("Ajustes")))

	var settings: Dictionary = PbJson.as_dict(Save.store.get("settings", {}))
	box.add_child(_slider_row(App.ui("Música"), float(settings.get("music", 1.0)),
		func(v): _persist("music", v)))
	box.add_child(_slider_row(App.ui("Efectos"), float(settings.get("sfx", 1.0)),
		func(v): _persist("sfx", v)))
	box.add_child(_slider_row("镜头震动", float(settings.get("shake", 1.0)),
		func(v): _persist("shake", v)))

	# .seg/.pill: aim mode as a segmented control (auto = lock nearest enemy).
	box.add_child(UI.dim("瞄准模式"))
	box.add_child(UI.segment([
		{"id": "auto", "text": App.ui("Automático")},
		{"id": "manual", "text": App.ui("Manual")},
	], str(settings.get("aimMode", "auto")),
		func(id): _persist("aimMode", id)))

	# Theme switch (web Ajustes -> Tema): light/dark design tokens.
	var theme_row := UI.hbox(8)
	theme_row.add_child(UI.label("深色主题", 15, PbTheme.ink()))
	var theme_sp := Control.new()
	theme_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_sp)
	var theme_sw := PbWidgets.SwitchToggle.new()
	theme_sw.set_pressed(str(settings.get("theme", "light")) == "dark")
	theme_sw.toggled.connect(func(on): App.set_theme_mode("dark" if on else "light"))
	theme_row.add_child(theme_sw)
	box.add_child(theme_row)

	# Language (web Ajustes -> Idioma del juego). The choice lives in
	# user://pb.lang, mirroring localStorage('pokebonk.lang'); picking a value
	# reloads the screen, which is what the web does with location.reload().
	box.add_child(UI.dim(App.ui("Idioma del juego")))
	var lang_row := UI.hbox(8)
	var lang_opt := OptionButton.new()
	lang_opt.add_item(App.ui("Automático"), 0)
	var stored_lang := App.stored_locale()
	for i in App.LOCALES.size():
		var entry := PbJson.as_dict(App.LOCALES[i])
		lang_opt.add_item(str(entry.get("name", "")), i + 1)
		if str(entry.get("id", "")) == stored_lang:
			lang_opt.select(i + 1)
	lang_opt.item_selected.connect(func(idx: int):
		var chosen := "" if idx == 0 else str(PbJson.as_dict(App.LOCALES[idx - 1]).get("id", ""))
		App.set_locale(chosen))
	lang_row.add_child(lang_opt)
	box.add_child(lang_row)

	# M-15: port-only content (recent runs, port notes) lives here, not in the menu flow.
	box.add_child(HSeparator.new())
	box.add_child(UI.subtitle("最近对局"))
	_recent = UI.vbox(2)
	box.add_child(_recent)
	box.add_child(HSeparator.new())
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
	box.add_child(UI.paragraph("Godot 移植版 · 完全离线 · 数据与世界对齐上游项目镜像", 12, PbTheme.ink_muted(), 2))
	box.add_child(UI.paragraph("来源：上游 Web 项目 build %s / 版本 %s" % [
		str(meta.get("site_build", "?")), str(meta.get("site_version", "?"))], 12, PbTheme.ink_muted(), 2))
	box.add_child(UI.paragraph("公式与数据表由上游项目逆向导出，偏移坐标见 data/pb/constants.json", 12, PbTheme.ink_muted(), 2))
	return card


func _slider_row(caption: String, value: float, on_change: Callable) -> Control:
	var box := UI.vbox(0)
	box.add_child(UI.dim(caption))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = clampf(value, 0.0, 1.0)
	slider.custom_minimum_size = Vector2(0, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PbTheme.paint_slider(slider)
	slider.value_changed.connect(on_change)
	box.add_child(slider)
	return box


# ------------------------------------------------------------------- state
func refresh() -> void:
	var profile: Dictionary = Save.load_profile()
	var s := Save.summary()
	_wallet_name.text = str(s.get("name", "?"))
	_wallet_sub.text = "%d 场对局 · %d 个家族已捕获" % [int(s.get("runs", 0)), int(s.get("captured", 0))]
	var portrait := "res://assets/portraits/%d.png" % _starter
	_wallet_avatar.texture = load(portrait) as Texture2D if ResourceLoader.exists(portrait) else null
	for c in _wallet.get_children():
		c.queue_free()
	_wallet.add_child(UI.stat_pill(App.ui("Polvo Estelar"), _num(int(s.get("stardust", 0))), "yellow"))
	_wallet.add_child(UI.stat_pill(App.ui("Pokédex"), "%d/151" % int(s.get("captured", 0)), "orange"))
	if _play_sub != null:
		_play_sub.text = App.ui("Modo clásico · {n}/{total} en tu Liga",
			{"n": int(s.get("captured", 0)), "total": 151})
	if _play_title != null:
		_play_title.add_theme_font_size_override("font_size",
			int(clampf(34.0, 4.6 * _viewport.y / 100.0, 42.0)))
	for c in _recent.get_children():
		c.queue_free()
	var runs: Array = PbJson.as_array(profile.get("runs", []))
	if runs.is_empty():
		_recent.add_child(UI.dim("还没有记录，开一局试试"))
	for raw in runs.slice(0, 3):
		var rec := PbJson.as_dict(raw)
		_recent.add_child(UI.dim("%s · Lv%d · %d 杀 · %.0fs · %s" % [
			App.t("pokemon", int(rec.get("species", 0)), "#%d" % int(rec.get("species", 0))),
			int(rec.get("level", 0)), int(rec.get("kills", 0)), float(rec.get("time", 0.0)),
			App.ui("Victoria") if bool(rec.get("victory", false)) else App.ui("Derrota")]))
	_show_starter(int(profile.get("starter", 0)) if int(profile.get("starter", 0)) > 0 else _starter)
	if _play_sprite != null and is_instance_valid(_play_sprite):
		_play_sprite.setup(_starter, "idle")


# ------------------------------------------------------------- settings modal
## The web keeps partner stats, sliders, aim mode and language behind `Ajustes`; the port does
## the same so the menu itself matches the reference layout.
func _build_settings_modal() -> void:
	_settings_scrim = PanelContainer.new()
	_settings_scrim.name = "SettingsScrim"
	_settings_scrim.add_theme_stylebox_override("panel", PbTheme.modal_scrim())
	add_child(_settings_scrim)
	UI.fill(_settings_scrim)
	_settings_scrim.visible = false
	var col := UI.vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_scrim.add_child(col)
	var head := UI.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(head)
	# H-13: `.modal h1{display:inline-block}` -- keep the pill hugging the text.
	var title := UI.modal_title(App.ui("Ajustes"), false)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(UI.button("关闭 (Esc)", _close_settings, false, "ghost", true))
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var row_scroll := UI.scroll()
	row_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_scroll.add_child(row)
	col.add_child(row_scroll)
	row.add_child(_showcase_card())
	row.add_child(_settings_card())


func _open_settings() -> void:
	_settings_scrim.visible = true
	Audio.sfx("ui")


func _close_settings() -> void:
	_settings_scrim.visible = false
	Audio.sfx("ui")


## Modes and systems the mirror's backend does not expose offline. Each one says so instead
## of pretending to work, matching how the port documents the rest of its gaps.
func _start_endless() -> void:
	UI.toast(self, "生存模式未移植：需要服务器端的迁移/塔层系统")
	Audio.sfx("deny")


func _todo_coop() -> void:
	_ui_todo("合作模式（re 镜像里有完整的联机协议，但需要 WebRTC/中继服务）")


func _todo_event() -> void:
	_ui_todo("活动「Lavanda 之夜」是限时服务器事件")


func _todo_tasks() -> void:
	_ui_todo("委托任务由服务器下发，镜像里没有该接口")


func _todo_achievements() -> void:
	_ui_todo("成就页未移植：数据在 profile.counters，界面待建")


func _todo_ranking() -> void:
	_ui_todo("排行榜是服务器玩法，离线镜像无数据")


func _todo_clan() -> void:
	_ui_todo("Clans 为服务器玩法（firebase/clans.mjs 未被离线后端实现）")


func _todo_report() -> void:
	_ui_todo("反馈接口指向线上服务，离线不可用")


func _todo_discord() -> void:
	_ui_todo("外部链接：离线镜像不跳转")


func _todo_dev() -> void:
	_ui_todo("开发者主页为线上内容")


func _ui_todo(text: String) -> void:
	UI.toast(self, text)
	Audio.sfx("deny")


func _show_starter(species_id: int) -> void:
	_starter = species_id
	var species := PbData.species(species_id)
	if species.is_empty():
		return
	if _showcase_sprite != null and is_instance_valid(_showcase_sprite):
		_showcase_sprite.setup(species_id, "walk", 4.0, 2)
	_showcase_name.text = "%d. %s" % [species_id, str(species.get("name", "?"))]
	_showcase_meta.text = "种族值 %d · %s · 捕获率 %d · %s" % [
		int(species.get("bst", 0)), "闪光" if bool(species.get("mythical", false)) else "普通",
		int(species.get("captureRate", 0)), str(species.get("color", ""))]
	for c in _showcase_types.get_children():
		c.queue_free()
	for t in PbJson.as_array(species.get("types", [])):
		_showcase_types.add_child(UI.type_chip(str(t)))
	for c in _stat_grid.get_children():
		c.queue_free()
	var stats := PbJson.as_dict(species.get("stats", {}))
	var derived := PbStats.stats_from_species(species, 0.0)
	for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
		_stat_grid.add_child(UI.dim(key.to_upper()))
		_stat_grid.add_child(UI.label(str(int(stats.get(key, 0))), 15))
		_stat_grid.add_child(UI.label("实时", 11))
		_stat_grid.add_child(UI.label(_derived_for(str(key), derived), 13))
	for c in _moves_box.get_children():
		c.queue_free()
	var slots := 0
	for raw in PbJson.as_array(PbActor.create(species_id).get("moves", [])):
		if raw == null:
			continue
		var def := PbJson.as_dict(PbJson.as_dict(raw).get("def", {}))
		if def.is_empty():
			continue
		slots += 1
		_moves_box.add_child(UI.dim("%d. %s  [%s · %s] 伤害 %.1f · 冷却 %.2fs · 段数 %d" % [
			slots, str(def.get("name", "?")), str(def.get("type", "")),
			str(def.get("arch", "")), float(def.get("dmg", 0.0)),
			float(def.get("cd", 0.0)), int(def.get("count", 1))]))
	Audio.play_cry(species_id)


func _derived_for(key: String, stats: Dictionary) -> String:
	match key:
		"hp":
			return "%d HP" % int(stats.get("maxHp", 0))
		"atk":
			return "物伤 x%.2f" % float(stats.get("physical", 0))
		"def":
			return "护甲 %.1f" % float(stats.get("armor", 0))
		"spa":
			return "特伤 x%.2f" % float(stats.get("special", 0))
		"spd":
			return "回复 %.2f" % float(stats.get("regen", 0))
		"spe":
			return "移速 %.2f / 闪避 %.0f%%" % [float(stats.get("moveSpeed", 0)),
				float(stats.get("evasion", 0)) * 100.0]
	return ""


func _cycle_starter(delta: int) -> void:
	var profile: Dictionary = Save.load_profile()
	var unlocked: Array = PbJson.as_array(profile.get("unlocked", []))
	if unlocked.is_empty():
		unlocked = PbData.kanto_ids()
	var index := unlocked.find(_starter)
	if index < 0:
		index = 0
	index = posmod(index + delta, unlocked.size())
	_set_starter(int(unlocked[index]))


func _set_starter(pick: int) -> void:
	Save.handle("POST", "/profile/starter", {}, {"id": pick})
	Audio.sfx("ui")
	refresh()


# ------------------------------------------------------- starter picker (sp-*)
## The web `sp` screen (bundle @1951000): three .sp-card candidates, hover
## previews the cry, click opens the "¿Elegir a X?" confirm modal, and the pick
## lands a ls-stamp pop. Replaces the old ◀▶ cycle.
var _picker: Control = null


func _starter_candidates() -> Array:
	var profile: Dictionary = Save.load_profile()
	# JSON stores dex ids as floats, so compare numerically (not Array.has(int)).
	var unlocked_ints := []
	for u in PbJson.as_array(profile.get("unlocked", [])):
		unlocked_ints.append(int(u))
	# The classic Kanto trio, filtered to what the profile has unlocked.
	var trio := [1, 4, 7]
	if unlocked_ints.is_empty():
		return trio
	var out := []
	for id in trio:
		if unlocked_ints.has(id):
			out.append(id)
	if out.is_empty():
		return [unlocked_ints[0]]
	return out


func _open_starter_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	var scrim := PanelContainer.new()
	scrim.name = "StarterPicker"
	scrim.add_theme_stylebox_override("panel", PbTheme.modal_scrim())
	add_child(scrim)
	UI.fill(scrim)
	_picker = scrim
	var col := UI.vbox(16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	scrim.add_child(col)
	# H-13: keep the modal title inline instead of stretching it across the column.
	var title := UI.modal_title("选择你的初始伙伴", false)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(title)
	var blurb := UI.paragraph("它将是你 Liga 的第一位成员；确认后不可更改。", 14, Color.WHITE, 1)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)
	var cards := UI.hbox(22)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	for id in _starter_candidates():
		cards.add_child(_sp_card(int(id)))
	var foot := UI.hbox(8)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	foot.add_child(UI.button(App.ui("Volver"), func():
		if _picker != null and is_instance_valid(_picker):
			_picker.queue_free()
		_picker = null, false, "ghost"))
	Audio.sfx("ui")


## One .sp-card: the PMD showcase (with the ls-stamp overlay) + passive/first-move info.
func _sp_card(species_id: int) -> Control:
	var species := PbData.species(species_id)
	var card := Button.new()
	card.name = "SpCard%d" % species_id
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(240, 320)
	var s := PbTheme.stylebox(".card", {"rc": "#" + PbTheme.type_color(
		str(PbJson.as_array(species.get("types", ["normal"]))[0])).to_html(false)})
	card.add_theme_stylebox_override("normal", s)
	card.add_theme_stylebox_override("hover", s)
	card.add_theme_stylebox_override("pressed", s)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var box := UI.vbox(0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(box)

	# ls-show: the animated showcase with the "¡Te elijo a ti!" stamp.
	var show := Control.new()
	show.name = "LsShow"
	show.custom_minimum_size = Vector2(0, 200)
	var rc := PbTheme.type_color(str(PbJson.as_array(species.get("types", ["normal"]))[0]))
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.setup({"type": "linear", "angle": 135.0, "stops": [
		{"color": PbTheme.mix(rc, Color.WHITE, 0.55), "pos": 0.0}, {"color": rc, "pos": 100.0}]}, null, true)
	show.add_child(band)
	var sprite := PmdSprite.new()
	sprite.setup(species_id, "idle", 2.0)
	sprite.set_anchors_preset(Control.PRESET_CENTER_TOP)
	show.add_child(sprite)
	var stamp := UI.chip(App.ui("¡Te elijo a ti!"), PbTheme.accent_color("red", "c"))
	stamp.name = "LsStamp"
	stamp.visible = false
	stamp.position = Vector2(24, 150)
	show.add_child(stamp)
	box.add_child(show)

	# sp-info: passive + starter move.
	var info := UI.vbox(6)
	var margins := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		margins.add_theme_constant_override(side, 14)
	margins.add_child(info)
	box.add_child(margins)
	var name_l := UI.title("%d. %s" % [species_id, str(species.get("name", "?"))], 20)
	info.add_child(name_l)
	var types := UI.hbox(4)
	info.add_child(types)
	for t in PbJson.as_array(species.get("types", [])):
		types.add_child(UI.type_chip(str(t)))
	var first := ""
	var moves: Array = PbJson.as_array(PbActor.create(species_id).get("moves", []))
	for raw in moves:
		if raw != null:
			first = str(PbJson.as_dict(PbJson.as_dict(raw).get("def", {})).get("name", ""))
			break
	if not first.is_empty():
		info.add_child(UI.dim("初始招式：%s" % first))
	card.mouse_entered.connect(func(): Audio.play_cry(species_id, 0.5))
	card.pressed.connect(func(): _confirm_starter(species_id, stamp))
	UI.anim_in_simple(card, "popIn", 0)
	return card


## The "¿Elegir a X?" confirm modal (web @1951000): ghost 返回重选 / red 确认.
func _confirm_starter(species_id: int, stamp: Control) -> void:
	# ls-stamp pop on the chosen card.
	if stamp != null and is_instance_valid(stamp):
		stamp.visible = true
		stamp.pivot_offset = stamp.size * 0.5
		stamp.scale = Vector2(0.2, 0.2)
		var tw := stamp.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.35)
	var species := PbData.species(species_id)
	var nm := App.t("pokemon", species_id, str(species.get("name", "?")))
	Audio.play_cry(species_id, 0.9)
	var modal := UI.modal_shell(App.ui("¿Elegir a {name}?", {"name": nm}), true)
	var scrim: PanelContainer = modal["scrim"]
	var body: VBoxContainer = modal["body"]
	add_child(scrim)
	UI.fill(scrim)
	body.add_child(UI.paragraph("它将成为你的初始伙伴，之后不可更换。", 14, Color.WHITE, 1))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	row.add_child(UI.button(App.ui("Volver a elegir"), func():
		scrim.queue_free(), false, "ghost"))
	row.add_child(UI.button(App.ui("Sí, elijo a {name}", {"name": nm}), func():
		_set_starter(species_id)
		scrim.queue_free()
		if _picker != null and is_instance_valid(_picker):
			_picker.queue_free()
		_picker = null, false, "red"))


func _persist(key: String, value) -> void:
	var settings: Dictionary = PbJson.as_dict(Save.store.get("settings", {}))
	settings[key] = value
	Save.handle("PUT", "/profile/prefs", {}, {"settings": settings})
	Audio.apply_profile_settings(PbJson.as_dict(Save.store.get("settings", {})))


func _start_run() -> void:
	App.selected_species = _starter
	App.goto("run")


static func _num(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%s" % _thousands(value)
	return str(value)


static func _thousands(value: int) -> String:
	var digits := str(value)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


# ------------------------------------------------------------------- skew tile
## `.mm-item`: a Button that paints its CSS background (gradient/stripes/rings/strip)
## inside a `skew(-6deg)` canvas transform. Children stay upright, exactly like the
## web's `.mm-item>*{transform:skew(6deg)}` counter-skew.
class SkewTile:
	extends Button

	const K := 0.10510423526  # tan(6deg)

	var grad: Dictionary = {}
	var strip_grad: Dictionary = {}
	var fill := Color.WHITE
	var stripes := false
	var radius := 18.0
	var strip := Color(0, 0, 0, 0)
	var strip_side := "left"
	var strip_size := 7.0
	var inset := Color(0, 0, 0, 0)
	var inset_width := 4.0
	var hard := Color(0, 0, 0, 0)
	var hard_offset := 4
	var glow := Color(0, 0, 0, 0)
	var glow_size := 14.0
	var accent := Color(0, 0, 0, 0)
	var hovered := false
	var stripe_period := 20.0

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		clip_contents = false
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
		resized.connect(queue_redraw)

	func _hover(on: bool) -> void:
		hovered = on
		queue_redraw()
		pivot_offset = size * 0.5
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector2(1.03, 1.03) if on else Vector2.ONE, 0.18)

	func _draw() -> void:
		if size.x <= 1.0 or size.y <= 1.0:
			return
		var r := minf(radius, minf(size.x, size.y) * 0.5)
		draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-K, 1),
			Vector2(K * size.y * 0.5, 0)))
		if hovered and accent.a > 0.0:
			_rrect_draw(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), r + 3.0, accent)
		if glow.a > 0.0:
			for i in range(4, 0, -1):
				var grow := glow_size * float(i) / 4.0
				var c := glow
				c.a = glow.a * 0.30 / float(i)
				_rrect_draw(Rect2(Vector2(-grow, -grow + 6.0),
					size + Vector2(grow * 2.0, grow * 2.0)), r + grow, c)
		if hard.a > 0.0:
			_rrect_draw(Rect2(Vector2(0, float(hard_offset)), size), r, hard)
		_paint_body(Rect2(Vector2.ZERO, size), r)
		if inset.a > 0.0:
			# `inset 0 0 0 4px #ffffffe6`: ring, then repaint the interior.
			_rrect_draw(Rect2(Vector2.ZERO, size), r, inset)
			var inner := Rect2(Vector2(inset_width, inset_width),
				size - Vector2(inset_width * 2.0, inset_width * 2.0))
			_paint_body(inner, maxf(r - inset_width, 0.0))
		if strip_side == "left" and (strip.a > 0.0 or not strip_grad.is_empty()):
			var sr := Rect2(0, 0, strip_size, size.y)
			var sr_r := minf(r, strip_size * 0.5)
			if not strip_grad.is_empty():
				_linear(sr, sr_r, strip_grad)
			elif strip.a > 0.0:
				_rrect_draw(sr, sr_r, strip)
		elif strip_side == "bottom" and strip.a > 0.0:
			var sb_rect := Rect2(0, size.y - strip_size, size.x, strip_size)
			_rrect_draw(sb_rect, minf(r, strip_size * 0.5), strip)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	func _paint_body(rect: Rect2, r: float) -> void:
		if not grad.is_empty() and str(grad.get("type", "")) == "linear":
			_linear(rect, r, grad)
		else:
			_rrect_draw(rect, r, fill)
		if stripes:
			var pts := _rrect(rect, r)
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append(p / stripe_period)
			draw_colored_polygon(pts, Color.WHITE, uvs, PbWidgets.stripes_texture())

	func _rrect_draw(rect: Rect2, r: float, color: Color) -> void:
		draw_colored_polygon(_rrect(rect, r), color)

	func _linear(rect: Rect2, r: float, g: Dictionary) -> void:
		var pts := _rrect(rect, r)
		draw_polygon(pts, PbWidgets.linear_colors(pts, g, rect.get_center()))

	func _rrect(rect: Rect2, r: float) -> PackedVector2Array:
		var rr := minf(r, minf(rect.size.x, rect.size.y) * 0.5)
		if rr <= 0.5:
			return PackedVector2Array([rect.position,
				rect.position + Vector2(rect.size.x, 0),
				rect.position + rect.size,
				rect.position + Vector2(0, rect.size.y)])
		var pts := PackedVector2Array()
		var steps := 8
		var corners := [
			{"c": Vector2(rect.size.x - rr, rr), "a0": -90.0, "a1": 0.0},
			{"c": Vector2(rect.size.x - rr, rect.size.y - rr), "a0": 0.0, "a1": 90.0},
			{"c": Vector2(rr, rect.size.y - rr), "a0": 90.0, "a1": 180.0},
			{"c": Vector2(rr, rr), "a0": 180.0, "a1": 270.0},
		]
		for corner_def in corners:
			var center: Vector2 = corner_def["c"]
			var a0 := deg_to_rad(float(corner_def["a0"]))
			var a1 := deg_to_rad(float(corner_def["a1"]))
			for i in steps + 1:
				var ang := lerpf(a0, a1, float(i) / float(steps))
				pts.append(rect.position + center + Vector2(cos(ang), sin(ang)) * rr)
		return pts
