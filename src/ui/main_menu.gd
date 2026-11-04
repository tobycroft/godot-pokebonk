extends Control
## Main menu, laid out node-for-node like the web build's start screen (v0.8.34, mirrored in
## pokebonk-re): floating language/fullscreen pills top-left, the trainer bar top-right, the
## DigiAssault wordmark with its BETA badge, the `.mm-item` grid (a big striped `play` tile plus
## endless / coop / event / tasks), the five small tiles, the mini row, and the season card on
## the right -- all painted from the ported CSS tokens (PbTheme) over the page backdrop.
##
## The port-only extras (derived stats, move list, sliders, locale picker) live in the
## `Ajustes` modal instead of crowding the menu, which is also where the web puts them.
##
## Data flows through the ported API routes exactly as the web client does:
## GET /profile, POST /profile/starter, PUT /profile/prefs.


var _wallet: HBoxContainer
var _wallet_name: Label
var _wallet_sub: Label
var _wallet_avatar: TextureRect
var _play_sub: Label
var _play_sprite: PmdSprite
var _showcase_sprite: PmdSprite
var _showcase_name: Label
var _showcase_meta: Label
var _showcase_types: HBoxContainer
var _stat_grid: GridContainer
var _moves_box: VBoxContainer
var _recent: VBoxContainer
var _hint: Label
var _settings_scrim: PanelContainer
var _starter := 4


func _ready() -> void:
	UI.fill(self)
	var root := UI.screen()
	add_child(root)
	UI.fill(root)
	var column := UI.content(root, 22)

	column.add_child(_top_row())

	var body := UI.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_nav_column())
	body.add_child(_season_card())

	_hint = UI.paragraph("操作：WASD / 方向键移动 · F 融合（两招满级后）· P 暂停 · 1-3 选卡 · Esc 结算本局", 12, PbTheme.ink_muted(), 1)
	column.add_child(_hint)
	column.add_child(_legal_footer())

	_build_settings_modal()

	_starter = int(Save.store.get("starter", 0))
	if _starter <= 0:
		_starter = int(Save.store.get("lastSpecies", 4))
	Audio.apply_profile_settings(PbJson.as_dict(Save.store.get("settings", {})))
	Audio.play_music("menu")
	refresh()
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


# ------------------------------------------------------------------- header
## The two floating pills on the left (language stays hidden while the port is zh-only) and the
## trainer bar on the right, exactly where the web puts them.
func _top_row() -> Control:
	var row := UI.hbox(10)
	var fs := UI.small_button("⛶", _toggle_fullscreen, "blue")
	fs.name = "FullscreenPill"
	row.add_child(fs)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_trainer_bar())
	return row


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


