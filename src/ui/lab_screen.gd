extends Control
## Research lab: the 22 permanent upgrades from api-core.js's LAB table.
##
## Buying goes through the ported route POST /lab/<id>/buy, so cost (10*(rank+1)),
## MAX / NO_STARDUST errors and the stardust spend all behave like the web build.
##
## Layout mirrors the web `.lab-wrap > .lab-group > .grp-head + .lab-grid`
## (repeat(auto-fill, minmax(230px, 1fr))) structure: 70px `.lab-top`, 54px
## `.lab-ic` disc, `.lab-lv` level pill and the three `.lab-buy` states.

const MIN_COL := 230.0   # .lab-grid minmax(230px, 1fr)
const GRID_GAP := 12.0   # .lab-grid gap
const TOP_H := 70.0      # .lab-top height
const ICON_SIZE := 54.0  # .lab-ic width/height
const ICON_ART := 40.0   # .lab-ic img width/height

## Web metadata table (`je` in the main bundle, same build as the i18n export):
## name/desc strings double as App.ui keys, `icon` is the item art id, `stat`
## mirrors the web split `m.filter(e => e.stat)`. `choice4` / `archive` exist in
## that table but not in api-core.js LAB, so they are not part of the port's 22.
const META := {
	"slot-move": {"name": "4.º movimiento", "desc": "Desbloquea el cuarto hueco de movimiento.", "icon": "tm-case", "stat": false},
	"slot-vit": {"name": "Huecos de vitamina", "desc": "+1 hueco de vitamina por nivel.", "icon": "protein", "stat": false},
	"reroll": {"name": "Refrescar", "desc": "+1 uso de Refrescar ofertas por partida.", "icon": "escape-rope", "stat": false},
	"skip": {"name": "Saltar", "desc": "+1 uso de Saltar mejora por partida (te da Pokédólares).", "icon": "x-speed", "stat": false},
	"banish": {"name": "Desterrar", "desc": "+1 uso de Desterrar: elimina una opción del resto de la partida.", "icon": "cleanse-tag", "stat": false},
	"dmg": {"name": "Entrenamiento", "desc": "+4% de daño por nivel.", "icon": "protein", "stat": true},
	"hp": {"name": "Resistencia", "desc": "+8 PS máximos por nivel.", "icon": "hp-up", "stat": true},
	"spd": {"name": "Agilidad", "desc": "+2.5% velocidad por nivel.", "icon": "carbos", "stat": true},
	"xp": {"name": "Estudio", "desc": "+5% experiencia por nivel.", "icon": "lucky-egg", "stat": true},
	"gold": {"name": "Comercio", "desc": "+8% Pokédólares por nivel.", "icon": "amulet-coin", "stat": true},
	"luck": {"name": "Fortuna", "desc": "+5 suerte por nivel.", "icon": "star-piece", "stat": true},
	"magnet": {"name": "Magnetismo", "desc": "+0.6 rango de recogida por nivel.", "icon": "magnet", "stat": true},
	"regen": {"name": "Restos", "desc": "+0.2 regeneración por nivel.", "icon": "leftovers", "stat": true},
	"armor": {"name": "Coraza", "desc": "+2 armadura por nivel.", "icon": "iron", "stat": true},
	"crit": {"name": "Precisión", "desc": "+1% probabilidad de crítico por nivel.", "icon": "scope-lens", "stat": true},
	"atkspd": {"name": "Celeridad", "desc": "+2% velocidad de ataque por nivel.", "icon": "quick-claw", "stat": true},
	"area": {"name": "Expansión", "desc": "+3% área por nivel.", "icon": "wide-lens", "stat": true},
	"revive": {"name": "Revivir", "desc": "Empiezas con un Revivir Máximo.", "icon": "max-revive", "stat": false},
	"research": {"name": "Investigación", "desc": "+25% progreso de investigación por nivel.", "icon": "poke-ball", "stat": false},
	"party": {"name": "Equipo de apoyo", "desc": "+1 hueco para Alfas capturados (de 2 a 3).", "icon": "great-ball", "stat": false},
	"ult": {"name": "Sintonía", "desc": "La Ultimate se carga un 4% más rápido por nivel.", "icon": "soul-dew", "stat": false},
	"bag": {"name": "Mochila grande", "desc": "Puedes llevarte 3 objetos de la Mochila a cada partida (en vez de 2).", "icon": "great-ball", "stat": false},
}

