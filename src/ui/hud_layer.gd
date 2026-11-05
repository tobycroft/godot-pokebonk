class_name RunHud
extends Control
## The in-run HUD, node-for-node like the web build's `hud` DOM (bundle @2124400):
## hud-tl (xp-ring medal + plate with name/types/lives + hpbar + pw-row),
## hud-top (ht-l biome/pips/zone/weather · ht-c timer/danger/gold · ht-r clock),
## hud-tr (streak, empty until lives/revive port), hud-bl (fusion ult ring +
## kill counter + kgoal), bossbar, toasts and banners.
##
## Every colour/radius/shadow comes from PbTheme reading ui_theme.json (the
## site's own CSS); conic rings and gradient bands use PbWidgets. sync() only
## touches values each frame (the tree is built once), mirroring the web's
## dataset-diff update pattern.

var _state: Dictionary = {}
var _els := {}

var _hp_lag := 1.0
var _hp_lag_hold := 0.0
var _last_hp_ratio := 1.0
var _stage_shown := 0
var _boss_shown := false
var _weather_shown := ""
var _timer_final := false
var _timer_pulse: Tween = null


func build(state: Dictionary) -> void:
	_state = state
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = PbTheme.build()
	_els = {}
	_build_top()
	_build_tl()
	_build_tr()
	_build_bl()
	_build_br()
	_build_bossbar()


## ------------------------------------------------------------------ hud-top
func _fit_centre_slot(slot: Control, centre: Control) -> void:
	slot.custom_minimum_size.x = centre.get_combined_minimum_size().x


func _build_top() -> void:
	var top := PanelContainer.new()
	top.name = "HudTop"
	top.add_theme_stylebox_override("panel", PbTheme.hud_top_style())
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	# H-10: .hud-top is a 1fr | auto | 1fr grid in the stylesheet. Keeping the
	# clock in its own middle track is what stops it from covering ht-l / ht-r.
	var grid := GridContainer.new()
	grid.name = "HtGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)
	top.add_child(grid)

	# ht-l: biome + stage pips + zone + weather
	var left := UI.vbox(3)
	left.name = "HtL"
	grid.add_child(left)
	var biome := UI.label("", 17, PbTheme.ink())
	biome.add_theme_font_override("font", PbTheme.font("title"))
	left.add_child(biome)
	_els["biome"] = biome
	var row := UI.hbox(6)
	left.add_child(row)
	var pips := UI.hbox(3)
	pips.name = "HtPips"
	row.add_child(pips)
	_els["pips"] = pips
	var zone := UI.dim("")
	zone.add_theme_font_size_override("font_size", 12)
	row.add_child(zone)
	_els["zone"] = zone
	var weather := PanelContainer.new()
	weather.name = "HtWeather"
	var wbox := UI.hbox(3)
	wbox.alignment = BoxContainer.ALIGNMENT_CENTER
	weather.add_child(wbox)
	var wlabel := UI.label("", 11, PbTheme.ink_muted())
	wbox.add_child(wlabel)
	weather.add_theme_stylebox_override("panel", PbTheme.stylebox(".ht-weather"))
	weather.visible = false
	row.add_child(weather)
	_els["weather"] = weather
	_els["weather_label"] = wlabel

	# ht-c: the middle grid track (.ht-c margin:-4px 0 -80px in CSS). The slot is
	# SIZE_FILL so the column owns its track; the column itself is a plain-Control
	# child that starts 4px above the panel and hangs below it without growing it.
	var slot := Control.new()
	slot.name = "HtCSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_horizontal = Control.SIZE_FILL
	slot.size_flags_vertical = Control.SIZE_FILL
	grid.add_child(slot)
	var centre := UI.vbox(6)
	centre.name = "HtC"
	centre.alignment = BoxContainer.ALIGNMENT_BEGIN
	slot.add_child(centre)
	centre.set_anchors_preset(Control.PRESET_CENTER_TOP)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_END
	centre.offset_top = -4
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The slot must reserve the clock column's width so the 1fr tracks can never
	# be overrun; a plain Control does not inherit its child's minimum size.
	centre.minimum_size_changed.connect(_fit_centre_slot.bind(slot, centre))
	_fit_centre_slot(slot, centre)
	var timer := PanelContainer.new()
	timer.name = "Timer"
	timer.add_theme_stylebox_override("panel", PbTheme.timer_style(false))
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var trow := UI.hbox(8)
	timer.add_child(trow)
	var ball := UI.icon_rect("poke-ball", 22)
	trow.add_child(ball)
	var timer_label := UI.label("0:00", 30, Color.WHITE)
	timer_label.add_theme_font_override("font", PbTheme.font("title"))
	trow.add_child(timer_label)
	centre.add_child(timer)
	_els["timer"] = timer
	_els["timer_label"] = timer_label
	centre.add_child(_build_danger())
	centre.add_child(_build_wallet())

	# ht-r: run clock
	var right := UI.vbox(0)
	right.name = "HtR"
	right.alignment = BoxContainer.ALIGNMENT_END
	grid.add_child(right)
	var clock_val := UI.label("0:00.0", 18, PbTheme.ink())
	clock_val.add_theme_font_override("font", PbTheme.font("title"))
	clock_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(clock_val)
	_els["clock"] = clock_val
	var clock_sub := UI.dim("")
	clock_sub.add_theme_font_size_override("font_size", 11)
	clock_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(clock_sub)
	_els["clock_sub"] = clock_sub

	# lay it out: left | right ends, centre column hangs over the panel edge
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.custom_minimum_size = Vector2(560, 0)
	top.offset_left = 0
	top.offset_right = 0
	top.offset_top = 12
	# .ht-l sits at the panel start, .ht-r at the end (justify-self in CSS)
	left.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.alignment = BoxContainer.ALIGNMENT_END
	_fit_centre_slot(slot, centre)


