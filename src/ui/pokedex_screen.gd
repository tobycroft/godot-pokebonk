extends Control
## Pokédex screen, laid out like the web `.dx` view (diff-list #6): a left
## `.dx-search` + `.dx-grid` of `.dx-tile` squares (unseen ones get the grey
## `.dx-tile.unk` lock), and a right `.dx-info` panel with the portrait,
## `.dx-types` chips, six `.dx-bar` stat bars and `.dx-ms` move rows whose bar
## width is the real-time dps estimate from PbDamage.move_instance.
##
## Data comes straight from the ported tables: pokemon.json for stats,
## learnsets.json resolved through PbMoves/PbDamage into live move numbers.

var _detail: VBoxContainer
var _grid: GridContainer
var _search: LineEdit
var _gen := 1
var _query := ""


func _ready() -> void:
	UI.fill(self)
	var root := UI.screen()
	add_child(root)
	UI.fill(root)
	var column := UI.content(root, 18)

	# .scr-head: back pill (Esc) + the skewed striped title plate.
	column.add_child(UI.screen_head("图鉴", "Pokédex · 151 de Kanto", func(): App.back_to_menu()))

	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	# ---- left: search + generation seg + tile grid
	var left := UI.vbox(8)
	left.custom_minimum_size = Vector2(430, 0)
	row.add_child(left)

	var gen_items := []
	for gen in [1, 2, 3, 4]:
		gen_items.append({"id": str(gen), "text": "Gen %d" % gen})
	left.add_child(UI.segment(gen_items, str(_gen), func(id): _set_gen(int(id))))

	# .dx-search: a .field that filters by name or dex number.
	_search = UI.field("搜索名称或编号…")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(t): _query = t.strip_edges(); _rebuild_grid())
	left.add_child(_search)

	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	_grid = UI.grid(5, 6)
	sc.add_child(_grid)

	# ---- right: .dx-info detail panel
	var panel := UI.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var info_scroll := UI.scroll()
	panel.add_child(info_scroll)
	_detail = UI.vbox(10)
	_detail.name = "DxInfo"
	info_scroll.add_child(_detail)

	_rebuild_grid()
	_show(PbData.kanto_ids()[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


func _set_gen(gen: int) -> void:
	_gen = gen
	_rebuild_grid()


func _matching_ids() -> Array:
	var ids: Array = PbData.dex_ids(_gen)
	if _query.is_empty():
		return ids
	var q := _query.to_lower()
	var numeric := q.is_valid_int()
	var out := []
	for id in ids:
		var species := PbData.species(int(id))
		var name := String(species.get("name", "")).to_lower()
		if (numeric and int(q) == int(id)) or (not numeric and name.contains(q)):
			out.append(id)
	return out


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var captured: Array = PbJson.as_array(Save.store.get("captured", []))
	for id in _matching_ids():
		_grid.add_child(_tile(int(id), captured.has(int(id))))


## .dx-tile: square species cell; unseen ones use the grey .dx-tile.unk lock.
func _tile(species_id: int, captured: bool) -> Button:
	var species := PbData.species(species_id)
	var b := Button.new()
	b.name = "Tile%d" % species_id
	b.custom_minimum_size = Vector2(84, 84)
	b.focus_mode = Control.FOCUS_NONE
	var rc := PbTheme.type_color(String(PbJson.as_array(species.get("types", ["normal"]))[0]))
	var s := PbTheme.stylebox(".dx-tile", {"--c": "#" + rc.to_html(false)})
	if not captured:
		s = PbTheme.stylebox(".dx-tile.unk")
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = "%d %s" % [species_id, String(species.get("name", ""))]
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	if captured:
		v.add_child(UI.species_icon(species_id, 1.9))
	else:
		var lock := UI.icon_rect("lock", 26)
		lock.modulate = PbTheme.ink_muted()
		v.add_child(lock)
	var num := UI.dim("#%d" % species_id)
	num.add_theme_font_size_override("font_size", 10)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	b.pressed.connect(func(): _show(species_id))
	return b


func _show(species_id: int) -> void:
	for c in _detail.get_children():
		c.queue_free()
	var species := PbData.species(species_id)
	if species.is_empty():
		return

	# head: portrait + name + types
	var head := UI.hbox(12)
	_detail.add_child(head)
	var portrait := PmdSprite.new()
	portrait.setup(species_id, "idle", 2.6)
	head.add_child(portrait)
	var title_col := UI.vbox(4)
	title_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	head.add_child(title_col)
	var h := UI.title("%d. %s" % [species_id, String(species.get("name", "?"))], 24)
	title_col.add_child(h)
	var types := UI.hbox(4)
	types.name = "DxTypes"
	title_col.add_child(types)
	for t in PbJson.as_array(species.get("types", [])):
		types.add_child(UI.type_chip(String(t)))
	title_col.add_child(UI.dim("家族 %d · 进化自 %s · 捕获率 %d · %s" % [
		int(species.get("family", species_id)),
		"—" if species.get("evoFrom") == null else str(int(species["evoFrom"])),
		int(species.get("captureRate", 0)), String(species.get("color", ""))]))

	var flavor := String(species.get("flavor", ""))
	if not flavor.is_empty():
		_detail.add_child(UI.paragraph(flavor, 13, PbTheme.ink_muted(), 2))

	# .dx-bar six-stat bars (value -> bar width, coloured by magnitude)
	_detail.add_child(HSeparator.new())
	_detail.add_child(UI.section("种族值"))
	var stats := PbJson.as_dict(species.get("stats", {}))
	var bar_col := UI.vbox(3)
	_detail.add_child(bar_col)
	for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
		bar_col.add_child(_stat_row(key.to_upper(), int(stats.get(key, 0))))
	var bst := int(species.get("bst", 0))
	bar_col.add_child(_stat_row("BST", bst, 720.0, PbTheme.accent_color("purple", "c")))

	# real-time derivation (Qy port)
	var derived := PbStats.stats_from_species(species, 0.0)
	_detail.add_child(UI.dim("对局数值(移植公式): HP %d · 伤害 x%.2f · 物/特 %.2f/%.2f · 护甲 %.1f · 闪避 %.1f%% · 移速 %.2f" % [
		int(derived.get("maxHp", 0)), float(derived.get("damage", 0)),
		float(derived.get("physical", 0)), float(derived.get("special", 0)),
		float(derived.get("armor", 0)), float(derived.get("evasion", 0)) * 100.0,
		float(derived.get("moveSpeed", 0))]))

	# .dx-ms learnable moves with dps bars
	_detail.add_child(HSeparator.new())
	_detail.add_child(UI.section("可学招式（实时解析，前 12 项）"))
	var actor := PbActor.create(species_id)
	var moves := PbMoves.learnable_moves(species_id)
	var scored := []
	for key in moves:
		var def := PbMoves.resolve(String(key))
		if def.is_empty():
			continue
		var built := PbDamage.move_instance(def, PbActor.actor_for_damage(actor), 1)
		scored.append({"def": def, "dps": float(built.get("dps", 0.0))})
	scored.sort_custom(func(a, b): return float(a["dps"]) > float(b["dps"]))
	var max_dps := 1.0
	for s in scored:
		max_dps = maxf(max_dps, float(s["dps"]))
	for i in mini(12, scored.size()):
		_detail.add_child(_move_row(PbJson.as_dict(scored[i]["def"]), float(scored[i]["dps"]) / max_dps))
	var best := PbMoves.best_move_for(species_id)
	if not best.is_empty():
		_detail.add_child(UI.label("自动招牌招式: %s" % PbMoves.resolve(best).get("name", best), 15))
	Audio.play_cry(species_id)


## One .dx-bar row: caption + value + a track whose fill width is value/max.
func _stat_row(caption: String, value: int, mx: float = 255.0, color: Color = Color(0, 0, 0, 0)) -> Control:
	var row := UI.hbox(8)
	var cap := UI.dim(caption)
	cap.custom_minimum_size = Vector2(46, 0)
	row.add_child(cap)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := Panel.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = PbTheme.css_color(PbTheme.v("--k-e4dcf4", "#e4dcf4"), Color("#e4dcf4"))
	ts.set_corner_radius_all(99)
	track.add_theme_stylebox_override("panel", ts)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	var fill := ColorRect.new()
	var ratio := clampf(float(value) / mx, 0.0, 1.0)
	fill.color = color if color.a > 0.0 else _stat_color(ratio)
	fill.custom_minimum_size = Vector2(0, 10)
	bar.add_child(fill)
	bar.resized.connect(func(): fill.size = Vector2(bar.size.x * ratio, 10))
	fill.size = Vector2(120 * ratio, 10)
	row.add_child(bar)
	var val := UI.label(str(value), 13, PbTheme.ink())
	val.custom_minimum_size = Vector2(34, 0)
	val.add_theme_font_override("font", PbTheme.font("title"))
	row.add_child(val)
	return row


func _stat_color(ratio: float) -> Color:
	if ratio >= 0.7:
		return PbTheme.accent_color("green", "c")
	if ratio >= 0.45:
		return PbTheme.accent_color("blue", "c")
	if ratio >= 0.28:
		return PbTheme.accent_color("yellow", "c")
	return PbTheme.accent_color("red", "c")


## One .dx-ms row: type chip + move name + a dps bar.
func _move_row(def: Dictionary, dps_ratio: float) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-ms"))
	var row := UI.hbox(10)
	panel.add_child(row)
	row.add_child(UI.type_chip(String(def.get("type", "normal"))))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UI.label("%s  [%s]  dmg %.1f cd %.2fs" % [
		String(def.get("name", "?")), String(def.get("arch", "")),
		float(def.get("dmg", 0.0)), float(def.get("cd", 0.0))], 13, PbTheme.ink()))
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 5)
	var track := Panel.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = PbTheme.css_color(PbTheme.v("--k-e4dcf4", "#e4dcf4"), Color("#e4dcf4"))
	ts.set_corner_radius_all(99)
	track.add_theme_stylebox_override("panel", ts)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	var fill := ColorRect.new()
	fill.color = PbTheme.type_color(String(def.get("type", "normal")))
	fill.custom_minimum_size = Vector2(0, 5)
	fill.size = Vector2(200 * clampf(dps_ratio, 0.0, 1.0), 5)
	bar.add_child(fill)
	col.add_child(bar)
	return panel