## `h` in the web screen: two groups in metadata order, tinted purple/blue.
const GROUPS := [
	{
		"title": "Entrenamiento",
		"sub": "Mejoras permanentes de estadísticas",
		"accent": "purple",
		"ids": ["dmg", "hp", "spd", "xp", "gold", "luck", "magnet", "regen", "armor", "crit", "atkspd", "area"],
	},
	{
		"title": "Equipo de partida",
		"sub": "Huecos, opciones y herramientas",
		"accent": "blue",
		"ids": ["slot-move", "slot-vit", "reroll", "skip", "banish", "revive", "research", "party", "ult", "bag"],
	},
]

const NOTES := "Mejoras permanentes: valen para todas tus partidas y todos tus Pokémon. Arriba, Entrenamiento (daño, PS, velocidad…); abajo, el equipo de partida. Cada nivel cuesta más que el anterior."
const SOURCE_NOTE := "数据来自 api-core.js 的 LAB 表；走 /lab/<id>/buy 路由。"

var _stardust: Label
var _rows := {}
var _hover_styles := {}
var _buy_styles := {}
var _grad_can := {}
var _grad_max := {}
var _grad_top_max := {}


func _ready() -> void:
	UI.fill(self)
	var scr := UI.screen()
	add_child(scr)
	UI.fill(scr)
	# .screen padding is 18px 24px 20px; .lab-wrap adds 4px 6px 10px around the grid.
	var root := UI.content(scr, 24)
	root.add_theme_constant_override("separation", 14)

	var head := UI.screen_head(App.ui("Laboratorio"), App.ui("Gasta tu Polvo Estelar"),
		func(): App.back_to_menu())
	root.add_child(head)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	head.add_child(_help_button())
	head.add_child(_currency_chip())

	var sc := UI.scroll()
	root.add_child(sc)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 4)
	wrap.add_theme_constant_override("margin_bottom", 10)
	wrap.add_theme_constant_override("margin_left", 6)
	wrap.add_theme_constant_override("margin_right", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(wrap)
	var groups := UI.vbox(18)  # .lab-wrap gap:18px
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(groups)

	var maxima := {}
	for row in Save.lab_table():
		var entry := PbJson.as_dict(row)
		maxima[str(entry["id"])] = int(entry["max"])

	var card_index := 0
	for g in GROUPS:
		var ids: Array = g["ids"]
		var group := _group(g)
		groups.add_child(group)
		var grid: GridContainer = group.get_meta("grid")
		for id in ids:
			if not maxima.has(id):
				continue
			var card := _card(id, int(maxima[id]), card_index, str(g["accent"]))
			grid.add_child(card)
			_tile_in(card, card_index)  # .lab-card animation:tileIn .35s var(--d,0s)
			card_index += 1

	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


# ---------------------------------------------------------------- chrome
func _currency_chip() -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = PbTheme.paper(1)  # --paper-2
	s.set_corner_radius_all(999)
	s.corner_detail = 12
	s.content_margin_left = 5
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	s.shadow_color = PbTheme.css_color("#1a124614", Color(0, 0, 0, 0.08))
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := UI.hbox(6)
	h.add_child(UI.icon_rect("stardust", 28))  # .currency img
	_stardust = UI.label("", 15, PbTheme.ink())  # .currency font-size 15/800
	_stardust.add_theme_font_override("font", PbTheme.font("title_bold"))
	_stardust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	h.add_child(_stardust)
	p.add_child(h)
	return p


## M-15: the port-only explainer moved out of the main flow into this popup.
func _help_button() -> Control:
	var b := UI.button("?", _show_notes, false, "ghost")
	b.custom_minimum_size = Vector2(34, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 18)
	b.tooltip_text = App.ui("Laboratorio")
	return b


func _show_notes() -> void:
	if has_node("Modal"):
		return
	var modal := UI.modal_shell(App.ui("Laboratorio"), true)
	var scrim: PanelContainer = modal["scrim"]
	var body: VBoxContainer = modal["body"]
	add_child(scrim)
	body.add_child(UI.paragraph(NOTES, 14, Color.WHITE, 3))
	body.add_child(UI.label(SOURCE_NOTE, 12, Color(1, 1, 1, 0.75)))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	row.add_child(UI.button(App.ui("Volver"), func(): scrim.queue_free(), false, "ghost"))


# ---------------------------------------------------------------- groups
## `.grp-head` (6px left border, 22px title, 13px sub) + `.lab-grid`.
func _group(g: Dictionary) -> Control:
	var box := UI.vbox(0)
	var head_margin := MarginContainer.new()
	head_margin.add_theme_constant_override("margin_top", 4)
	head_margin.add_theme_constant_override("margin_bottom", 10)
	var plate := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_width_left = 6
	s.border_color = PbTheme.accent_color(str(g["accent"]), "c")
	s.content_margin_left = 12
	plate.add_theme_stylebox_override("panel", s)
	var h := UI.hbox(10)
	head_margin.add_child(plate)
	plate.add_child(h)

	var title := UI.label(App.ui(str(g["title"])), 22, Color.WHITE)
	title.add_theme_font_override("font", PbTheme.font("title"))
	title.add_theme_color_override("font_shadow_color", PbTheme.css_color("#0009", Color(0, 0, 0, 0.6)))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	h.add_child(title)

	var sub := UI.label(App.ui(str(g["sub"])), 13, Color.WHITE)
	sub.add_theme_font_override("font", PbTheme.font("body_bold"))
	sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	h.add_child(sub)

	var grid := UI.grid(1, int(GRID_GAP))
	grid.name = "LabGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.set_meta("accent", str(g["accent"]))
	grid.resized.connect(func(): UI.autofill_columns(grid, MIN_COL, GRID_GAP))
	box.add_child(head_margin)
	box.add_child(grid)
	box.set_meta("grid", grid)
	return box


# ---------------------------------------------------------------- card
func _card(id: String, max_rank: int, index: int, accent: String) -> Control:
	var meta := PbJson.as_dict(META.get(id, {}))
	var accent_col := PbTheme.accent_color(accent, "c")
	var accent_hex := "#" + accent_col.to_html(false)

	var panel := PanelContainer.new()
	panel.name = "LabCard_" + id
	panel.custom_minimum_size = Vector2(MIN_COL, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := PbTheme.stylebox(".lab-card", {"--c": accent_hex})
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", s)
	panel.clip_contents = true
	var v := UI.vbox(0)
	panel.add_child(v)

	# .lab-top: 70px gradient band, stripe overlay, radius follows the card.
	var top := Control.new()
	top.name = "LabTop"
	top.custom_minimum_size = Vector2(0, TOP_H)
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := PbTheme.gradient(str(PbTheme.decls(".lab-top").get("background", "")),
		{"--c": accent_hex})
	band.setup(grad, null, true).corner = 20.0
	top.add_child(band)

	# .lab-ic: 54px paper disc translated 18px, 40px pixel art inside.
	var disc := PanelContainer.new()
	var disc_s := PbTheme.stylebox(".lab-ic")
	disc_s.set_corner_radius_all(27)
	disc_s.content_margin_left = 0
	disc_s.content_margin_right = 0
	disc_s.content_margin_top = 0
	disc_s.content_margin_bottom = 0
	disc.add_theme_stylebox_override("panel", disc_s)
	disc.anchor_left = 0.5
	disc.anchor_right = 0.5
	disc.offset_left = -ICON_SIZE * 0.5
	disc.offset_right = ICON_SIZE * 0.5
	var disc_top := (TOP_H - ICON_SIZE) * 0.5 + 18.0  # transform:translateY(18px)
	disc.offset_top = disc_top
	disc.offset_bottom = disc_top + ICON_SIZE
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_center := CenterContainer.new()
	art_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := UI.icon_rect(str(meta.get("icon", "")), int(ICON_ART))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_center.add_child(art)
	disc.add_child(art_center)
	top.add_child(disc)

	# .lab-lv: absolute top:8px right:10px pill.
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", PbTheme.stylebox(".lab-lv"))
	pill.anchor_left = 1.0
	pill.anchor_right = 1.0
	pill.offset_left = -10.0
	pill.offset_right = -10.0
	pill.offset_top = 8.0
	pill.offset_bottom = 8.0
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pill.grow_vertical = Control.GROW_DIRECTION_END
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_label := UI.label("", 12, PbTheme.ink())
	pill_label.add_theme_font_override("font", PbTheme.font("title"))
	pill_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.add_child(pill_label)
	top.add_child(pill)
	v.add_child(top)

	# .lab-bd: padding 24px 14px 10px, centred, gap 4.
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 24)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	v.add_child(body_margin)
	var body := UI.vbox(4)
	body_margin.add_child(body)

	var name_l := UI.label(App.ui(str(meta.get("name", id))), 18, PbTheme.ink())
	name_l.add_theme_font_override("font", PbTheme.font("title"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(name_l)

	var desc := UI.label(App.ui(str(meta.get("desc", ""))), 13,
		PbTheme.css_color(PbTheme.v("--ink-2", "#5a5478"), Color("#5a5478")))
	desc.add_theme_font_override("font", PbTheme.font("body"))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 13 * 1.35 * 2)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.resized.connect(UI.fit_wrapped_height.bind(desc))
	body.add_child(desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)

	# .pips: margin-top auto + padding-top 8, 18×6 bars, gap 4.
	var pips_margin := MarginContainer.new()
	pips_margin.add_theme_constant_override("margin_top", 8)
	body.add_child(pips_margin)
	var pips := UI.hbox(4)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips_margin.add_child(pips)
	var pip_fills: Array[Control] = []
	for i in max_rank:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(18, 6)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var off := PanelContainer.new()
		off.set_anchors_preset(Control.PRESET_FULL_RECT)
		var off_s := StyleBoxFlat.new()
		off_s.bg_color = PbTheme.css_color(PbTheme.v("--line", "#e4e0f0"), Color("#e4e0f0"))
		off_s.set_corner_radius_all(6)
		off.add_theme_stylebox_override("panel", off_s)
		off.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(off)
		var on := PbWidgets.GradRect.new()
		on.set_anchors_preset(Control.PRESET_FULL_RECT)
		on.setup(PbTheme.gradient("linear-gradient(90deg, var(--orange), var(--yellow))"), null, false)
		on.corner = 3.0
		on.visible = false
		slot.add_child(on)
		pip_fills.append(on)
		pips.add_child(slot)

	# .lab-buy with its margin 4px 12px 12px.
	var buy_margin := MarginContainer.new()
	buy_margin.add_theme_constant_override("margin_left", 12)
	buy_margin.add_theme_constant_override("margin_right", 12)
	buy_margin.add_theme_constant_override("margin_top", 4)
	buy_margin.add_theme_constant_override("margin_bottom", 12)
	v.add_child(buy_margin)
	var buy := _buy_button(id)
	buy_margin.add_child(buy)
	var buy_bg := PbWidgets.GradRect.new()
	buy_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	buy_bg.offset_bottom = -4.0
	buy_bg.corner = 999.0
	buy_bg.visible = false
	buy.add_child(buy_bg)
	var buy_content := CenterContainer.new()
	buy_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	buy_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy.add_child(buy_content)

	var row := {
		"max": max_rank,
		"id": id,
		"panel": panel,
		"normal": s,
		"band": band,
		"grad": grad,
		"pill": pill_label,
		"pips": pip_fills,
		"buy": buy,
		"buy_bg": buy_bg,
		"buy_content": buy_content,
		"state": "",
		"hover": false,
		"rest_y": 0.0,
		"accent": accent_hex,
	}
	_rows[id] = row
	_ignore_mouse(v)
	buy.mouse_filter = Control.MOUSE_FILTER_STOP
	buy.mouse_entered.connect(_set_hover.bind(row, true))
	buy.mouse_exited.connect(_clear_hover_deferred.bind(row))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_entered.connect(_set_hover.bind(row, true))
	panel.mouse_exited.connect(_clear_hover_deferred.bind(row))
	panel.set_meta("tile_i", index)
	return panel


func _buy_button(id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)  # padding 9 + icon 20 + padding 9
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): _buy(id))
	b.mouse_entered.connect(func():
		if is_instance_valid(b) and _rows.get(id, {}).get("state", "") == "can":
			b.modulate = Color(1.08, 1.08, 1.08)  # .lab-buy.can:hover filter:brightness(1.08)
	)
	b.mouse_exited.connect(func():
		if is_instance_valid(b):
			b.modulate = Color.WHITE
	)
	return b