## .danger: paper pill with the 7-segment meter (dH/fH tables @2122027).
func _build_danger() -> Control:
	var pill := PanelContainer.new()
	pill.name = "Danger"
	pill.add_theme_stylebox_override("panel", PbTheme.stylebox(".danger"))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := UI.hbox(7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(row)
	var cap := UI.label("", 11, PbTheme.accent_color("green", "c"))
	cap.add_theme_font_override("font", PbTheme.font("title"))
	cap.custom_minimum_size = Vector2(64, 0)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(cap)
	_els["danger_cap"] = cap
	var segs := UI.hbox(3)
	segs.name = "DgSeg"
	row.add_child(segs)
	_els["danger_segs"] = segs
	var thresholds := PbTheme.danger_thresholds()
	for i in thresholds.size():
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(13, 7)
		slot.add_theme_stylebox_override("panel", _dg_slot_style())
		var fill := ColorRect.new()
		fill.color = PbTheme.css_color(str(PbTheme.danger_colors()[i]), Color("#36c96a"))
		fill.size = Vector2(13, 7)
		fill.pivot_offset = Vector2(0, 0)
		slot.add_child(fill)
		segs.add_child(slot)
	return pill


static func _dg_slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PbTheme.css_color(PbTheme.v("--k-e6e3ef", "#e6e3ef"), Color("#e6e3ef"))
	s.set_corner_radius_all(3)
	return s


## .wallet: gold pill (nugget icon + amount). The next-ball price (.wl-ball)
## stays hidden until the shop/ball economy lands (diff-list #8).
func _build_wallet() -> Control:
	var pill := PanelContainer.new()
	pill.name = "Wallet"
	pill.add_theme_stylebox_override("panel", PbTheme.wallet_style())
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := UI.hbox(4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(row)
	row.add_child(UI.icon_rect("gold", 22))
	var value := UI.label("0", 17, PbTheme.wallet_gold())
	value.add_theme_font_override("font", PbTheme.font("title"))
	value.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	_els["gold"] = value
	return pill


## ------------------------------------------------------------------ hud-tl
func _build_tl() -> void:
	# Plain Control (not a container): the CSS pulls the plate 34px left over
	# the medal, which container layout would fight.
	var tl := Control.new()
	tl.name = "HudTl"
	tl.position = Vector2(14, 12)
	tl.custom_minimum_size = Vector2(320, 108)
	add_child(tl)

	var medal := HudXpRing.new()
	medal.name = "TlRing"
	tl.add_child(medal)
	_els["xp_ring"] = medal
	var portrait := PmdSprite.new()
	portrait.setup(1, "idle", 0.7)
	medal.set_portrait(portrait)
	_els["portrait"] = portrait
	var lvl := PanelContainer.new()
	lvl.name = "TlLvl"
	var lvl_style := PbTheme.level_badge_style()
	# .tl-lvl box-shadow: 0 0 0 3px paper -> painted as an inner paper rim.
	lvl_style.set_border_width_all(3)
	lvl_style.border_color = PbTheme.paper()
	lvl.add_theme_stylebox_override("panel", lvl_style)
	var lvl_row := UI.hbox(2)
	lvl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl.add_child(lvl_row)
	var lvl_small := UI.label("Nv", 10, Color.WHITE)
	lvl_small.add_theme_font_override("font", PbTheme.font("title"))
	lvl_row.add_child(lvl_small)
	var lvl_num := UI.label("1", 20, Color.WHITE)
	lvl_num.add_theme_font_override("font", PbTheme.font("title"))
	lvl_row.add_child(lvl_num)
	_els["level"] = lvl_num
	medal.add_child(lvl)
	# .tl-lvl{bottom:-12px;left:50%;transform:translate(-50%)}: centre it under the
	# 108px medal, 12px below the rim (H-12).
	lvl.reset_size()
	lvl.position = Vector2((108.0 - lvl.size.x) * 0.5, 108.0 + 12.0 - lvl.size.y)

	var plate := PanelContainer.new()
	plate.name = "TlPlate"
	plate.custom_minimum_size = Vector2(260, 84)
	plate.position = Vector2(74, 12) # 108px medal - 34px overlap (.tl-plate margin)
	plate.z_index = -1 # CSS z-index: medal 2 above plate 1
	var plate_style := PbTheme.stylebox(".tl-plate")
	# H-18: the plate fill lives on `.tl-plate:before{background:var(--w97)}` in
	# the stylesheet; read it through the token instead of a literal #fffffff7.
	plate_style.bg_color = PbTheme.hud_plate()
	plate.add_theme_stylebox_override("panel", plate_style)
	tl.add_child(plate)
	var pv := UI.vbox(3)
	plate.add_child(pv)
	var head := UI.hbox(8)
	head.add_theme_constant_override("separation", 8)
	pv.add_child(head)
	var name_l := UI.label("—", 21, PbTheme.ink())
	name_l.add_theme_font_override("font", PbTheme.font("title"))
	head.add_child(name_l)
	_els["name"] = name_l
	var types := UI.hbox(4)
	head.add_child(types)
	_els["types"] = types
	var lives := UI.label("", 12, PbTheme.css_color("#b5841a", Color("#b5841a")))
	lives.add_theme_font_override("font", PbTheme.font("title"))
	lives.visible = false
	head.add_child(lives)
	_els["lives"] = lives
	pv.add_child(_build_hpbar())
	var pw := UI.hbox(4)
	pw.name = "PwRow"
	pw.alignment = BoxContainer.ALIGNMENT_CENTER
	pw.visible = false
	pv.add_child(pw)
	_els["pw_row"] = pw


## .under .hpbar: 18px bar with a 2.5px paper border. Layers follow the DOM's
## z-order: track -> u (red lag, z1) -> i (fill, z2) -> :after shine -> s (shield,
## z3) -> b (11px caption, z4). H-11 keeps the lag under the fill and wider than
## it, exactly like the stylesheet, so the trailing sliver stays visible.
const HP_BAR_H := 18.0
const HP_INNER_INSET := 3.0

func _build_hpbar() -> Control:
	var bar := Control.new()
	bar.name = "HpBar"
	bar.custom_minimum_size = Vector2(0, HP_BAR_H)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := Panel.new()
	track.name = "track"
	var ts := StyleBoxFlat.new()
	ts.bg_color = PbTheme.css_color("#4a4068", Color("#4a4068"))
	ts.set_corner_radius_all(999)
	ts.set_border_width_all(3)
	ts.border_color = PbTheme.paper()
	track.add_theme_stylebox_override("panel", ts)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)

	# Pill interior (the CSS children are absolutely positioned inside the border).
	var inner := Control.new()
	inner.name = "HpInner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = HP_INNER_INSET
	inner.offset_right = -HP_INNER_INSET
	inner.offset_top = HP_INNER_INSET
	inner.offset_bottom = -HP_INNER_INSET
	bar.add_child(inner)

	var lag := Panel.new()
	lag.name = "u"
	lag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lag_style := StyleBoxFlat.new()
	lag_style.bg_color = PbTheme.css_color("#ff5a6a", Color("#ff5a6a"))
	lag_style.set_corner_radius_all(999)
	lag.add_theme_stylebox_override("panel", lag_style)
	inner.add_child(lag)

	var fill := PbWidgets.GradRect.new()
	fill.name = "i"
	fill.corner = 999.0
	fill.setup(_hp_gradient("high"), null, false)
	inner.add_child(fill)

	var shield := Panel.new()
	shield.name = "s"
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shield_style := StyleBoxFlat.new()
	shield_style.bg_color = PbTheme.css_color("#78dcffbf", Color("#78dcff"))
	shield_style.set_corner_radius_all(999)
	shield.add_theme_stylebox_override("panel", shield_style)
	shield.visible = false
	inner.add_child(shield)

	# .under .hpbar:after -- white 35%-height glint inset 4px / 2px from the top.
	var shine := Panel.new()
	shine.name = "HpShine"
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shine_style := StyleBoxFlat.new()
	shine_style.bg_color = PbTheme.css_color("#ffffff59", Color(1, 1, 1, 0.35))
	shine_style.set_corner_radius_all(99)
	shine.add_theme_stylebox_override("panel", shine_style)
	shine.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shine.offset_left = 4
	shine.offset_right = -4
	shine.offset_top = 2
	shine.offset_bottom = 2 + roundf(HP_BAR_H * 0.35)
	bar.add_child(shine)

	var caption := UI.label("", 11, Color.WHITE)
	caption.name = "b"
	caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 8
	caption.add_theme_constant_override("outline_size", 3)
	caption.add_theme_color_override("font_outline_color", PbTheme.ink())
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(caption)

	_els["hp_inner"] = inner
	_els["hp_fill"] = fill
	_els["hp_lag"] = lag
	_els["hp_shield"] = shield
	_els["hp_caption"] = caption
	_els["hp_band"] = "high"
	return bar


static func _hp_gradient(band: String) -> Dictionary:
	return PbTheme.hpbar_gradient(band)


## ------------------------------------------------------------------ hud-tr
func _build_tr() -> void:
	var tr := UI.vbox(10)
	tr.name = "HudTr"
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(tr)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -240
	tr.offset_right = -14
	tr.offset_top = 14
	tr.offset_bottom = 240
	# .streak stays empty until the revive/lives port (diff-list #8); the slot
	# exists so later phases land without layout surgery.


## ------------------------------------------------------------------ hud-bl
func _build_bl() -> void:
	var bl := UI.vbox(8)
	bl.name = "HudBl"
	add_child(bl)
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_left = 14
	bl.offset_right = 254
	bl.offset_top = -14
	bl.offset_bottom = -14

	# .ult (adapted): the fusion machine's ring — kbd R (PbRun: KEY_R), ready when a recipe is.
	var ult := Control.new()
	ult.name = "FusionUlt"
	ult.custom_minimum_size = Vector2(74, 74)
	var ring := PbWidgets.UltRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ult.add_child(ring)
	_els["ult_ring"] = ring
	var kcap := PanelContainer.new()
	kcap.add_theme_stylebox_override("panel", PbTheme.stylebox(".ult kbd"))
	var krow := UI.hbox(0)
	kcap.add_child(krow)
	krow.add_child(UI.label("R", 12, PbTheme.ink()))
	krow.alignment = BoxContainer.ALIGNMENT_CENTER
	ult.add_child(kcap)
	kcap.position = Vector2(58, 60)
	var nm := PanelContainer.new()
	var nms := StyleBoxFlat.new()
	nms.bg_color = PbTheme.css_color("#16102c9e", Color(0.086, 0.063, 0.173, 0.62))
	nms.set_corner_radius_all(99)
	nms.content_margin_left = 10
	nms.content_margin_right = 10
	nms.content_margin_top = 2
	nms.content_margin_bottom = 2
	nm.add_theme_stylebox_override("panel", nms)
	var nml := UI.label(App.ui("Fusión"), 11, Color.WHITE)
	nml.add_theme_font_override("font", PbTheme.font("title"))
	nm.add_child(nml)
	ult.add_child(nm)
	nm.position = Vector2(14, -22)
	_els["ult_name"] = nml
	bl.add_child(ult)

	# .counter: kills pill.
	var counter := PanelContainer.new()
	counter.add_theme_stylebox_override("panel", PbTheme.stylebox(".counter"))
	var crow := UI.hbox(4)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	counter.add_child(crow)
	crow.add_child(UI.icon_rect("poke-ball", 22))
	var kills := UI.label("0", 15, PbTheme.ink())
	kills.add_theme_font_override("font", PbTheme.font("title"))
	crow.add_child(kills)
	bl.add_child(counter)
	_els["kills"] = kills

	# .kgoal: next-boss goal card (226px wide per CSS).
	var goal := PanelContainer.new()
	goal.name = "KGoal"
	goal.add_theme_stylebox_override("panel", PbTheme.kgoal_style())
	goal.custom_minimum_size = Vector2(226, 0)
	var gv := UI.vbox(0)
	gv.add_theme_constant_override("separation", 0)
	goal.add_child(gv)
	var ghead := PanelContainer.new()
	var head_style := PbTheme.stylebox(".kg-head")
	head_style.bg_color = PbTheme.rarity_color(3)
	ghead.add_theme_stylebox_override("panel", head_style)
	var ghtrow := UI.hbox(6)
	ghtrow.alignment = BoxContainer.ALIGNMENT_CENTER
	ghead.add_child(ghtrow)
	var gtitle := UI.label("目标", 10, Color.WHITE)
	gtitle.add_theme_font_override("font", PbTheme.font("title"))
	# .kg-head{text-shadow:0 1px #0003}
	gtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.2))
	gtitle.add_theme_constant_override("shadow_offset_y", 1)
	ghtrow.add_child(gtitle)
	# H-14: `.kg-head span{background:var(--paper);color:var(--kc)}` -- the tag is
	# a paper pill, so the rarity colour stays readable on the purple head.
	var kc_hex := "#" + PbTheme.rarity_color(3).to_html(false)
	var gtag_pill := PanelContainer.new()
	gtag_pill.add_theme_stylebox_override("panel",
		PbTheme.stylebox(".kg-head span", {"--kc": kc_hex, "--c": kc_hex}))
	var gtag := UI.label("", 10, PbTheme.rarity_color(3))
	gtag.add_theme_font_override("font", PbTheme.font("title"))
	gtag_pill.add_child(gtag)
	ghtrow.add_child(gtag_pill)
	_els["kg_tag"] = gtag
	gv.add_child(ghead)
	var gmain := UI.hbox(8)
	gmain.add_theme_constant_override("separation", 8)
	gv.add_child(gmain)
	var gpt := PanelContainer.new()
	var pts := StyleBoxFlat.new()
	pts.bg_color = PbTheme.paper(1.0)
	pts.set_corner_radius_all(999)
	pts.shadow_size = 0
	pts.set_border_width_all(2)
	pts.border_color = PbTheme.rarity_color(3)
	gpt.add_theme_stylebox_override("panel", pts)
	gpt.custom_minimum_size = Vector2(34, 34)
	var gsprite := PmdSprite.new()
	gsprite.setup(1, "idle", 0.36)
	gpt.add_child(gsprite)
	gmain.add_child(gpt)
	_els["kg_sprite"] = gsprite
	var gbody := UI.vbox(0)
	gbody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gmain.add_child(gbody)
	var gsmall := UI.dim("下一首领")
	gsmall.add_theme_font_size_override("font_size", 9)
	gbody.add_child(gsmall)
	var gname := UI.label("—", 14, PbTheme.ink())
	gname.add_theme_font_override("font", PbTheme.font("title"))
	gbody.add_child(gname)
	_els["kg_name"] = gname
	var gleft := UI.vbox(0)
	gleft.alignment = BoxContainer.ALIGNMENT_END
	gmain.add_child(gleft)
	var gleft_cap := UI.dim(App.ui("Te faltan"))
	gleft_cap.add_theme_font_size_override("font_size", 8)
	gleft.add_child(gleft_cap)
	var gleft_val := UI.label("", 19, PbTheme.rarity_color(3))
	gleft_val.add_theme_font_override("font", PbTheme.font("title"))
	gleft.add_child(gleft_val)
	_els["kg_left"] = gleft_val
	var gbar := Control.new()
	gbar.name = "KgBar"
	gbar.custom_minimum_size = Vector2(0, 6)
	var gbar_fill := ColorRect.new()
	gbar_fill.color = PbTheme.rarity_color(3)
	gbar_fill.custom_minimum_size = Vector2(0, 6)
	gbar.add_child(gbar_fill)
	var gbar_bg := Panel.new()
	var gbgs := StyleBoxFlat.new()
	gbgs.bg_color = PbTheme.paper(1.0)
	gbgs.set_corner_radius_all(9)
	gbar_bg.add_theme_stylebox_override("panel", gbgs)
	gbar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gbar_bg.z_index = -1
	gbar.add_child(gbar_bg)
	gv.add_child(gbar)
	_els["kg_fill"] = gbar_fill
	bl.add_child(goal)
	_els["kgoal"] = goal


