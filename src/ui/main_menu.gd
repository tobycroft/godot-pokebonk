extends Control
## Main menu, laid out like the web build's start screen: brand row + wallet
## pills across the top, a hero card with the chunky pill actions on the left,
## the starter showcase and settings on the right, all painted from the ported
## CSS tokens (PbTheme) over the recreated page backdrop.
##
## Data flows through the ported API routes exactly as the web client does:
## GET /profile, POST /profile/starter, PUT /profile/prefs.


var _wallet: HBoxContainer
var _showcase_sprite: PmdSprite
var _showcase_name: Label
var _showcase_meta: Label
var _showcase_types: HBoxContainer
var _stat_grid: GridContainer
var _moves_box: VBoxContainer
var _recent: VBoxContainer
var _hint: Label
var _starter := 4


func _ready() -> void:
	UI.fill(self)
	var root := UI.screen()
	add_child(root)
	UI.fill(root)
	var column := UI.content(root, 26)

	column.add_child(_brand_row())
	column.add_child(HSeparator.new())

	var hero := UI.hbox(16)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(hero)
	hero.add_child(_actions_card())
	hero.add_child(_showcase_card())
	hero.add_child(_settings_card())

	_hint = UI.paragraph("操作：WASD / 方向键移动 · F 融合（两招满级后）· P 暂停 · 1-3 选卡 · Esc 结算本局", 13, PbTheme.ink_muted(), 1)
	column.add_child(_hint)

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


func _process(_dt: float) -> void:
	# Esc on the menu closes the app, like leaving the web page.
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()


# ------------------------------------------------------------------- header
func _brand_row() -> Control:
	var row := UI.hbox(12)
	var brand := UI.vbox(0)
	brand.add_theme_constant_override("separation", 0)
	var title := UI.title("PokéBonk", 44)
	brand.add_child(title)
	brand.add_child(UI.dim("Godot 移植版 · 完全离线 · 数据与公式来自 pokebonk-web"))
	row.add_child(brand)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_wallet = UI.hbox(8)
	row.add_child(_wallet)
	return row


# ------------------------------------------------------------------- actions
func _actions_card() -> Control:
	var card := UI.panel(18)
	card.custom_minimum_size = Vector2(320, 0)
	var box := UI.vbox(10)
	card.add_child(box)
	box.add_child(UI.subtitle("开始你的对局"))
	box.add_child(UI.button("开始对局", _start_run, true, "yellow"))

	# .mm-nav: the secondary destinations as web .mm-item tiles.
	var nav := UI.grid(1, 8)
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(nav)
	nav.add_child(UI.mm_tile("globe", "图鉴", "151 只宝可梦与实时公式", PbTheme.accent_color("blue", "c"), func(): App.goto("dex")))
	nav.add_child(UI.mm_tile("stardust", "研究所", "永久强化", PbTheme.accent_color("green", "c"), func(): App.goto("lab")))
	nav.add_child(UI.mm_tile("rotate", "融合机器", "招式合成配方", PbTheme.accent_color("purple", "c"), func(): App.goto("fusion")))
	nav.add_child(UI.mm_tile("lock", "存档管理", "导出 / 导入 / 备份", PbTheme.accent_color("orange", "c"), func(): App.goto("save")))

	box.add_child(HSeparator.new())
	# Starter selection (web `sp` screen @1951000): a 3-way pick, not a ◀▶ cycle.
	box.add_child(UI.button("选择初始伙伴", _open_starter_picker, false, "purple"))

	box.add_child(HSeparator.new())
	box.add_child(UI.dim("最近对局（profile.runs，结算后写入）"))
	_recent = UI.vbox(2)
	box.add_child(_recent)
	return card


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
	box.add_child(UI.subtitle("设置"))

	var settings: Dictionary = PbJson.as_dict(Save.store.get("settings", {}))
	box.add_child(_slider_row("音乐", float(settings.get("music", 1.0)),
		func(v): _persist("music", v)))
	box.add_child(_slider_row("音效", float(settings.get("sfx", 1.0)),
		func(v): _persist("sfx", v)))
	box.add_child(_slider_row("镜头震动", float(settings.get("shake", 1.0)),
		func(v): _persist("shake", v)))

	# .seg/.pill: aim mode as a segmented control (auto = lock nearest enemy).
	box.add_child(UI.dim("瞄准模式"))
	box.add_child(UI.segment([
		{"id": "auto", "text": "自动"},
		{"id": "manual", "text": "手动"},
	], String(settings.get("aimMode", "auto")),
		func(id): _persist("aimMode", id)))

	# Theme switch (web Ajustes -> Tema): light/dark design tokens.
	var theme_row := UI.hbox(8)
	theme_row.add_child(UI.label("深色主题", 15, PbTheme.ink()))
	var theme_sp := Control.new()
	theme_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_sp)
	var theme_sw := PbWidgets.SwitchToggle.new()
	theme_sw.set_pressed(String(settings.get("theme", "light")) == "dark")
	theme_sw.toggled.connect(func(on): App.set_theme_mode("dark" if on else "light"))
	theme_row.add_child(theme_sw)
	box.add_child(theme_row)

	# Language: the site ships 9 locales; the port exposes the ones with data.
	box.add_child(UI.dim("界面语言"))
	var codes := ["en", "zh", "zht", "ja", "fr", "pt", "ru"]
	var lang_items := []
	for code in codes:
		lang_items.append({"id": code, "text": code.to_upper()})
	box.add_child(UI.segment(lang_items, App.locale,
		func(id): _set_locale(id)))

	box.add_child(HSeparator.new())
	var meta := PbJson.as_dict(PbData.pb_table("port_meta"))
	box.add_child(UI.paragraph("来源：pokebonk-web build %s / 版本 %s" % [
		String(meta.get("site_build", "?")), String(meta.get("site_version", "?"))], 12, PbTheme.ink_muted(), 2))
	box.add_child(UI.paragraph("公式与数据表由 pokebonk-web/tools-re 逆向导出，偏移坐标见 data/pb/constants.json", 12, PbTheme.ink_muted(), 2))
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
	for c in _wallet.get_children():
		c.queue_free()
	_wallet.add_child(UI.stat_pill("训练家", String(s.get("name", "?")), "blue"))
	_wallet.add_child(UI.stat_pill("星尘", _num(int(s.get("stardust", 0))), "yellow"))
	_wallet.add_child(UI.stat_pill("邦币", _num(int(s.get("bonk", 0))), "purple"))
	_wallet.add_child(UI.stat_pill("联盟", "%d" % int(s.get("league", 0)), "green"))
	_wallet.add_child(UI.stat_pill("图鉴", "%d/151" % int(s.get("captured", 0)), "orange"))
	_wallet.add_child(UI.stat_pill("对局", "%d" % int(s.get("runs", 0)), "red"))
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
			"胜利" if bool(rec.get("victory", false)) else "失败"]))
	_show_starter(int(profile.get("starter", 0)) if int(profile.get("starter", 0)) > 0 else _starter)