# ---------------------------------------------------------------- state
func refresh() -> void:
	var wallet := int(Save.store.get("stardust", 0))
	_stardust.text = UI.fmt_num(float(wallet))
	for id in _rows.keys():
		var row: Dictionary = _rows[id]
		var rank := Save.lab(str(id))
		var max_rank := int(row["max"])
		# The ported route charges 10*(rank+1); the web UI labels the metadata
		# price table, which the offline API does not charge (see reply notes).
		var cost := 10 * (rank + 1)
		var maxed := rank >= max_rank
		var afford := wallet >= cost
		var state := "max" if maxed else ("can" if afford else "plain")

		var pill: Label = row["pill"]
		pill.text = App.ui("MÁX.") if maxed else App.ui("Nv. {n}/{max}", {"n": rank, "max": max_rank})

		var fills: Array = row["pips"]
		for i in fills.size():
			(fills[i] as Control).visible = i < rank

		var band: PbWidgets.GradRect = row["band"]
		if maxed and not bool(row.get("band_max", false)):
			row["band_max"] = true
			band.setup(_top_max_gradient(), null, true)
		elif not maxed and bool(row.get("band_max", false)):
			row["band_max"] = false
			band.setup(row["grad"], null, true)

		_apply_buy_state(row, state, cost)


