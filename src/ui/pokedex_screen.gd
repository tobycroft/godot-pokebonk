extends Control
## Pokédex screen, rebuilt against the web `.dx` view
## (assets/main-oZVl1tJD-mvpjh5lt.css + main-C5MieX6g-mvpjh5lt.js).
##
## Left: `.dx-search` + generation seg + `.dx-types` filter row + `.dx-grid`
## (repeat(auto-fill, minmax(84px, 1fr)) emulated by a width-driven column count)
## with the four `.dx-tile` states (cap / on / unk / shiny mark).
## Right: `.dx-info` with the `.dx-show` showcase card (`.ls-show` gradient,
## `.ls-num`, `.ls-stage` sprite + `.ls-plate`), the `.dx-shiny` toggle and the
## web's base-stat rows.
##
## Values come from ui_theme.json wherever the rule shipped (`_px()`); the
## remaining skin helpers stay local to this screen on purpose (parallel UI work
## is editing pb_theme/ui_kit). They are listed for a later ui_kit merge.

const DEX_SHADER := preload("res://assets/ui/pokedex_sprite.gdshader")

## Web JS passes these for an unseen species (`.dx-show` --c/--c2 fallback).
const UNSEEN_C1 := "#6a6488"
const UNSEEN_C2 := "#2e2a48"

var _gen := 1
var _status := "all"
var _query := ""
var _type := ""
var _selected := 0
var _selected_shiny := false

var _detail: VBoxContainer
var _grid: GridContainer
var _empty: Control
var _search: LineEdit
var _scroll: ScrollContainer
var _count: Label
var _types_row: HFlowContainer
var _tiles := {}          # species id -> tile entry dictionary
var _type_buttons := {}   # type id -> {btn, ring}
var _cell := 84.0
var _min_tile := 84.0
var _gap := 8.0
var _syncing := false


func _ready() -> void:
	UI.fill(self)
	var root := UI.screen()
	add_child(root)
	UI.fill(root)
	var column := UI.content(root, 18)

	column.add_child(UI.screen_head(App.ui("Pokédex"),
		App.ui("{n}/{total} vistos", {"n": _seen_count(), "total": PbData.kanto_ids().size()}),
		func(): App.back_to_menu()))

	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	_min_tile = _grid_min_px()
	_gap = _px(".dx-grid", "gap", 8.0)
	row.add_child(_build_left())
	row.add_child(_build_right())

	_selected = int(PbData.kanto_ids()[0])
	# Web initialises the shiny toggle once, from the initially selected species
	# (`p = profile.shinies.includes(t)`) and keeps it across selections.
	_selected_shiny = _has_shiny(_selected)
	_rebuild_grid()
	_show(_selected)
	_apply_selected_tile()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