## ------------------------------------------------------------------ hud-br
## .minimap radar (bundle @2125794), bottom-right.
func _build_br() -> void:
	var br := Control.new()
	br.name = "HudBr"
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(br)
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# .minimap is 212x212 in the stylesheet (H-12).
	br.offset_left = -226
	br.offset_right = -14
	br.offset_top = -226
	br.offset_bottom = -14
	var mm := PbWidgets.Minimap.new()
	mm.set_anchors_preset(Control.PRESET_FULL_RECT)
	br.add_child(mm)
	_els["minimap"] = mm


## ------------------------------------------------------------------ bossbar
func _build_bossbar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "BossBar"
	bar.visible = false
	add_child(bar)
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -300
	bar.offset_right = 300
	bar.offset_top = 96
	bar.offset_bottom = 160
	# H-15: .bossbar exposes its accent through `--c`; pass it so the bottom
	# border and the tag background resolve instead of falling back to paper.
	var boss_c := "#e82a5a"
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", PbTheme.stylebox(".bb-body", {"--c": boss_c}))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(body)
	var col := UI.vbox(4)
	body.add_child(col)
	var head := UI.hbox(8)
	col.add_child(head)
	var pt := PmdSprite.new()
	pt.setup(1, "idle", 0.5)
	head.add_child(pt)
	_els["bb_pt"] = pt
	var bname := UI.label("首领", 18, PbTheme.ink())
	bname.add_theme_font_override("font", PbTheme.font("title"))
	head.add_child(bname)
	_els["bb_name"] = bname
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", PbTheme.stylebox(".bb-tag", {"--c": boss_c}))
	var tag_l := UI.label("BOSS", 10, Color.WHITE)
	tag_l.add_theme_font_override("font", PbTheme.font("title"))
	tag.add_child(tag_l)
	head.add_child(tag)
	var bar_track := Control.new()
	bar_track.custom_minimum_size = Vector2(0, 15)
	bar_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# H-15: fill is `.bb-bar>i`'s 3-stop token gradient, not a hard-coded #ff4a6e.
	var bb_fill := PbWidgets.GradRect.new()
	var bb_grad := PbTheme.gradient(str(PbTheme.decls(".bb-bar>i").get("background", "")))
	bb_fill.setup(bb_grad, null, false)
	bb_fill.custom_minimum_size = Vector2(0, 15)
	bar_track.add_child(bb_fill)
	var bb_text := UI.label("", 11, Color.WHITE)
	bb_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	bb_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bb_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bb_text.offset_right = -10
	bar_track.add_child(bb_text)
	var bb_bg := Panel.new()
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = PbTheme.css_color("#2e2848", Color("#2e2848"))
	bg_s.set_corner_radius_all(999)
	bb_bg.add_theme_stylebox_override("panel", bg_s)
	bb_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bb_bg.z_index = -1
	bar_track.add_child(bb_bg)
	col.add_child(bar_track)
	_els["bb_fill"] = bb_fill
	_els["bb_text"] = bb_text
	_els["bossbar"] = bar