## Wordmark + BETA badge, the `.mm-item` grid and the mini row.
func _nav_column() -> Control:
	var box := UI.vbox(12)
	box.custom_minimum_size = Vector2(620, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var brand := UI.hbox(10)
	brand.add_theme_constant_override("separation", 8)
	var title := UI.title("DigiAssault", 58)
	brand.add_child(title)
	brand.add_child(UI.chip("BETA v0.8.34", PbTheme.accent_color("red", "c")))
	box.add_child(brand)
	box.add_child(UI.dim("Godot 移植版 · 完全离线 · 数据与世界对齐上游项目镜像"))

	# .mm-nav: the play tile is full width (`.mm-item.play` spans the grid), then the four
	# mode/event tiles two-up, the five small tiles, and the mini row.
	var nav := UI.vbox(10)
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(nav)
	nav.add_child(_play_tile())

	var grid := UI.grid(2, 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(grid)
	grid.add_child(UI.mm_tile("moon-stone", App.ui("Supervivencia"), "无尽 · 迁移与首领", PbTheme.accent_color("purple", "c"), _start_endless))
	grid.add_child(UI.mm_tile("friends", App.ui("Cooperativo"), App.ui("Con amigos · 2-4"), PbTheme.accent_color("green", "c"), _todo_coop))
	grid.add_child(UI.mm_tile("map-boss", "Lavanda 之夜", "活动 · 14 天后结束", PbTheme.accent_color("orange", "c"), _todo_event))
	grid.add_child(UI.mm_tile("mission", App.ui("Encargos"), "3 项 · 19 小时后刷新", PbTheme.accent_color("blue", "c"), _todo_tasks))

	var tiles := UI.grid(5, 8)
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(tiles)
	tiles.add_child(_mini_tile("globe", App.ui("Pokédex"), "%d/151" % int(Save.summary().get("captured", 0)),
		PbTheme.accent_color("blue", "c"), func(): App.goto("dex")))
	tiles.add_child(_mini_tile("stardust", App.ui("Laboratorio"), "%d" % int(Save.summary().get("lab", 0)),
		PbTheme.accent_color("green", "c"), func(): App.goto("lab")))
	tiles.add_child(_mini_tile("crown", App.ui("Logros"), "0/228", PbTheme.accent_color("red", "c"), _todo_achievements))
	tiles.add_child(_mini_tile("gold", App.ui("Ranking"), "14 d", PbTheme.accent_color("yellow", "c"), _todo_ranking))
	tiles.add_child(_mini_tile("clan", App.ui("Clan"), App.ui("Sin clan"), PbTheme.accent_color("purple", "c"), _todo_clan))

	var mini := UI.hbox(8)
	box.add_child(mini)
	mini.add_child(UI.mm_tile("brush", App.ui("Ajustes"), "", PbTheme.accent_color("blue", "c"), _open_settings))
	mini.add_child(UI.mm_tile("bug", App.ui("Reportar"), "", PbTheme.accent_color("orange", "c"), _todo_report))
	mini.add_child(UI.mm_tile("chat", "Discord", "", PbTheme.accent_color("purple", "c"), _todo_discord))
	mini.add_child(UI.mm_tile("megaphone", "Charcher", "", PbTheme.accent_color("green", "c"), _todo_dev))

	box.add_child(HSeparator.new())
	box.add_child(UI.dim("最近对局（profile.runs，结算后写入）"))
	_recent = UI.vbox(2)
	box.add_child(_recent)
	return box


## `.mm-item.play`: red gradient + stripes, the label, the Liga progress line and the current
## partner's sprite on the right -- the web's hero tile.
func _play_tile() -> Control:
	var tile := Button.new()
	tile.flat = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.name = "PlayTile"
	tile.custom_minimum_size = Vector2(0, 108)
	var s := PbTheme.stylebox(".mm-item.play", {"--c": "#" + PbTheme.accent_color("red", "c").to_html(false)})
	s.content_margin_left = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.content_margin_right = 12
	for state in ["normal", "hover", "pressed"]:
		tile.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# `.mm-item.play` is a red gradient with stripes -- a StyleBoxFlat cannot express that, so
	# the band is painted behind the content (same trick as the season header).
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.corner = 22.0
	band.setup(PbTheme.gradient("linear-gradient(135deg, #ff8f94, #ff5a5f 60%, #e0303e)"), null, true)
	tile.add_child(band)

	var row := UI.hbox(12)
	tile.add_child(row)
	# Pin the row to the tile: a Button lays its children out by anchors, not by container.
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := PanelContainer.new()
	ic.add_theme_stylebox_override("panel", PbTheme.stylebox(".mm-ic", {"--c": "#ff5a5f"}))
	ic.custom_minimum_size = Vector2(56, 56)
	ic.add_child(UI.icon_rect("poke-ball", 42))
	row.add_child(ic)

	var tx := UI.vbox(2)
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var big := UI.label(App.ui("Jugar"), 30, Color.WHITE)
	big.add_theme_font_override("font", PbTheme.font("title"))
	tx.add_child(big)
	_play_sub = UI.label("", 13, Color(1, 1, 1, 0.92))
	tx.add_child(_play_sub)
	row.add_child(tx)

	_play_sprite = PmdSprite.new()
	_play_sprite.custom_minimum_size = Vector2(64, 64)
	row.add_child(_play_sprite)

	tile.pressed.connect(_start_run)
	tile.mouse_entered.connect(func():
		tile.pivot_offset = tile.size * 0.5
		tile.create_tween().tween_property(tile, "scale", Vector2(1.02, 1.02), 0.12))
	tile.mouse_exited.connect(func():
		tile.create_tween().tween_property(tile, "scale", Vector2.ONE, 0.12))
	return tile


## `.lb-card`-style season panel on the right: striped header, segmented tabs, the region
## selector, the empty leaderboard state and the prize ladder.
func _season_card() -> Control:
	var card := UI.panel(0)
	card.name = "SeasonCard"
	card.custom_minimum_size = Vector2(320, 0)
	var box := UI.vbox(8)
	card.add_child(box)

	var head := UI.hbox(8)
	head.add_theme_constant_override("separation", 8)
	var word := UI.label(App.ui("Temporada {n}", {"n": 2}), 20, Color.WHITE)
	word.add_theme_font_override("font", PbTheme.font("title"))
	head.add_child(word)
	var head_sp := Control.new()
	head_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_sp)
	head.add_child(UI.label(App.ui("Termina en {time}", {"time": "14 d"}), 12, Color(1, 1, 1, 0.92)))
	box.add_child(_banner(58, head))

	box.add_child(UI.segment([
		{"id": "kills", "text": App.ui("Bajas")},
		{"id": "endless", "text": App.ui("Supervivencia")},
		{"id": "race", "text": App.ui("Contrarreloj")},
		{"id": "clans", "text": App.ui("Clanes")},
	], "kills", func(_id): _todo_ranking()))
	box.add_child(UI.mm_tile("globe", App.ui("Global"), "所有地区合计", PbTheme.accent_color("purple", "c"), _todo_ranking))
	box.add_child(UI.dim("还没有人打过本赛季 —— 开一局就能直接进前 100。"))

	var mine := UI.panel(12)
	mine.name = "SeasonMine"
	var mbox := UI.vbox(4)
	mine.add_child(mbox)
	mbox.add_child(UI.section(App.ui("Tu temporada")))
	mbox.add_child(UI.paragraph("游客不计入排行榜。", 14, PbTheme.ink(), 2))
	box.add_child(mine)

	box.add_child(UI.dim("奖励：前 100 名获得徽章、边框与星尘"))
	var prizes := UI.hbox(6)
	for label_text in ["#1", "#2-3", "#4-10", "#11-25", "#26-50", "#51-100"]:
		prizes.add_child(UI.chip(label_text, PbTheme.accent_color("yellow", "c")))
	box.add_child(prizes)
	box.add_child(UI.button(App.ui("Ver clasificación completa"), _todo_ranking, false, "blue"))
	return card


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


## `.mm-item.tile`: the small vertical tiles (icon on top, title, value) the web uses for the
## secondary destinations row.
func _mini_tile(icon_name: String, title_text: String, value_text: String,
		accent: Color, on_click: Callable) -> Control:
	var tile := Button.new()
	tile.flat = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(0, 92)
	var s := PbTheme.stylebox(".mm-item.tile", {"--c": "#" + accent.to_html(false)})
	for state in ["normal", "hover", "pressed"]:
		tile.add_theme_stylebox_override(state, s)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UI.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile.add_child(col)
	var ic := PanelContainer.new()
	ic.add_theme_stylebox_override("panel", PbTheme.stylebox(".mm-ic", {"--c": "#" + accent.to_html(false)}))
	ic.custom_minimum_size = Vector2(40, 40)
	ic.add_child(UI.icon_rect(icon_name, 30))
	col.add_child(ic)
	var t := UI.label(title_text, 15, PbTheme.ink())
	t.add_theme_font_override("font", PbTheme.font("title"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	# `.mm-tx small{font-size:12px;font-weight:800}`: body_bold keeps the weight
	# now that PbTheme.font("body") is the 700 face.
	var v := UI.label(value_text, PbTheme.font_size("tiny"), PbTheme.ink_muted())
	v.add_theme_font_override("font", PbTheme.font("body_bold"))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)
	if on_click.is_valid():
		tile.pressed.connect(on_click)
	return tile


func _legal_footer() -> Control:
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
	return UI.paragraph(
		"DigiAssault 是非官方同人作品，无广告、无内购、无盈利意图，与 Nintendo / Creatures / GAME FREAK 无关。"
		+ "宝可梦名称与角色为各自权利所有者的商标 · © 1995-2026 · 精灵图来自 PMD SpriteCollab (CC BY-NC 4.0)。"
		+ "移植来源：上游 Web 项目 build %s / 版本 %s" % [str(meta.get("site_build", "?")),
		str(meta.get("site_version", "?"))],
		11, PbTheme.ink_muted(), 3)


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

	box.add_child(HSeparator.new())
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
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
		_play_sub.text = "经典模式 · %d/151 在你的联盟 · 联盟 %d · 邦币 %d" % [
			int(s.get("captured", 0)), int(s.get("league", 0)), int(s.get("bonk", 0))]
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
	UI.fill(_settings_scrim)
	_settings_scrim.visible = false
	add_child(_settings_scrim)
	UI.fill(_settings_scrim)
	var col := UI.vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_scrim.add_child(col)
	var head := UI.hbox(10)
	col.add_child(head)
	var title := UI.modal_title(App.ui("Ajustes"), false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.button("关闭 (Esc)", _close_settings, false, "ghost", true))
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
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
	UI.fill(scrim)
	add_child(scrim)
	UI.fill(scrim)
	_picker = scrim
	var col := UI.vbox(16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	scrim.add_child(col)
	col.add_child(UI.modal_title("选择你的初始伙伴", false))
	col.add_child(UI.paragraph("它将是你 Liga 的第一位成员；确认后不可更改。", 14, Color.WHITE, 1))
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