# --------------------------------------------------------------- left column
func _build_left() -> Control:
	var left := UI.panel(int(_px(".dx-left", "padding", 14.0)))
	left.name = "DxLeft"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UI.vbox(int(_px(".dx-left", "gap", 10.0)))
	left.add_child(col)

	# .dx-bar: search + `.seg` status filter + .dx-count (flex-wrap:wrap).
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", int(_px(".dx-bar", "gap", 10.0)))
	bar.add_theme_constant_override("v_separation", 6)
	col.add_child(bar)

	_search = UI.field(App.ui("Buscar por nombre o número…"))
	_search.custom_minimum_size = Vector2(200, 0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", int(_px(".dx-search", "font-size", 15.0)))
	_search.text_changed.connect(func(t): _query = t.strip_edges().to_lower(); _rebuild_grid())
	bar.add_child(_search)

	# Web `.dx-bar .seg`: [[all,Todos],[seen,Vistos],[caught,Capturados],
	# [shiny,Variocolor]].
	var status_items := [
		{"id": "all", "text": App.ui("Todos")},
		{"id": "seen", "text": App.ui("Vistos")},
		{"id": "caught", "text": App.ui("Capturados")},
		{"id": "shiny", "text": App.ui("Variocolor")},
	]
	bar.add_child(UI.segment(status_items, _status, func(id): _set_status(id)))

	_count = UI.label("", int(_px(".dx-count", "font-size", 12.0)), PbTheme.ink_muted())
	_count.name = "DxCount"
	_count.add_theme_font_override("font", PbTheme.font("title_bold"))
	bar.add_child(_count)

	# Generation tabs stay as an extra filter next to the web's status seg.
	var gen_items := []
	for gen in [1, 2, 3, 4]:
		gen_items.append({"id": str(gen), "text": App.ui("Gen {n}", {"n": gen})})
	bar.add_child(UI.segment(gen_items, str(_gen), func(id): _set_gen(int(id))))

	# .dx-types: 26px type icons (JE(e,26)), dimmed until picked, 3px yellow
	# ring + scale 1.18 when on.
	_types_row = HFlowContainer.new()
	_types_row.name = "DxTypes"
	_types_row.add_theme_constant_override("h_separation", 4)
	_types_row.add_theme_constant_override("v_separation", 4)
	col.add_child(_types_row)
	for type_id in PbData.type_names():
		var built := _type_button(str(type_id))
		_types_row.add_child(built["btn"])
		_type_buttons[str(type_id)] = built

	# .dx-grid scroll area: 6px 4px padding, 8px gutters.
	_scroll = UI.scroll()
	_scroll.name = "DxScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := _grid_padding()
	wrap.add_theme_constant_override("margin_left", int(pad.x))
	wrap.add_theme_constant_override("margin_right", int(pad.x))
	wrap.add_theme_constant_override("margin_top", int(pad.y))
	wrap.add_theme_constant_override("margin_bottom", int(pad.y))
	_scroll.add_child(wrap)
	var host := UI.vbox(0)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(host)

	# .dx-empty: 48px ball + centred caption.
	var empty_wrap := MarginContainer.new()
	empty_wrap.add_theme_constant_override("margin_left", 50)
	empty_wrap.add_theme_constant_override("margin_right", 50)
	empty_wrap.add_theme_constant_override("margin_top", 50)
	empty_wrap.add_theme_constant_override("margin_bottom", 50)
	var empty_col := UI.vbox(8)
	empty_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var empty_icon := UI.icon_rect("poke-ball", 48)
	empty_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty_col.add_child(empty_icon)
	var empty_text := UI.label(App.ui("Ningún Pokémon coincide con la búsqueda."),
		int(_px(".dx-entry", "font-size", 14.0)), PbTheme.ink_muted())
	empty_text.add_theme_font_override("font", PbTheme.font("body_bold"))
	empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_col.add_child(empty_text)
	empty_wrap.add_child(empty_col)
	empty_wrap.visible = false
	host.add_child(empty_wrap)
	_empty = empty_wrap

	_grid = GridContainer.new()
	_grid.name = "DxGrid"
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(_gap))
	_grid.add_theme_constant_override("v_separation", int(_gap))
	_grid.resized.connect(_sync_columns)
	host.add_child(_grid)
	return left


func _type_button(type_id: String) -> Dictionary:
	var btn := Button.new()
	btn.name = "Type_%s" % type_id
	# .dx-type: padding 2px around the 26px icon (JE(e,26)).
	btn.custom_minimum_size = Vector2(30, 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = PbData.localized_name("types", type_id, App.locale)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	btn.pivot_offset = Vector2(15, 15)
	# Inner art node so the hover `translateY(-2px)` does not fight the row's
	# layout (the container owns the button's position).
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(art)
	var icon := _type_icon(type_id, 26)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(icon)
	var ring := Panel.new()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0, 0, 0, 0)
	rs.border_color = PbTheme.accent_color("yellow", "c")
	rs.set_border_width_all(3)
	rs.set_corner_radius_all(99)
	ring.add_theme_stylebox_override("panel", rs)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = -3
	ring.offset_top = -3
	ring.offset_right = 3
	ring.offset_bottom = 3
	ring.visible = false
	art.add_child(ring)
	btn.pressed.connect(_set_type.bind(type_id))
	btn.mouse_entered.connect(_type_hover.bind(art, type_id, true))
	btn.mouse_exited.connect(_type_hover.bind(art, type_id, false))
	btn.modulate.a = 0.5
	return {"btn": btn, "ring": ring}


func _type_hover(art: Control, type_id: String, inside: bool) -> void:
	# .dx-type:hover{opacity:.85;transform:translateY(-2px)}
	if type_id == _type:
		return
	art.get_parent().modulate.a = 0.85 if inside else 0.5
	var tw := art.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "position:y", -2.0 if inside else 0.0, 0.14)


func _set_type(type_id: String) -> void:
	# Web: `d = d === e ? "" : e` -- clicking the active type clears it.
	_type = "" if _type == type_id else type_id
	for key in _type_buttons.keys():
		var item: Dictionary = _type_buttons[key]
		var btn: Button = item["btn"]
		var on := str(key) == _type
		(item["ring"] as Panel).visible = on
		btn.modulate.a = 1.0 if on else 0.5
		btn.scale = Vector2.ONE * (1.18 if on else 1.0)
	_rebuild_grid()


func _set_gen(gen: int) -> void:
	_gen = gen
	_rebuild_grid()


func _set_status(status: String) -> void:
	_status = status
	_rebuild_grid()


func _grid_padding() -> Vector2:
	var parts := str(PbTheme.decls(".dx-grid").get("padding", "")).split(" ", false)
	var v := parts[0].to_float() if parts.size() > 0 else 6.0
	var h := parts[1].to_float() if parts.size() > 1 else 4.0
	if h <= 0.0:
		h = 4.0
	if v <= 0.0:
		v = 6.0
	return Vector2(h, v)