## ------------------------------------------------------------------ sync
func sync(state: Dictionary, dt: float) -> void:
	if _els.is_empty():
		return
	var player: Dictionary = PbJson.as_dict(state.get("player", {}))
	var stats := PbJson.as_dict(player.get("stats", {}))
	var run_stats := PbJson.as_dict(state.get("stats", {}))
	var time := float(state.get("time", 0.0))
	var stage := int(state.get("stage", 1))

	# timer + runclock (rl()/il() semantics)
	(_els["timer_label"] as Label).text = UI.fmt_clock(time)
	var final_phase := stage >= PbRun.STAGES and bool(state.get("bossSpawned", false))
	(_els["timer"] as PanelContainer).add_theme_stylebox_override("panel", PbTheme.timer_style(final_phase))
	if final_phase != _timer_final:
		_timer_final = final_phase
		# .timer.final{animation:.4s infinite alternate pulse} -> brightness 1.35
		var timer := _els["timer"] as PanelContainer
		if _timer_pulse != null:
			_timer_pulse.kill()
			_timer_pulse = null
		timer.modulate = Color.WHITE
		if final_phase:
			_timer_pulse = timer.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
			_timer_pulse.tween_property(timer, "modulate", Color(1.35, 1.35, 1.35), 0.4)
			_timer_pulse.tween_property(timer, "modulate", Color.WHITE, 0.4)
	(_els["clock"] as Label).text = UI.fmt_clock_t(time)
	(_els["clock_sub"] as Label).text = "第 %d/%d 阶段" % [stage, PbRun.STAGES]

	# biome + stage pips + weather
	(_els["biome"] as Label).text = _biome_name(str(state.get("biome", "forest")))
	_sync_pips(stage)
	var weather := str(state.get("weather", "clear"))
	var wname := _weather_name(weather)
	var wpill := _els["weather"] as PanelContainer
	# Only show the pill for a weather we can actually name. A null/unknown id
	# used to leak straight into the label (`<null>`), which is what showed as a
	# stray badge next to the biome name.
	wpill.visible = weather != "clear" and not wname.is_empty()
	if wpill.visible:
		(_els["weather_label"] as Label).text = wname

	# wallet + kills
	(_els["gold"] as Label).text = UI.fmt_num(float(state.get("gold", 0.0)))
	(_els["kills"] as Label).text = UI.fmt_num(float(run_stats.get("kills", 0)))

	# medal: portrait/level/xp ring
	var species := int(player.get("species_id", 1))
	var portrait := _els["portrait"] as PmdSprite
	if portrait.species_id != species:
		portrait.setup(species, "idle", 0.7)
	var ring := _els["xp_ring"] as HudXpRing
	var xp_next := maxf(1.0, float(player.get("xpNext", 1)))
	ring.progress = clampf(float(player.get("xp", 0)) / xp_next * 100.0, 0.0, 100.0)
	var types_now := PbJson.as_array(player.get("types", []))
	var first_type := str(types_now[0]) if not types_now.is_empty() else "normal"
	ring.accent = PbTheme.type_color(first_type)
	(_els["level"] as Label).text = str(int(player.get("level", 1)))
	# zh species title from the mirror's i18n table; the actor's raw name is the fallback.
	(_els["name"] as Label).text = App.t("pokemon", int(player.get("species_id", 0)),
		str(player.get("name", "?")))
	_sync_types(player)

	# hpbar with red lag + shield overlay
	_sync_hp(player, stats, dt)

	# .tl-lives: Revivir Máximo charges (bundle @2150311), hidden at zero
	var lives := _els["lives"] as Label
	var revives := int(player.get("revives", 0))
	lives.visible = revives > 0
	lives.text = "♥ ×%d" % revives

	# danger meter
	_sync_danger(state)

	# fusion ring (adapted .ult): ready when a recipe is available
	_sync_fusion(state)

	# kgoal: countdown to boss, then boss HP
	_sync_goal(state, stage)

	# bossbar
	_sync_boss(state)

	# pw-row: card buffs summary
	_sync_pw(player)

	# minimap blips
	_sync_minimap(state, player)

	# streak (hud-tr) stays empty until lives port