func _apply_buy_state(row: Dictionary, state: String, cost: int) -> void:
	var buy: Button = row["buy"]
	var bg: PbWidgets.GradRect = row["buy_bg"]
	var content: CenterContainer = row["buy_content"]

	if state != str(row["state"]):
		row["state"] = state
		for child in content.get_children():
			content.remove_child(child)
			child.queue_free()

	var styles := _buy_style_set()
	var style: StyleBoxFlat = styles["plain"]
	if state == "can":
		style = styles["can"]
	elif state == "max":
		style = styles["max"]
	buy.add_theme_stylebox_override("normal", style)
	buy.add_theme_stylebox_override("hover", style)
	buy.add_theme_stylebox_override("pressed", style)
	buy.disabled = false

	if state == "can":
		# .lab-buy.can background is a stripe + green gradient (not expressible
		# by StyleBoxFlat); GradRect paints it above the transparent box.
		row["buy_bg"].visible = true
		bg.setup(_buy_gradient("can"), null, true)
		bg.offset_bottom = -4.0
		buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif state == "max":
		bg.visible = true
		bg.setup(_buy_gradient("max"), null, false)
		bg.offset_bottom = -3.0
		buy.mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		bg.visible = false
		buy.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN  # cursor:not-allowed

	if content.get_child_count() == 0:
		var h := UI.hbox(6)  # .lab-buy gap 6
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_child(h)
		if state == "max":
			h.add_child(UI.icon_rect("check", 18))
			h.add_child(_buy_label(App.ui("Completado"), PbTheme.css_color(PbTheme.v("--ink-on", "#2a2440"), Color("#2a2440"))))
		else:
			h.add_child(UI.icon_rect("stardust", 20))
			h.add_child(_buy_label(UI.fmt_num(float(cost)), Color.WHITE))
	else:
		var h := content.get_child(0) as HBoxContainer
		var label := h.get_child(1) as Label
		if label != null:
			label.text = App.ui("Completado") if state == "max" else UI.fmt_num(float(cost))

	var label2 := content.get_child(0).get_child(1) as Label
	if label2 != null:
		label2.add_theme_color_override("font_color",
			PbTheme.css_color(PbTheme.v("--ink-on", "#2a2440"), Color("#2a2440")) if state == "max" else Color.WHITE)


