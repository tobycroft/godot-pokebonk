extends Control
## Research lab: the 22 permanent upgrades from api-core.js's LAB table.
##
## Buying goes through the ported route POST /lab/<id>/buy, so cost (10*(rank+1)),
## MAX / NO_STARDUST errors and the stardust spend all behave like the web build.


var _stardust: Label
var _rows := {}


func _ready() -> void:
	UI.fill(self)
	var scr := UI.screen()
	add_child(scr)
	UI.fill(scr)
	var root := UI.content(scr, 18)

	# .scr-head: back pill (Esc) + striped title plate (web screen chrome).
	root.add_child(UI.screen_head(App.ui("Laboratorio"), App.ui("Mejoras permanentes de estadísticas"), func(): App.back_to_menu()))
	root.add_child(UI.paragraph(App.ui("Mejoras permanentes: valen para todas tus partidas y todos tus Pokémon. Arriba, Entrenamiento (daño, PS, velocidad…); abajo, el equipo de partida. Cada nivel cuesta más que el anterior."), 13, PbTheme.ink_muted(), 1))
	_stardust = UI.label("", 18, PbTheme.accent_color("blue", "cd"))
	_stardust.add_theme_font_override("font", PbTheme.font("title"))
	root.add_child(_stardust)

	var sc := UI.scroll()
	root.add_child(sc)
	var grid := UI.grid(3, 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for row in Save.lab_table():
		var entry := PbJson.as_dict(row)
		grid.add_child(_card(str(entry["id"]), int(entry["max"]), grid.get_child_count() - 1))

	var footer := UI.hbox(8)
	root.add_child(footer)
	footer.add_child(UI.dim("数据来自 api-core.js 的 LAB 表；走 /lab/<id>/buy 路由。"))
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


## .lab-card tile: gradient top band + icon disc + name + level pill + price
## pill (green when affordable, red when short, .kind.price.ok/.no) + buy button.
func _card(id: String, max_rank: int, index: int) -> Control:
	var accent := _lab_color(id)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := PbTheme.stylebox(".lab-card", {"--c": "#" + accent.to_html(false)})
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", s)
	panel.clip_contents = true
	var v := UI.vbox(0)
	panel.add_child(v)

	# .lab-top gradient band
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 40)
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.setup(PbTheme.gradient(str(PbTheme.decls(".lab-top").get("background", "")),
		{"--c": "#" + accent.to_html(false)}), null, true)
	top.add_child(band)
	v.add_child(top)

	var body := UI.vbox(4)
	var margins := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		margins.add_theme_constant_override(side, 12)
	margins.add_theme_constant_override("margin_top", 4)
	margins.add_child(body)
	v.add_child(margins)

	var name_l := UI.label(_name(id), 15, PbTheme.ink())
	name_l.add_theme_font_override("font", PbTheme.font("title"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(name_l)

	var rank := UI.chip(App.ui("Nv. {n}/{max}", {"n": 0, "max": max_rank}), accent)
	rank.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(rank)

	var cost := UI.chip("—", PbTheme.ink_muted())
	cost.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(cost)

	var buy := UI.button(App.ui("Comprar"), func(): _buy(id), false, "purple")
	buy.custom_minimum_size = Vector2(0, 34)
	body.add_child(buy)

	_rows[id] = {"max": max_rank, "rank": rank, "cost": cost, "buy": buy, "panel": panel}
	UI.anim_in_simple(panel, "tileIn", index)
	return panel


## Category colour for the tile accent (the site tints lab groups; we key off
## the id families). Falls back to the .lab-card default --c:var(--purple).
func _lab_color(id: String) -> Color:
	if id.begins_with("slot") or id in ["bag", "party"]:
		return PbTheme.accent_color("blue", "c")
	if id in ["dmg", "hp", "armor", "regen", "spd", "atkspd", "area"]:
		return PbTheme.accent_color("green", "c")
	if id in ["reroll", "skip", "banish", "research", "ult"]:
		return PbTheme.accent_color("orange", "c")
	return PbTheme.accent_color("purple", "c")


func _buy(id: String) -> void:
	var res := Save.lab_buy(id)
	if not bool(res.get("ok", false)):
		Audio.sfx("deny")
		match str(res.get("error", "")):
			"MAX":
				UI.toast(self, App.ui("MÁX."))
			"NO_STARDUST":
				UI.toast(self, App.ui("No tienes Polvo Estelar suficiente."))
	else:
		Audio.sfx("level")
		# CSS @keyframes bought: scale .92 -> 1.06 -> 1.
		var entry := PbJson.as_dict(_rows.get(id, {}))
		var panel := entry.get("panel") as Control
		if panel != null:
			panel.pivot_offset = panel.size * 0.5
			var tw := panel.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			panel.scale = Vector2(0.92, 0.92)
			tw.tween_property(panel, "scale", Vector2(1.06, 1.06), 0.12)
			tw.tween_property(panel, "scale", Vector2.ONE, 0.12)
	refresh()


func refresh() -> void:
	_stardust.text = "%s: %d    %s: %d" % [
		App.ui("Polvo Estelar"), int(Save.store.get("stardust", 0)),
		"Bonk", int(Save.store.get("bonk", 0))]
	var wallet := int(Save.store.get("stardust", 0))
	for id in _rows.keys():
		var entry: Dictionary = _rows[id]
		var rank := Save.lab(id)
		var max_rank := int(entry["max"])
		var rank_chip := _chip_label(entry["rank"])
		rank_chip.text = App.ui("Nv. {n}/{max}", {"n": rank, "max": max_rank}) if rank < max_rank else App.ui("MÁX.")
		var cost := 10 * (rank + 1)
		var maxed := rank >= max_rank
		var afford := wallet >= cost
		var cost_chip := _chip_label(entry["cost"])
		cost_chip.text = App.ui("MÁX.") if maxed else App.ui("{n} de Polvo Estelar", {"n": cost})
		# .kind.price.ok / .kind.price.no colouring by affordability.
		var price_col := PbTheme.ink_muted()
		if maxed:
			price_col = PbTheme.ink_muted()
		elif afford:
			price_col = PbTheme.accent_color("green", "cd")
		else:
			price_col = PbTheme.accent_color("red", "cd")
		cost_chip.add_theme_color_override("font_color", price_col)
		(entry["buy"] as Button).disabled = maxed or not afford


func _chip_label(chip: Control) -> Label:
	for c in chip.get_children():
		if c is Label:
			return c as Label
	return chip as Label


func _name(id: String) -> String:
	var names := {
		"slot-move": "4.º movimiento", "slot-vit": "Huecos de vitamina",
		"reroll": "Refrescar", "skip": "Saltar", "banish": "Desterrar",
		"dmg": "Daño", "hp": "PS máx.", "spd": "Velocidad", "xp": "Experiencia",
		"gold": "Pokédólares", "luck": "Suerte", "magnet": "Recogida", "regen": "Regeneración",
		"armor": "Armadura", "revive": "Revivir", "research": "Investigación",
		"party": "Equipo de apoyo", "area": "Área", "atkspd": "Velocidad de ataque", "ult": "Ultimate",
		"crit": "Crítico", "bag": "Mochila",
	}
	return App.ui(str(names.get(id, id)))
