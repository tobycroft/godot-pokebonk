extends Control
## Pokédex screen: species grid + detail panel.
##
## Uses the ported data layer end to end: pokemon.json for stats, learnsets.json
## (ids) resolved through PbMoves into real-time move definitions.


var _detail: VBoxContainer
var _gen := 1
var _grid: GridContainer


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

	var left := UI.vbox(8)
	row.add_child(left)

	# Generation filter as a .seg of .pill buttons (was a row of chunky buttons).
	var gen_items := []
	for gen in [1, 2, 3, 4]:
		gen_items.append({"id": str(gen), "text": "Gen %d" % gen})
	left.add_child(UI.segment(gen_items, str(_gen), func(id): _set_gen(int(id))))

	left.add_child(UI.paragraph("点击查看种族值、属性与可学招式（实时公式已按 web 版移植）", 13, PbTheme.ink_muted(), 1))
	var sc := UI.scroll()
	sc.custom_minimum_size = Vector2(430, 480)
	left.add_child(sc)
	_grid = UI.grid(5, 6)
	sc.add_child(_grid)
	for id in _ids():
		_grid.add_child(_cell(id))

	var panel := UI.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	_detail = UI.vbox(6)
	var detail_scroll := UI.scroll()
	panel.add_child(detail_scroll)
	detail_scroll.add_child(_detail)
	_show(PbData.kanto_ids()[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


func _ids() -> Array:
	return PbData.dex_ids(_gen)


func _set_gen(gen: int) -> void:
	_gen = gen
	_rebuild_grid()


func _rebuild_grid() -> void:
	# Repopulate the grid for the new generation filter.
	for c in _grid.get_children():
		c.queue_free()
	for id in _ids():
		_grid.add_child(_cell(id))


func _cell(species_id: int) -> Button:
	var species := PbData.species(species_id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 108)
	b.add_theme_stylebox_override("normal", PbTheme.pill_field())
	b.add_theme_stylebox_override("hover", PbTheme.pill_field(true))
	b.add_theme_stylebox_override("pressed", PbTheme.pill_field(true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = "%d %s" % [species_id, String(species.get("name", ""))]
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	v.add_child(UI.species_icon(species_id, 2.2))
	v.add_child(UI.dim("#%d" % species_id))
	b.pressed.connect(func(): _show(species_id))
	return b


func _show(species_id: int) -> void:
	for c in _detail.get_children():
		c.queue_free()
	var species := PbData.species(species_id)
	if species.is_empty():
		return
	_detail.add_child(UI.label("%d. %s" % [species_id, String(species.get("name", "?"))], 22))
	var types := UI.hbox(6)
	_detail.add_child(types)
	for t in PbJson.as_array(species.get("types", [])):
		types.add_child(UI.type_chip(String(t)))
	_detail.add_child(UI.dim("属性 %s · 家族 %d · 进化自 %s · 捕获率 %d · 颜色 %s" % [
		PbData.type_label(String(PbJson.as_array(species.get("types", []))[0])),
		int(species.get("family", species_id)),
		"—" if species.get("evoFrom") == null else str(int(species["evoFrom"])),
		int(species.get("captureRate", 0)), String(species.get("color", ""))]))
	_detail.add_child(UI.paragraph(String(species.get("flavor", "")), 13, PbTheme.ink_muted(), 3))

	var stats := PbJson.as_dict(species.get("stats", {}))
	var table := UI.grid(4, 4)
	_detail.add_child(table)
	for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
		table.add_child(UI.dim(key.to_upper()))
		table.add_child(UI.label(str(int(stats.get(key, 0))), 15))
	table.add_child(UI.dim("BST"))
	table.add_child(UI.label(str(int(species.get("bst", 0))), 15))
	table.add_child(UI.dim("身高/体重"))
	table.add_child(UI.label("%d m / %d kg" % [int(species.get("height", 0)), int(species.get("weight", 0))], 14))

	_detail.add_child(HSeparator.new())
	# Real-time derivation (Qy port): what this species actually fights with.
	var derived := PbStats.stats_from_species(species, 0.0)
	_detail.add_child(UI.dim("对局数值(移植公式): HP %d · 伤害 x%.2f · 物/特 %.2f/%.2f · 护甲 %.1f · 闪避 %.1f%% · 移速 %.2f" % [
		int(derived.get("maxHp", 0)), float(derived.get("damage", 0)),
		float(derived.get("physical", 0)), float(derived.get("special", 0)),
		float(derived.get("armor", 0)), float(derived.get("evasion", 0)) * 100.0,
		float(derived.get("moveSpeed", 0))]))

	_detail.add_child(HSeparator.new())
	_detail.add_child(UI.dim("可学招式（实时化解析，前 24 项）"))
	var moves := PbMoves.learnable_moves(species_id)
	var list := UI.vbox(2)
	_detail.add_child(list)
	for i in mini(24, moves.size()):
		var def := PbMoves.resolve(String(moves[i]))
		if def.is_empty():
			continue
		list.add_child(UI.dim("· %s [%s/%s] 实时伤害 %.1f 冷却 %.2fs 段数 %d 范围 %.1f" % [
			String(def.get("name", "")), String(def.get("type", "")), String(def.get("arch", "")),
			float(def.get("dmg", 0.0)), float(def.get("cd", 0.0)), int(def.get("count", 0)),
			float(def.get("area", 0.0))]))
	var best := PbMoves.best_move_for(species_id)
	if not best.is_empty():
		_detail.add_child(UI.label("自动招牌招式: %s" % PbMoves.resolve(best).get("name", best), 15))
	Audio.play_cry(species_id)