func _show_starter(species_id: int) -> void:
	_starter = species_id
	var species := PbData.species(species_id)
	if species.is_empty():
		return
	if _showcase_sprite != null and is_instance_valid(_showcase_sprite):
		_showcase_sprite.setup(species_id, "walk", 4.0, 2)
	_showcase_name.text = "%d. %s" % [species_id, String(species.get("name", "?"))]
	_showcase_meta.text = "种族值 %d · %s · 捕获率 %d · %s" % [
		int(species.get("bst", 0)), "闪光" if bool(species.get("mythical", false)) else "普通",
		int(species.get("captureRate", 0)), String(species.get("color", ""))]
	for c in _showcase_types.get_children():
		c.queue_free()
	for t in PbJson.as_array(species.get("types", [])):
		_showcase_types.add_child(UI.type_chip(String(t)))
	for c in _stat_grid.get_children():
		c.queue_free()
	var stats := PbJson.as_dict(species.get("stats", {}))
	var derived := PbStats.stats_from_species(species, 0.0)
	for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
		_stat_grid.add_child(UI.dim(key.to_upper()))
		_stat_grid.add_child(UI.label(str(int(stats.get(key, 0))), 15))
		_stat_grid.add_child(UI.label("实时", 11))
		_stat_grid.add_child(UI.label(_derived_for(String(key), derived), 13))
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
			slots, String(def.get("name", "?")), String(def.get("type", "")),
			String(def.get("arch", "")), float(def.get("dmg", 0.0)),
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
	foot.add_child(UI.button("返回", func():
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
		String(PbJson.as_array(species.get("types", ["normal"]))[0])).to_html(false)})
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
	var rc := PbTheme.type_color(String(PbJson.as_array(species.get("types", ["normal"]))[0]))
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.setup({"type": "linear", "angle": 135.0, "stops": [
		{"color": PbTheme.mix(rc, Color.WHITE, 0.55), "pos": 0.0}, {"color": rc, "pos": 100.0}]}, null, true)
	show.add_child(band)
	var sprite := PmdSprite.new()
	sprite.setup(species_id, "idle", 2.0)
	sprite.set_anchors_preset(Control.PRESET_CENTER_TOP)
	show.add_child(sprite)
	var stamp := UI.chip("就选你了！", PbTheme.accent_color("red", "c"))
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
	var name_l := UI.title("%d. %s" % [species_id, String(species.get("name", "?"))], 20)
	info.add_child(name_l)
	var types := UI.hbox(4)
	info.add_child(types)
	for t in PbJson.as_array(species.get("types", [])):
		types.add_child(UI.type_chip(String(t)))
	var first := ""
	var moves: Array = PbJson.as_array(PbActor.create(species_id).get("moves", []))
	for raw in moves:
		if raw != null:
			first = String(PbJson.as_dict(PbJson.as_dict(raw).get("def", {})).get("name", ""))
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
	var nm := String(species.get("name", "?"))
	Audio.play_cry(species_id, 0.9)
	var modal := UI.modal_shell("选择 %s？" % nm, true)
	var scrim: PanelContainer = modal["scrim"]
	var body: VBoxContainer = modal["body"]
	add_child(scrim)
	UI.fill(scrim)
	body.add_child(UI.paragraph("它将成为你的初始伙伴，之后不可更换。", 14, Color.WHITE, 1))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	row.add_child(UI.button("返回重选", func():
		scrim.queue_free(), false, "ghost"))
	row.add_child(UI.button("确认选择 %s" % nm, func():
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


func _set_locale(code: String) -> void:
	App.locale = code
	TranslationServer.set_locale(code)
	refresh()


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