## Feed the radar: enemies as type-coloured dots, xp candies yellow.
func _sync_minimap(state: Dictionary, player: Dictionary) -> void:
	var minimap := _els.get("minimap") as PbWidgets.Minimap
	if minimap == null:
		return
	minimap.player_pos = Vector2(float(player.get("x", 0.0)), float(player.get("z", 0.0)))
	var blips := []
	var pool := PbRun.pool_of(state)
	for entry in PbEnemies.live_indices(pool):
		var i := int(entry)
		if not PbEnemies.is_alive(pool, i):
			continue
		var types: Array = PbEnemies.types_of(pool, i)
		var col := PbTheme.type_color(str(types[0])) if not types.is_empty() else PbTheme.type_color("normal")
		var is_boss := PbEnemies.is_boss(pool, i)
		blips.append({
			"x": float(PbEnemies.get_field(pool, "x", i)),
			"z": float(PbEnemies.get_field(pool, "z", i)),
			"color": col,
			"r": 5.0 if is_boss else 3.0,
		})
	for raw in PbJson.as_array(state.get("orbs", [])):
		var orb := PbJson.as_dict(raw)
		blips.append({"x": float(orb.get("x", 0.0)), "z": float(orb.get("z", 0.0)),
			"color": PbTheme.accent_color("yellow", "c"), "r": 2.0})
	minimap.blips = blips