# -------------------------------------------------------------- tile grid
func _matching_ids() -> Array:
	var ids: Array = PbData.dex_ids(_gen)
	var out := []
	for id in ids:
		var sid := int(id)
		var species := PbData.species(sid)
		# Web status filter: all / seen / caught / shiny (shiny or classic mark).
		var seen := _is_seen(sid)
		if _status == "seen" and not seen:
			continue
		if _status == "caught" and not _is_captured(sid):
			continue
		if _status == "shiny" and not (_has_shiny(sid) or _has_classic(sid)):
			continue
		if not _type.is_empty():
			# Web: type filter only matches species the player has already seen.
			if not (seen and _has_type(species, _type)):
				continue
		if not _query.is_empty():
			if _query.is_valid_int():
				if sid != int(_query):
					continue
			elif not (seen and _name(species, sid).to_lower().contains(_query)):
				continue
		out.append(sid)
	return out


func _rebuild_grid() -> void:
	_clear(_grid)
	_tiles.clear()
	var ids := _matching_ids()
	_count.text = App.ui("{n} Pokémon", {"n": ids.size()})
	_empty.visible = ids.is_empty()
	_grid.visible = not ids.is_empty()
	for id in ids:
		var entry := _tile(int(id))
		_grid.add_child(entry["cell"])
		_tiles[int(id)] = entry
	_sync_columns.call_deferred()
	_apply_selected_tile()


func _sync_columns() -> void:
	if _syncing:
		return
	var width := _grid.size.x
	if width <= _min_tile:
		return
	var cols := maxi(1, int(floor((width + _gap) / (_min_tile + _gap))))
	if cols != _grid.columns:
		_syncing = true
		_grid.columns = cols
		_syncing = false
	_cell = maxf(1.0, (width - _gap * float(cols - 1)) / float(cols))
	for entry in _tiles.values():
		(entry["cell"] as Control).custom_minimum_size = Vector2(_cell, _cell)


## `.dx-tile`: 4 states -- seen (lit gradient), captured (ball badge), unseen
## (grey `.unk` + white silhouette) and shiny (gradient star at the top-left).
func _tile(species_id: int) -> Dictionary:
	var species := PbData.species(species_id)
	var seen := _is_seen(species_id)
	var captured := _is_captured(species_id)
	var shiny := _has_shiny(species_id)
	var types := PbJson.as_array(species.get("types", ["normal"]))

	var cell := Control.new()
	cell.name = "Tile%d" % species_id
	cell.custom_minimum_size = Vector2(_cell, _cell)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.tooltip_text = _name(species, species_id) if seen else "???"
	cell.gui_input.connect(_tile_input.bind(species_id))
	cell.mouse_entered.connect(_tile_hover.bind(species_id, true))
	cell.mouse_exited.connect(_tile_hover.bind(species_id, false))

	# Inner gfx node owns the hover/selection scale so the grid keeps layout.
	var gfx := Control.new()
	gfx.name = "Gfx"
	gfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gfx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gfx.pivot_offset = Vector2(_cell, _cell) * 0.5
	cell.add_child(gfx)
	cell.resized.connect(func(): gfx.pivot_offset = cell.size * 0.5)

	# .dx-tile.on ring: 0 0 0 3px paper + 0 0 0 6px yellow.
	var radius := float(PbTheme.radius_tile())
	var ring_y := Panel.new()
	var ry := StyleBoxFlat.new()
	ry.bg_color = PbTheme.accent_color("yellow", "c")
	ry.set_corner_radius_all(int(radius) + 6)
	ring_y.add_theme_stylebox_override("panel", ry)
	ring_y.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_y.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_y.offset_left = -6
	ring_y.offset_top = -6
	ring_y.offset_right = 6
	ring_y.offset_bottom = 6
	ring_y.visible = false
	gfx.add_child(ring_y)
	var ring_p := Panel.new()
	var rp := StyleBoxFlat.new()
	rp.bg_color = PbTheme.css_color(PbTheme.v("--paper", "#ffffff"), Color.WHITE)
	rp.set_corner_radius_all(int(radius) + 3)
	ring_p.add_theme_stylebox_override("panel", rp)
	ring_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_p.offset_left = -3
	ring_p.offset_top = -3
	ring_p.offset_right = 3
	ring_p.offset_bottom = 3
	ring_p.visible = false
	gfx.add_child(ring_p)

	var rule := ".dx-tile" if seen else ".dx-tile.unk"
	var vars := {}
	if seen:
		var c := PbTheme.type_color(str(types[0])) if not types.is_empty() else PbTheme.type_color("normal")
		vars = {"--c": "#" + c.to_html(false)}
	# `.dx-tile` shadow/inset lives in the token's stylebox; a Panel paints it
	# under the gradient (StyleBoxFlat.draw inside custom _draw is noisy in
	# headless).
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-tile"))
	gfx.add_child(box)
	var grad := PbWidgets.GradRect.new()
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.corner = radius
	grad.setup(PbTheme.gradient(PbTheme.rule(rule), vars), null, false)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gfx.add_child(grad)

	# `.dx-tile.on` paints the pale-yellow radial over both the seen and the
	# `.unk` background (`.dx-tile.on` comes later in the sheet).
	var on_grad := PbWidgets.GradRect.new()
	on_grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_grad.corner = radius
	on_grad.setup(PbTheme.gradient(PbTheme.rule(".dx-tile.on")), null, false)
	on_grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	on_grad.visible = false
	gfx.add_child(on_grad)

	# Sprite: absolute inset 9% 9% 15%, exactly like `.dx-tile>img:first-child`.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.09
	holder.anchor_top = 0.09
	holder.anchor_right = 0.91
	holder.anchor_bottom = 0.85
	gfx.add_child(holder)
	var spr := PmdSprite.new()
	spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spr.setup(species_id, "idle", 1.0)
	spr.custom_minimum_size = Vector2.ZERO
	holder.add_child(spr)
	spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not seen:
		# `.dx-tile.unk>canvas:first-child`: brightness(0) invert() opacity(.2).
		spr.material = _sprite_filter(0.0, true, true, 0.2)

	# `.dx-tile small`: bottom 3px left 7px, 10px/900.
	var num := UI.label("%03d" % species_id, int(_px(".dx-tile small", "font-size", 10.0)), PbTheme.ink_muted())
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_override("font", PbTheme.font("body_bold"))
	num.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	num.offset_left = 7
	num.offset_top = -16
	num.offset_right = 61
	num.offset_bottom = -3
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gfx.add_child(num)

	if captured:
		var ball := UI.icon_rect("poke-ball", 18)
		ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ball.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		ball.offset_left = -22
		ball.offset_top = 4
		ball.offset_right = -4
		ball.offset_bottom = 22
		gfx.add_child(ball)
	if shiny:
		var mark := DexShinyMark.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.gradient_stops = _shiny_stops()
		mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		mark.offset_left = 5
		mark.offset_top = 5
		mark.offset_right = 19
		mark.offset_bottom = 19
		gfx.add_child(mark)

	return {
		"cell": cell, "gfx": gfx, "ring_y": ring_y, "ring_p": ring_p,
		"on_grad": on_grad,
	}