func _buy_label(text: String, color: Color) -> Label:
	var l := UI.label(text, 17, color)  # .lab-buy font-size 17/900
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l


func _buy_style_set() -> Dictionary:
	if _buy_styles.is_empty():
		var base := PbTheme.stylebox(".lab-buy")
		# .lab-buy.can / .lab-buy.max only override background + box-shadow; the
		# pill radius and padding stay on .lab-buy, so duplicate it first.
		var can := base.duplicate() as StyleBoxFlat
		can.bg_color = Color(0, 0, 0, 0)
		can.set_border_width_all(0)
		can.border_width_bottom = 4
		can.border_color = PbTheme.css_color("#157a3a", Color("#157a3a"))
		var maxs := base.duplicate() as StyleBoxFlat
		maxs.bg_color = Color(0, 0, 0, 0)
		maxs.set_border_width_all(0)
		maxs.border_width_bottom = 3
		maxs.border_color = PbTheme.css_color("#b07a00", Color("#b07a00"))
		_buy_styles = {"plain": base, "can": can, "max": maxs}
	return _buy_styles


func _buy_gradient(kind: String) -> Dictionary:
	if kind == "can":
		if _grad_can.is_empty():
			_grad_can = PbTheme.gradient(str(PbTheme.decls(".lab-buy.can").get("background", "")))
		return _grad_can
	if _grad_max.is_empty():
		_grad_max = PbTheme.gradient(str(PbTheme.decls(".lab-buy.max").get("background", "")))
	return _grad_max