func _biome_name(id: String) -> String:
	# The mirror's own region titles (zh), e.g. forest -> 青翠森林; the short names stay as the
	# fallback so the HUD never shows a raw id when the table is unavailable.
	var label := PbData.biome_label(id, App.locale)
	if not label.is_empty() and label != id:
		return label
	var names := {"forest": "森林", "coast": "海岸", "desert": "沙漠",
		"glacier": "冰川", "graveyard": "墓地", "volcano": "火山"}
	return str(names.get(id, id))


## Naming a weather id. Unknown or empty ids (a resumed run can carry a null)
## resolve to "" so the HUD hides the pill instead of echoing the raw value.
## Weather *events* (storm/eclipse/meowth, PbWeatherEvents) also write into
## `state.weather`, so they are named from data/pb/weather.json.
func _weather_name(key: String) -> String:
	var names := {"rain": App.ui("Lluvia"), "sun": App.ui("Sol"), "sand": App.ui("Tormenta de arena"),
		"hail": App.ui("Granizo"), "fog": App.ui("Niebla"), "ash": App.ui("Ceniza")}
	if names.has(key):
		return str(names[key])
	var event := PbJson.as_dict(PbWeatherEvents.table().get(key))
	var event_name := str(event.get("name", ""))
	return App.ui(event_name) if not event_name.is_empty() else ""


func _sync_pips(stage: int) -> void:
	if stage == _stage_shown:
		return
	_stage_shown = stage
	var pips := _els["pips"] as HBoxContainer
	for c in pips.get_children():
		c.queue_free()
	for i in PbRun.STAGES:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(16, 16)
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(8)
		s.set_border_width_all(2)
		if i + 1 < stage:
			s.bg_color = PbTheme.css_color("#1f8a46", Color("#1f8a46"))
			s.border_color = PbTheme.css_color("#1f8a46", Color("#1f8a46"))
		elif i + 1 == stage:
			s.bg_color = PbTheme.css_color("#ff5a5f", Color("#ff5a5f"))
			s.border_color = PbTheme.ink()
		else:
			s.bg_color = PbTheme.css_color(PbTheme.v("--k-ece9f4", "#ece9f4"), Color("#ece9f4"))
			s.border_color = PbTheme.css_color("#c8c4d8", Color("#c8c4d8"))
		pip.add_theme_stylebox_override("panel", s)
		var dot := ColorRect.new()
		dot.color = PbTheme.paper()
		dot.size = Vector2(4, 4)
		dot.position = Vector2(6, 6)
		pip.add_child(dot)
		pips.add_child(pip)


func _sync_types(player: Dictionary) -> void:
	var key := str(player.get("types", []))
	if str(_els.get("types_key", "")) == key:
		return
	_els["types_key"] = key
	var types := _els["types"] as HBoxContainer
	for c in types.get_children():
		c.queue_free()
	for t in PbJson.as_array(player.get("types", [])):
		var chip := UI.type_chip(str(t))
		(chip.get_child(0) as Label).add_theme_font_size_override("font_size", 10)
		types.add_child(chip)