func _tile_input(event: InputEvent, species_id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(species_id)


func _tile_hover(species_id: int, inside: bool) -> void:
	var entry: Dictionary = _tiles.get(species_id, {})
	if entry.is_empty():
		return
	var selected := species_id == _selected
	if inside:
		if not selected:
			# .dx-tile:hover{transform:translateY(-3px) scale(1.05)}
			_scale_tile(entry["gfx"], 1.05, -3.0)
			(entry["gfx"] as Control).z_index = 2
	else:
		_scale_tile(entry["gfx"], 1.08 if selected else 1.0)
		(entry["gfx"] as Control).z_index = 3 if selected else 0


func _select(species_id: int) -> void:
	if species_id == _selected:
		return
	var prev: Dictionary = _tiles.get(_selected, {})
	if not prev.is_empty():
		_apply_tile_state(prev, false)
	_selected = species_id
	# Web `C()`: `p = profile.shinies.includes(e)` whenever the tile changes.
	_selected_shiny = _has_shiny(species_id)
	var entry: Dictionary = _tiles.get(species_id, {})
	if not entry.is_empty():
		_apply_tile_state(entry, true)
		_scroll.ensure_control_visible.call_deferred(entry["cell"])
	_show(species_id)


func _apply_selected_tile() -> void:
	var entry: Dictionary = _tiles.get(_selected, {})
	if not entry.is_empty():
		_apply_tile_state(entry, true)


func _apply_tile_state(entry: Dictionary, on: bool) -> void:
	(entry["ring_y"] as Panel).visible = on
	(entry["ring_p"] as Panel).visible = on
	(entry["on_grad"] as Control).visible = on
	var gfx: Control = entry["gfx"]
	gfx.z_index = 3 if on else 0
	_scale_tile(gfx, 1.08 if on else 1.0)


func _scale_tile(gfx: Control, factor: float, offset_y: float = 0.0) -> void:
	var running = gfx.get_meta("scale_tween") if gfx.has_meta("scale_tween") else null
	if running is Tween and running.is_valid():
		running.kill()
	var tw := gfx.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(gfx, "scale", Vector2.ONE * factor, 0.14)
	tw.tween_property(gfx, "position:y", offset_y, 0.14)
	gfx.set_meta("scale_tween", tw)


# ------------------------------------------------------------- right column
func _build_right() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DxInfo"
	var style := PbTheme.card_style()
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := UI.scroll()
	panel.add_child(sc)
	_detail = UI.vbox(12)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_detail)
	return panel