func _top_max_gradient() -> Dictionary:
	if _grad_top_max.is_empty():
		_grad_top_max = PbTheme.gradient(str(PbTheme.decls(".lab-card.max .lab-top").get("background", "")))
	return _grad_top_max


# ---------------------------------------------------------------- interaction
func _set_hover(row: Dictionary, on: bool) -> void:
	if bool(row.get("hover", false)) == on:
		return
	row["hover"] = on
	var panel: Control = row["panel"]
	var target := 0.0
	if on:
		row["rest_y"] = panel.position.y
		target = float(row["rest_y"]) - 4.0  # .lab-card:hover transform:translateY(-4px)
		panel.add_theme_stylebox_override("panel", _hover_style(str(row["accent"])))
	else:
		target = float(row["rest_y"])
		panel.add_theme_stylebox_override("panel", row["normal"])
	if row.has("tw") and row["tw"] != null and (row["tw"] as Tween).is_valid():
		(row["tw"] as Tween).kill()
	var tw := panel.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	row["tw"] = tw
	tw.tween_property(panel, "position:y", target, 0.14)  # transition:.14s cubic-bezier(.3,1.6,.5,1)


## The buy button sits on top of the card, so a plain exited signal fires when
## the pointer moves onto it. Re-check the card rect instead of dropping hover.
func _clear_hover_deferred(row: Dictionary) -> void:
	if not is_instance_valid(row["panel"]):
		return
	if (row["panel"] as Control).get_global_rect().has_point(get_global_mouse_position()):
		return
	_set_hover(row, false)


## `.lab-card:hover{box-shadow:0 0 0 3px var(--c), var(--shadow)}` -- StyleBoxFlat
## carries one shadow, so the ring replaces the resting shadow.
func _hover_style(accent_hex: String) -> StyleBoxFlat:
	if _hover_styles.has(accent_hex):
		return _hover_styles[accent_hex]
	var base := PbTheme.stylebox(".lab-card", {"--c": accent_hex})
	base.content_margin_left = 0
	base.content_margin_right = 0
	base.content_margin_top = 0
	base.content_margin_bottom = 0
	var s := UI.hover_ring_style(base, PbTheme.css_color(accent_hex,
		PbTheme.accent_color("purple", "c")), 3)
	_hover_styles[accent_hex] = s
	return s


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
		# CSS @keyframes bought: scale .92 -> 1.06 -> 1 (0.6s).
		var entry := PbJson.as_dict(_rows.get(id, {}))
		var panel := entry.get("panel") as Control
		if panel != null:
			panel.pivot_offset = panel.size * 0.5
			var tw := panel.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			panel.scale = Vector2(0.92, 0.92)
			tw.tween_property(panel, "scale", Vector2(1.06, 1.06), 0.2)
			tw.tween_property(panel, "scale", Vector2.ONE, 0.4)
	refresh()


# ---------------------------------------------------------------- helpers
## Container children would eat the card's mouse_entered; only the buy button
## keeps input, and it re-arms hover through the deferred rect check.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


## CSS @keyframes tileIn: .35s, delay index*.03, from opacity 0 / scale .85.
func _tile_in(card: Control, index: int) -> void:
	card.modulate.a = 0.0
	card.pivot_offset = card.get_combined_minimum_size() * 0.5
	card.scale = Vector2(0.85, 0.85)
	var tw := card.create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_interval(float(index) * 0.03)
	tw.tween_property(card, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.35)