func _sync_hp(player: Dictionary, stats: Dictionary, dt: float) -> void:
	var max_hp := maxf(1.0, float(player.get("maxHp", 1.0)))
	var ratio := clampf(float(player.get("hp", 0.0)) / max_hp, 0.0, 1.0)
	var inner := _els["hp_inner"] as Control
	var width := inner.size.x
	var height := inner.size.y
	if height <= 0.0:
		# layout has not run yet on the first frame
		height = HP_BAR_H - HP_INNER_INSET * 2.0
	# red lag layer trails the real value (CSS transition on .hpbar>u)
	if ratio > _last_hp_ratio:
		_hp_lag = ratio
	else:
		_hp_lag_hold = maxf(0.0, _hp_lag_hold - dt)
		if _hp_lag_hold <= 0.0 and _hp_lag > ratio:
			_hp_lag = maxf(ratio, _hp_lag - dt * 0.9)
	_last_hp_ratio = ratio
	_hp_lag_hold = maxf(_hp_lag_hold, 0.35 if ratio < _hp_lag else 0.0)
	var fill := _els["hp_fill"] as PbWidgets.GradRect
	var lag := _els["hp_lag"] as Panel
	var shield := _els["hp_shield"] as Panel
	var caption := _els["hp_caption"] as Label
	var band := "high"
	if ratio <= 0.25:
		band = "low"
	elif ratio <= 0.55:
		band = "mid"
	if band != str(_els.get("hp_band", "")):
		_els["hp_band"] = band
		fill.setup(_hp_gradient(band), null, false)
	fill.size = Vector2(width * ratio, height)
	lag.size = Vector2(width * maxf(_hp_lag, ratio), height)
	var shield_v := clampf(float(player.get("shield", 0.0)) / max_hp, 0.0, 1.0)
	shield.visible = shield_v > 0.0
	shield.size = Vector2(width * shield_v, height)
	caption.text = "%s / %s" % [UI.fmt_num(float(player.get("hp", 0.0))), UI.fmt_num(max_hp)]
	if ratio <= 0.25:
		# CSS .hpbar.low>i -- .5s infinite alternate pulse
		if not fill.has_meta("pulsing"):
			fill.set_meta("pulsing", true)
			var tw := fill.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
			tw.tween_property(fill, "modulate", Color(1.25, 1.25, 1.25), 0.5)
			tw.tween_property(fill, "modulate", Color(1, 1, 1), 0.5)
			fill.set_meta("pulse_tw", tw)
	elif fill.has_meta("pulsing"):
		fill.remove_meta("pulsing")
		(fill.get_meta("pulse_tw") as Tween).kill()
		fill.remove_meta("pulse_tw")
		fill.modulate = Color.WHITE


func _sync_danger(state: Dictionary) -> void:
	# Single source: PbRun.danger() (mirrored by tools-re/golden_values.py).
	var danger := PbRun.danger(state)
	var thresholds := PbTheme.danger_thresholds()
	var level := 0
	for i in thresholds.size():
		if danger >= float(thresholds[i]):
			level = i
	var cap := _els["danger_cap"] as Label
	var colors := PbTheme.danger_colors()
	var zh := [App.ui("Tranquilo"), App.ui("Moderado"), App.ui("Peligroso"), App.ui("Muy peligroso"),
		App.ui("Brutal"), App.ui("Letal"), App.ui("Imposible")]
	cap.text = str(zh[clampi(level, 0, zh.size() - 1)])
	cap.add_theme_color_override("font_color",
		PbTheme.css_color(str(colors[clampi(level, 0, colors.size() - 1)]), Color("#36c96a")))
	if str(_els.get("danger_level", "")) != str(level):
		if level > int(_els.get("danger_prev", 0)):
			Audio.sfx("xp", 0.6)
		_els["danger_level"] = str(level)
	_els["danger_prev"] = level
	var segs := _els["danger_segs"] as HBoxContainer
	for i in segs.get_child_count():
		var slot := segs.get_child(i) as Panel
		var fillc := slot.get_child(0) as ColorRect
		var target := 0.0
		if i < level:
			target = 1.0
		elif i == level:
			var lo := float(thresholds[i])
			var hi := float(thresholds[i + 1]) if i + 1 < thresholds.size() else lo + 1.5
			target = clampf((danger - lo) / (hi - lo), 0.0, 1.0)
		fillc.scale = Vector2(target, 1.0)


func _sync_fusion(state: Dictionary) -> void:
	var offers: Array = PbRun.fusion_offers(state)
	var ready := false
	var best_level := 1
	for raw in PbJson.as_array(PbJson.as_dict(state.get("player", {})).get("moves", [])):
		if raw != null:
			best_level = maxi(best_level, int(PbJson.as_dict(raw).get("level", 1)))
	for raw in offers:
		if bool(PbJson.as_dict(raw).get("ready", false)):
			ready = true
			break
	var ring := _els["ult_ring"] as PbWidgets.UltRing
	ring.progress = clampf(float(best_level - 1) / float(PbFusion.MOVE_MAX_LEVEL - 1) * 100.0, 0.0, 100.0)
	ring.is_ready = ready
	ring.accent = PbTheme.accent_color("purple", "c")
	var nm := _els["ult_name"] as Label
	nm.text = "融合就绪！" if ready else "招式升级解锁融合"


func _sync_goal(state: Dictionary, stage: int) -> void:
	var boss_now := bool(state.get("bossSpawned", false))
	var pool := PbRun.pool_of(state)
	var boss_index := int(state.get("bossIndex", -1))
	var countdown := maxf(0.0, PbRun.STAGE_TIME - float(state.get("stageT", 0.0)))
	(_els["kg_left"] as Label).text = UI.fmt_clock(countdown) if not boss_now else "—"
	var progress := clampf(float(state.get("stageT", 0.0)) / PbRun.STAGE_TIME, 0.0, 1.0)
	if boss_now and boss_index >= 0 and PbEnemies.is_alive(pool, boss_index):
		var hp := float(PbEnemies.get_field(pool, "hp", boss_index))
		var mx := maxf(1.0, float(PbEnemies.get_field(pool, "maxHp", boss_index)))
		progress = clampf(hp / mx, 0.0, 1.0)
		(_els["kg_name"] as Label).text = App.t("pokemon", int(PbEnemies.get_field(pool, "species", boss_index)),
			"#%d" % int(PbEnemies.get_field(pool, "species", boss_index)))
		(_els["kg_tag"] as Label).text = "击败首领"
	elif not boss_now:
		var species := _next_boss_species(stage)
		(_els["kg_name"] as Label).text = App.t("pokemon", species, "#%d" % species)
		(_els["kg_tag"] as Label).text = App.ui("Fase {n}", {"n": stage})
		var sprite := _els["kg_sprite"] as PmdSprite
		if sprite.species_id != species:
			sprite.setup(species, "idle", 0.36)
	var fill := _els["kg_fill"] as ColorRect
	fill.size = Vector2((_els["kg_fill"].get_parent() as Control).size.x * progress, 6)