func _show(species_id: int) -> void:
	_selected = species_id
	_clear(_detail)
	var species := PbData.species(species_id)
	if species.is_empty():
		return
	var seen := _is_seen(species_id)
	var captured := _is_captured(species_id)
	var shiny := _has_shiny(species_id)

	_detail.add_child(_show_card(species, species_id, seen, shiny))
	if not seen:
		_detail.add_child(_entry(App.ui("No hay datos de este Pokémon. Encuéntralo en una partida para registrarlo en tu Pokédex.")))
		return

	var flavor := App.t("flavor", species_id, str(species.get("flavor", "")))
	if not flavor.is_empty():
		_detail.add_child(_entry(flavor))
	_detail.add_child(_facts(species, captured, shiny))

	_detail.add_child(_tag(App.ui("Estadísticas base")))
	var stats := PbJson.as_dict(species.get("stats", {}))
	var bars := UI.vbox(4)
	_detail.add_child(bars)
	var stat_labels := {"hp": "PS", "atk": "Ataque", "def": "Defensa",
		"spa": "At. Esp.", "spd": "Def. Esp.", "spe": "Velocidad"}
	for key in ["hp", "atk", "def", "spa", "spd", "spe"]:
		bars.add_child(_stat_row(App.ui(str(stat_labels[key])), int(stats.get(key, 0))))

	# `.dx-ms` move rows keep the port's live dps estimate from PbDamage.
	_detail.add_child(_tag(App.ui("Ataques")))
	var actor := PbActor.create(species_id)
	var moves := PbMoves.learnable_moves(species_id)
	var scored := []
	for key in moves:
		var def := PbMoves.resolve(str(key))
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
	Audio.play_cry(species_id)


## `.dx-show` = the `.ls-show` showcase card: 300px tall, type-radial gradient,
## inset white ring, 90px `#NNN`, `.ls-stage` sprite and the skewed `.ls-plate`.
func _show_card(species: Dictionary, species_id: int, seen: bool, shiny: bool) -> Control:
	var show := Control.new()
	show.name = "DXShow"
	show.clip_contents = true
	show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	show.custom_minimum_size = Vector2(0, _px(".dx-show", "height", 300.0))
	var height := show.custom_minimum_size.y

	var types := PbJson.as_array(species.get("types", ["normal"]))
	var c1: Color = PbTheme.css_color(UNSEEN_C1) if not seen else PbTheme.type_color(str(types[0]))
	var c2: Color = PbTheme.css_color(UNSEEN_C2)
	if seen:
		c2 = PbTheme.type_color(str(types[1])) if types.size() > 1 else c1
	var vars := {"--c": "#" + c1.to_html(false), "--c2": "#" + c2.to_html(false)}

	var grad := PbWidgets.GradRect.new()
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.corner = _px(".ls-show", "border-radius", 26.0)
	grad.setup(PbTheme.gradient(PbTheme.rule(".ls-show"), vars), null, false)
	show.add_child(grad)

	# `box-shadow: var(--shadow), inset 0 0 0 4px #ffffff8c` from the token.
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.add_theme_stylebox_override("panel", PbTheme.stylebox(".ls-show"))
	show.add_child(ring)

	# `.dx-show .ls-num`: top 4px right 22px, #fff3.
	var num := UI.title("#%03d" % species_id, int(_px(".dx-show .ls-num", "font-size", 90.0)))
	num.add_theme_color_override("font_color", PbTheme.css_color("#fff3"))
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	num.offset_left = -420
	num.offset_top = 4
	num.offset_right = -22
	num.offset_bottom = 120
	show.add_child(num)

	# `.dx-show .ls-stage`: inset top 2% / bottom 42%.
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.anchor_left = 0.0
	stage.anchor_top = 0.02
	stage.anchor_right = 1.0
	stage.anchor_bottom = 0.58
	show.add_child(stage)

	var pedestal := PbWidgets.GradRect.new()
	pedestal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedestal.anchor_left = 0.19
	pedestal.anchor_top = 1.0
	pedestal.anchor_right = 0.81
	pedestal.anchor_bottom = 1.0
	pedestal.offset_top = -17
	pedestal.offset_bottom = 17
	pedestal.corner = 99.0
	pedestal.setup(PbTheme.gradient(PbTheme.rule(".ls-pedestal")), null, false)
	stage.add_child(pedestal)

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_top = -0.10
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.27
	stage.add_child(holder)
	var spr := PmdSprite.new()
	spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spr.setup(species_id, "idle", 1.0)
	spr.custom_minimum_size = Vector2.ZERO
	holder.add_child(spr)
	spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not seen:
		# Web showcase silhouette: brightness(0) opacity(.6).
		spr.material = _sprite_filter(0.0, true, false, 0.6)
	elif _selected_shiny and shiny:
		spr.material = _sprite_filter(_hue_degrees(species_id), false, false, 1.0)

	# `.ls-plate`: paper plate, 8px type border, skew(-8deg), bottom-left 18px.
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", PbTheme.stylebox(".ls-plate", vars))
	plate.rotation = deg_to_rad(-8.0)
	var pv := UI.vbox(5)
	pv.rotation = deg_to_rad(8.0)
	plate.add_child(pv)

	var sub := ""
	if seen:
		var gen := int(species.get("gen", 1))
		if bool(species.get("legendary", false)):
			sub = App.ui("Gen {n} · Legendario", {"n": gen})
		elif bool(species.get("mythical", false)):
			sub = App.ui("Gen {n} · Singular", {"n": gen})
		else:
			sub = App.ui("Gen {n}", {"n": gen})
	else:
		sub = App.ui("Sin registrar")
	var sub_label := UI.label(sub, int(_px(".ls-plate small", "font-size", 12.0)), PbTheme.ink_muted())
	sub_label.add_theme_font_override("font", PbTheme.font("title_bold"))
	pv.add_child(sub_label)

	var name_text := _name(species, species_id) if seen else "???"
	var name_label := UI.title(name_text, int(_px(".dx-show .ls-plate h1", "font-size", 32.0)))
	pv.add_child(name_label)

	if seen:
		var types_row := UI.hbox(6)
		for type_id in types:
			types_row.add_child(UI.type_chip(str(type_id)))
		pv.add_child(types_row)
	else:
		var foot := UI.label(App.ui("Aún no lo has encontrado"),
			int(_px(".dx-entry", "font-size", 14.0)), PbTheme.ink())
		foot.add_theme_font_override("font", PbTheme.font("body_bold"))
		pv.add_child(foot)

	plate.reset_size()
	plate.position = Vector2(18, height - 18 - plate.size.y)
	show.add_child(plate)
	if shiny:
		show.add_child(_shiny_pill())
	return show


## `.dx-shiny`: white pill; when on it switches to the pink→purple→blue gradient.
func _shiny_pill() -> Control:
	var pill := Button.new()
	pill.name = "DXShiny"
	pill.focus_mode = Control.FOCUS_NONE
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pill.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	pill.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	pill.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	pill.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pill.tooltip_text = App.ui("Variocolor")

	var white := Panel.new()
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	white.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-shiny"))
	pill.add_child(white)

	var grad := PbWidgets.GradRect.new()
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.corner = 99.0
	grad.setup(PbTheme.gradient(PbTheme.rule(".dx-shiny.on")), null, false)
	grad.visible = _selected_shiny
	pill.add_child(grad)

	var row := UI.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad_l := 8
	var pad_r := 14
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = pad_l
	row.offset_right = -pad_r
	row.offset_top = 5
	row.offset_bottom = -5
	pill.add_child(row)

	var mark := DexShinyMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _selected_shiny:
		mark.flat_color = Color.WHITE
	else:
		mark.gradient_stops = _shiny_stops()
	mark.custom_minimum_size = Vector2(
		_px(".dx-shiny .shiny-mark", "width", 16.0),
		_px(".dx-shiny .shiny-mark", "height", 16.0))
	row.add_child(mark)

	var label := UI.label(App.ui("Variocolor") if _selected_shiny else App.ui("Normal"),
		int(_px(".dx-shiny", "font-size", 13.0)), Color.WHITE if _selected_shiny else PbTheme.ink())
	label.add_theme_font_override("font", PbTheme.font("title"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	pill.pressed.connect(_toggle_shiny)
	# The Button is parented to a plain Control, so nothing sizes it: build the
	# pill box from the CSS padding (5px 14px 5px 8px) + gap 6 + the content
	# metrics (child min sizes are still 0 before the first layout pass).
	var font := PbTheme.font("title")
	var font_px := int(_px(".dx-shiny", "font-size", 13.0))
	var mark_px := Vector2(_px(".dx-shiny .shiny-mark", "width", 16.0),
		_px(".dx-shiny .shiny-mark", "height", 16.0))
	var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var content := Vector2(mark_px.x + 6.0 + text_w,
		maxf(mark_px.y, font.get_height(font_px)))
	var min_size := content + Vector2(pad_l + pad_r, 10)
	pill.custom_minimum_size = min_size
	pill.size = min_size
	pill.position = Vector2(_px(".dx-shiny", "left", 14.0),
		_px(".dx-shiny", "top", 14.0))
	pill.mouse_entered.connect(func(): pill.modulate = Color(0.94, 0.94, 0.98))
	pill.mouse_exited.connect(func(): pill.modulate = Color.WHITE)
	return pill


func _toggle_shiny() -> void:
	_selected_shiny = not _selected_shiny
	_show(_selected)


func _entry(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-entry"))
	var body := UI.paragraph(text, int(_px(".dx-entry", "font-size", 14.0)), PbTheme.ink(), 2)
	body.add_theme_font_override("font", PbTheme.font("body_bold"))
	panel.add_child(body)
	return panel


func _facts(species: Dictionary, captured: bool, shiny: bool) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var slate := PbTheme.css_color(PbTheme.v("--slate", "#4a4466"), Color("#4a4466"))
	row.add_child(UI.chip(App.ui("Altura {n} m", {"n": _decimal(int(species.get("height", 0)))}), slate))
	row.add_child(UI.chip(App.ui("Peso {n} kg", {"n": _decimal(int(species.get("weight", 0)))}), slate))
	if captured:
		row.add_child(_icon_chip(App.ui("Capturado"), PbTheme.accent_color("green", "c"), "check"))
	if shiny:
		row.add_child(_gradient_chip(App.ui("Variocolor")))
	return row


func _icon_chip(text: String, color: Color, icon_name: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", PbTheme.chip_style(color))
	var row := UI.hbox(4)
	var icon := UI.icon_rect(icon_name, 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := UI.label(text, 12, Color.WHITE)
	label.add_theme_font_override("font", PbTheme.font("title"))
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	chip.add_child(row)
	return chip


## `.shiny-chip`: gradient pill. The rule was not in the extracted token table,
## so the shipped `.dx-shiny.on` gradient (same pink→purple→blue) is reused.
func _gradient_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 12
	empty.content_margin_right = 12
	empty.content_margin_top = 3
	empty.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", empty)
	var grad := PbWidgets.GradRect.new()
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.corner = 999.0
	grad.setup(PbTheme.gradient(PbTheme.rule(".dx-shiny.on")), null, false)
	chip.add_child(grad)
	var label := UI.label(text, 12, Color.WHITE)
	label.add_theme_font_override("font", PbTheme.font("title"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip


## `.tag` (not extracted into ui_theme.json): small bold caption above a block.
func _tag(text: String) -> Control:
	var label := UI.label(text, int(_px(".dx-count", "font-size", 12.0)), PbTheme.ink_muted())
	label.add_theme_font_override("font", PbTheme.font("title_bold"))
	return label


## `.stat-row` (the web dex rows): 60px caption, bar, 26px value, 12px type.
func _stat_row(caption: String, value: int) -> Control:
	var size := int(_px(".ls-stats .stat-row", "font-size", 12.0))
	var row := UI.hbox(6)
	var cap := UI.label(caption, size, PbTheme.ink())
	cap.custom_minimum_size = Vector2(60, 0)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cap.add_theme_font_override("font", PbTheme.font("title_bold"))
	row.add_child(cap)

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_theme_stylebox_override("panel", PbTheme.bar_background())
	bar.add_child(track)
	var ratio := clampf(float(value) / 180.0, 0.0, 1.0)
	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = _stat_color(value)
	fs.set_corner_radius_all(99)
	fill.add_theme_stylebox_override("panel", fs)
	fill.anchor_bottom = 1.0
	fill.offset_top = 0
	fill.offset_bottom = 0
	fill.offset_left = 0
	fill.offset_right = 0
	bar.add_child(fill)
	bar.resized.connect(func(): fill.offset_right = bar.size.x * ratio)
	fill.offset_right = bar.size.x * ratio
	row.add_child(bar)

	var val := UI.label(str(value), size, PbTheme.ink())
	val.custom_minimum_size = Vector2(26, 0)
	val.size_flags_horizontal = Control.SIZE_SHRINK_END
	val.add_theme_font_override("font", PbTheme.font("title_bold"))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row


## Web Qz: max 180, >=100 green, >=60 blue, otherwise red.
func _stat_color(value: int) -> Color:
	if value >= 100:
		return PbTheme.accent_color("green", "c")
	if value >= 60:
		return PbTheme.accent_color("blue", "c")
	return PbTheme.accent_color("red", "c")


## One `.dx-ms` row: type chip + move name + a dps bar.
func _move_row(def: Dictionary, dps_ratio: float) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-ms"))
	var row := UI.hbox(10)
	panel.add_child(row)
	row.add_child(UI.type_chip(str(def.get("type", "normal"))))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UI.label("%s  [%s]  dmg %.1f cd %.2fs" % [
		App.t("moves", int(def.get("id", 0)), str(def.get("name", "?"))), str(def.get("arch", "")),
		float(def.get("dmg", 0.0)), float(def.get("cd", 0.0))], 13, PbTheme.ink()))
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 5)
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_theme_stylebox_override("panel", PbTheme.stylebox(".dx-ms-bar"))
	bar.add_child(track)
	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = PbTheme.type_color(str(def.get("type", "normal")))
	fs.set_corner_radius_all(99)
	fill.add_theme_stylebox_override("panel", fs)
	fill.anchor_bottom = 1.0
	fill.offset_bottom = 0
	fill.offset_top = 0
	fill.offset_left = 0
	fill.offset_right = 0
	bar.add_child(fill)
	var ratio := clampf(dps_ratio, 0.0, 1.0)
	bar.resized.connect(func(): fill.offset_right = bar.size.x * ratio)
	col.add_child(bar)
	return panel


# ------------------------------------------------------------------ helpers
func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _name(species: Dictionary, species_id: int) -> String:
	return App.t("pokemon", species_id, str(species.get("name", "?")))


func _family(species_id: int) -> int:
	var species := PbData.species(species_id)
	return int(species.get("family", species_id))


## Web `o()`: seen id, or the whole family unlocked.
func _is_seen(species_id: int) -> bool:
	var seen: Array = PbJson.as_array(Save.store.get("seen", []))
	if seen.has(species_id):
		return true
	return _is_captured(species_id)


## Web `s()`: family unlocked.
func _is_captured(species_id: int) -> bool:
	var unlocked: Array = PbJson.as_array(Save.store.get("unlocked", []))
	return unlocked.has(_family(species_id))


func _has_shiny(species_id: int) -> bool:
	return PbJson.as_array(Save.store.get("shinies", [])).has(species_id)


func _has_classic(species_id: int) -> bool:
	return PbJson.as_array(Save.store.get("classics", [])).has(species_id)


func _seen_count() -> int:
	var n := 0
	for id in PbData.kanto_ids():
		if _is_seen(int(id)):
			n += 1
	return n


func _has_type(species: Dictionary, type_id: String) -> bool:
	return PbJson.as_array(species.get("types", [])).has(type_id)


func _decimal(tenths: int) -> String:
	return str(float(tenths) / 10.0)


func _type_icon(type_id: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := "res://assets/ui/types/%s.png" % type_id
	if ResourceLoader.exists(path):
		t.texture = load(path)
	return t


func _sprite_filter(hue: float, silhouette: bool, white: bool, alpha: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DEX_SHADER
	mat.set_shader_parameter("hue_deg", hue)
	mat.set_shader_parameter("silhouette", 1.0 if silhouette else 0.0)
	mat.set_shader_parameter("silhouette_white", 1.0 if white else 0.0)
	mat.set_shader_parameter("alpha_mul", alpha)
	return mat


## Web `cu()`: hue-rotate degrees for the shiny preview.
func _hue_degrees(species_id: int) -> float:
	return round((0.22 + fmod(float(species_id) * 0.618034, 1.0) * 0.56) * 360.0)


func _shiny_stops() -> Array:
	return PbJson.as_array(PbTheme.gradient(PbTheme.rule(".dx-shiny.on")).get("stops", []))


func _px(sel: String, key: String, fallback: float) -> float:
	var raw := str(PbTheme.decls(sel).get(key, ""))
	var value := raw.to_float()
	return value if value > 0.0 else fallback


func _grid_min_px() -> float:
	var raw := str(PbTheme.decls(".dx-grid").get("grid-template-columns", ""))
	var m := RegEx.create_from_string("minmax\\(\\s*([0-9.]+)px").search(raw)
	if m != null:
		return m.get_string(1).to_float()
	return 84.0


## `.shiny-mark` star: 8-point clip-path from the CSS, vertex-coloured with the
## shipped shiny gradient (theme table has no mark-specific gradient rule).
class DexShinyMark:
	extends Control
	var gradient_stops: Array = []
	var flat_color := Color(0, 0, 0, 0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([
			Vector2(w * 0.50, h * 0.00), Vector2(w * 0.61, h * 0.38),
			Vector2(w * 1.00, h * 0.50), Vector2(w * 0.61, h * 0.62),
			Vector2(w * 0.50, h * 1.00), Vector2(w * 0.39, h * 0.62),
			Vector2(w * 0.00, h * 0.50), Vector2(w * 0.39, h * 0.38),
		])
		var cols := PackedColorArray()
		for p in pts:
			var t := (p.x + p.y) / maxf(1.0, w + h)
			cols.append(_color_at(t))
		draw_polygon(pts, cols)

	func _color_at(t: float) -> Color:
		if flat_color.a > 0.0:
			return flat_color
		if gradient_stops.is_empty():
			return Color.WHITE
		var i := 0
		while i < gradient_stops.size() - 1 and float(gradient_stops[i + 1].get("pos", 1.0)) < t:
			i += 1
		if gradient_stops.size() == 1:
			return gradient_stops[0].get("color", Color.WHITE)
		var a: Dictionary = gradient_stops[i]
		var b: Dictionary = gradient_stops[mini(i + 1, gradient_stops.size() - 1)]
		var ta := float(a.get("pos", 0.0))
		var tb := float(b.get("pos", 1.0))
		var k := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
		return (a.get("color", Color.WHITE) as Color).lerp(b.get("color", Color.WHITE), k)