static func _next_boss_species(stage: int) -> int:
	var candidates := []
	for p in PbData.pokemon_list():
		if bool(p.get("legendary", false)) and int(p.get("gen", 1)) == 1:
			candidates.append(int(p["id"]))
	if candidates.is_empty():
		return 150
	return int(candidates[mini(stage - 1, candidates.size() - 1)])


func _sync_boss(state: Dictionary) -> void:
	var boss_now := bool(state.get("bossSpawned", false)) and int(state.get("bossIndex", -1)) >= 0
	var bar := _els["bossbar"] as HBoxContainer
	if boss_now != _boss_shown:
		_boss_shown = boss_now
		bar.visible = boss_now
		if boss_now:
			UI.anim_in(bar, "bbIn")
	if not boss_now:
		return
	var pool := PbRun.pool_of(state)
	var idx := int(state.get("bossIndex", -1))
	if not PbEnemies.is_alive(pool, idx):
		return
	var species := int(PbEnemies.get_field(pool, "species", idx))
	var pt := _els["bb_pt"] as PmdSprite
	if pt.species_id != species:
		pt.setup(species, "walk", 0.5)
	(_els["bb_name"] as Label).text = App.t("pokemon", species, "#%d" % species)
	var hp := float(PbEnemies.get_field(pool, "hp", idx))
	var mx := maxf(1.0, float(PbEnemies.get_field(pool, "maxHp", idx)))
	var fill := _els["bb_fill"] as Control
	var track := fill.get_parent() as Control
	fill.size = Vector2(track.size.x * clampf(hp / mx, 0.0, 1.0), 15)
	(_els["bb_text"] as Label).text = "%s / %s" % [UI.fmt_num(hp), UI.fmt_num(mx)]


## .pw-row: current card buffs as small pills (data is on the actor's mods).
func _sync_pw(player: Dictionary) -> void:
	var row := _els["pw_row"] as HBoxContainer
	var mods := PbJson.as_array(player.get("mods", []))
	var signature := str(mods.slice(maxi(0, mods.size() - 6)))
	if str(_els.get("pw_key", "")) == signature:
		return
	_els["pw_key"] = signature
	for c in row.get_children():
		c.queue_free()
	row.visible = not mods.is_empty()
	var recent := mods.slice(maxi(0, mods.size() - 6))
	for raw in recent:
		var mod := PbJson.as_dict(raw)
		var stat := str(mod.get("stat", "?"))
		var delta := "×%.2f" % float(mod.get("mul", 1.0)) if mod.has("mul") else "+%.2f" % float(mod.get("add", 0.0))
		var chip := UI.chip("%s %s" % [stat, delta], PbTheme.accent_color("blue", "c"))
		(chip.get_child(0) as Label).add_theme_font_size_override("font_size", 10)
		row.add_child(chip)


## Route a simulation message through the web toast stack instead of the old log.
func notify(text: String) -> void:
	UI.toast(self, text)


## Stage banner (CSS .banner with --c accent; the ported stage system announces
## stage-ups and the boss spawn).
func show_banner(text: String, sub_text: String = "", accent: String = "", long: bool = false) -> void:
	var before := get_child_count()
	UI.banner(self, text, sub_text, accent, long)
	if get_child_count() <= before:
		return
	var layer := get_child(get_child_count() - 1)
	# H-13: `.banner h1{display:inline-block;padding:8px 40px}` is a text-hugging
	# capsule; the shared helper lays the plate out full-width, so re-fit it here.
	if layer.get_child_count() > 0:
		UI.fit_capsule(layer.get_child(0) as Control, 40.0)


## H-12: .tl-medal / .tl-ring / .tl-portrait rebuilt at the stylesheet's 108px.
## conic-gradient(#3a8cff, #5ad8ff p%, var(--line) 0) is painted as a blue->cyan
## sweep over the `--line` remainder; the portrait keeps its inset:10px face with
## the 4px tc border. Local to this HUD file because PbWidgets is frozen for this
## phase (merge note in the hand-off).
class HudXpRing:
	extends Control
	var progress := 0.0:
		set(value):
			if absf(progress - value) > 0.05:
				progress = value
				queue_redraw()
	var accent := Color(0.23, 0.55, 1.0)
	var _portrait: Control = null

	func _init() -> void:
		custom_minimum_size = Vector2(108, 108)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_portrait(node: Control) -> void:
		_portrait = node
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(node)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5
		var band := 10.0 # .tl-portrait{inset:10px}
		var frac := clampf(progress / 100.0, 0.0, 1.0)
		var line_color := PbTheme.css_color(PbTheme.v("--line", "#e4e0f0"), Color("#e4e0f0"))
		draw_arc(center, radius - band * 0.5, 0.0, TAU, 64, line_color, band)
		if frac > 0.0:
			var steps := maxi(8, int(48.0 * frac))
			for i in steps:
				var t := (float(i) + 0.5) / float(steps)
				var color := Color("#3a8cff").lerp(Color("#5ad8ff"), t)
				draw_arc(center, radius - band * 0.5,
					-PI * 0.5 + TAU * frac * float(i) / float(steps),
					-PI * 0.5 + TAU * frac * float(i + 1) / float(steps),
					6, color, band)
		# .tl-portrait: radial paper -> 35% tc, 4px tc border
		var portrait_r := radius - band
		draw_circle(center, portrait_r, PbTheme.paper().lerp(accent, 0.35))
		draw_arc(center, portrait_r - 2.0, 0.0, TAU, 64, accent, 4.0)
		# 3px paper rim (box-shadow: 0 0 0 3px var(--paper))
		draw_arc(center, radius - 1.5, 0.0, TAU, 64, PbTheme.paper(), 3.0)
		if _portrait != null:
			var diameter := portrait_r * 2.0 - 8.0
			_portrait.size = Vector2(diameter, diameter)
			_portrait.position = center - _portrait.size * 0.5
