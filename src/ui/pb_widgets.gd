class_name PbWidgets
extends RefCounted
## Custom-draw widgets for effects StyleBoxFlat cannot express, all driven by
## the same extracted CSS tokens (PbTheme): gradients, the --stripes texture,
## conic cooldown rings and the .switch knob track.

## Shared tile for the `--stripes` repeating-linear-gradient (default: -45deg,
## #ffffff24 0 10px, transparent 10px 20px). Rendered once per (colour,period).
static var _stripe_tex := {}

static func stripes_texture() -> Texture2D:
	var st := PbTheme.stripes()
	var period := int(st["period"])
	var color: Color = st["color"]
	var key := "%s_%d" % [color.to_html(true), period]
	if _stripe_tex.has(key):
		return _stripe_tex[key]
	# A period-long diagonal ramp tile: pixel (x,y) is inside a stripe when
	# (x + y) mod period < period/2, which reproduces the -45deg banding.
	var img := Image.create(period, period, false, Image.FORMAT_RGBA8)
	for y in period:
		for x in period:
			var inside := (x + y) % period < period / 2
			img.set_pixel(x, y, color if inside else Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_stripe_tex[key] = tex
	return tex


## A rounded rect painted with a CSS linear-gradient + optional stripe overlay,
## approximating `background: var(--stripes), linear-gradient(...)` clipped to
## the rule's border-radius. Feed it PbTheme.gradient() output directly.
class GradRect:
	extends Control
	var gradient := {}              # PbTheme.gradient() dictionary
	var style: StyleBoxFlat = null  # drawn first (bg/border/shadow)
	var overlay_stripes := true
	var corner := -1.0              # -1 = inherit from style

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func setup(what_gradient: Dictionary, what_style: StyleBoxFlat = null, stripes: bool = true) -> GradRect:
		gradient = what_gradient
		style = what_style
		overlay_stripes = stripes
		queue_redraw()
		return self

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		if style != null:
			style.draw(self, rect)
		var radius := corner
		if radius < 0.0 and style != null:
			radius = float(style.corner_radius_top_left)
		var cap := minf(maxf(radius, 0.0), minf(size.x, size.y) * 0.5)
		var pts := _rounded_pts(size, cap)
		if gradient.get("type", "") == "linear":
			# Per-vertex colour interpolation along the CSS gradient direction:
			# no texture sampling, so it is deterministic on the first frame.
			var angle := deg_to_rad(float(gradient.get("angle", 180.0)))
			var dir := Vector2(sin(angle), -cos(angle))
			var proj := []
			var lo := INF
			var hi := -INF
			for p in pts:
				var t := (p - size * 0.5).dot(dir)
				proj.append(t)
				lo = minf(lo, t)
				hi = maxf(hi, t)
			var span := maxf(hi - lo, 0.001)
			var cols := PackedColorArray()
			for t in proj:
				var u := clampf((t - lo) / span, 0.0, 1.0)
				cols.append(_sample_gradient(u))
			draw_polygon(pts, cols)
		elif not gradient.is_empty():
			if style != null:
				draw_colored_polygon(pts, style.bg_color)
		if overlay_stripes:
			var st := PbTheme.stripes()
			var period := float(st["period"])
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append(p / period)
			draw_colored_polygon(pts, Color.WHITE, uvs, PbWidgets.stripes_texture())


	## Sample the gradient stops at t in [0,1] (offsets normalised 0..1).
	func _sample_gradient(t: float) -> Color:
		var stops: Array = gradient.get("stops", [])
		if stops.is_empty():
			return Color.WHITE
		var offs := []
		for i in stops.size():
			var pos := float(stops[i]["pos"])
			if pos < 0.0:
				pos = float(i) / maxf(1.0, float(stops.size() - 1)) * 100.0
			offs.append(clampf(pos / 100.0, 0.0, 1.0))
		if t <= float(offs[0]):
			return stops[0]["color"]
		for i in range(1, stops.size()):
			if t <= float(offs[i]):
				var s2 := maxf(float(offs[i]) - float(offs[i - 1]), 0.0001)
				var f := clampf((t - float(offs[i - 1])) / s2, 0.0, 1.0)
				return (stops[i - 1]["color"] as Color).lerp(stops[i]["color"], f)
		return stops[stops.size() - 1]["color"]


	## Corners rounded like border-radius: one arc of N points per corner
	## (Geometry2D's helper is instance-only, so the polygon is built here).
	func _rounded_pts(sz: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		if r <= 0.5:
			pts.append(Vector2(0, 0))
			pts.append(Vector2(sz.x, 0))
			pts.append(Vector2(sz.x, sz.y))
			pts.append(Vector2(0, sz.y))
			return pts
		var steps := 6
		var corners := [
			{"c": Vector2(sz.x - r, r), "a0": -90.0, "a1": 0.0},
			{"c": Vector2(sz.x - r, sz.y - r), "a0": 0.0, "a1": 90.0},
			{"c": Vector2(r, sz.y - r), "a0": 90.0, "a1": 180.0},
			{"c": Vector2(r, r), "a0": 180.0, "a1": 270.0},
		]
		for corner_def in corners:
			var center: Vector2 = corner_def["c"]
			var a0 := deg_to_rad(float(corner_def["a0"]))
			var a1 := deg_to_rad(float(corner_def["a1"]))
			for i in steps + 1:
				var ang := lerpf(a0, a1, float(i) / float(steps))
				pts.append(center + Vector2(cos(ang), sin(ang)) * r)
		return pts


## .ult-ring: conic cooldown. CSS paints conic-gradient(var(--c) p%, #3a3456 0);
## we sweep an accent arc over a dark disc, with the paper rim and the ready
## glow taken from .ult.ready/.ult-ring tokens.
class UltRing:
	extends Control
	var progress := 0.0            # 0..100, mirrors --p
	var accent := Color("#ffcc33")
	var is_ready := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(74, 74)
		pivot_offset = Vector2(37, 37)

	func _draw() -> void:
		var center := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(center, r, Color("#3a3456"))
		var frac := clampf(progress / 100.0, 0.0, 1.0)
		if frac > 0.0:
			var pts := PackedVector2Array()
			pts.append(center)
			var steps := 48
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * frac * float(i) / float(steps)
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			var col := accent
			if is_ready:
				col = accent.lerp(Color("#ffd23a"), 0.5)
			draw_colored_polygon(pts, col)
		# core well + paper rim (box-shadow: 0 0 0 3px var(--paper))
		draw_circle(center, maxf(r - 8.0, 1.0), PbTheme.ink())
		draw_arc(center, r - 1.5, 0.0, TAU, 64, PbTheme.paper(), 3.0)

	func refresh() -> void:
		queue_redraw()


## .switch: 58x32 track with a 24px knob; mirrors the .22s
## cubic-bezier(.3,1.6,.5,1) slide with TRANS_BACK, and the .on colour layer.
class SwitchToggle:
	extends Control
	signal toggled(on: bool)

	var on := false
	var accent := Color(0, 0, 0, 0)
	var _track: PanelContainer
	var _knob: Panel

	func _init(start_on: bool = false) -> void:
		on = start_on
		custom_minimum_size = Vector2(58, 32)
		size_flags_horizontal = Control.SIZE_SHRINK_END
		mouse_filter = Control.MOUSE_FILTER_STOP
		_track = PanelContainer.new()
		_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_track)
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_track.add_child(holder)
		_knob = Panel.new()
		_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_knob.size = Vector2(24, 24)
		holder.add_child(_knob)
		_track.resized.connect(func(): _paint(true))
		_paint(true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			set_pressed(not on)
			Audio.sfx("ui")
			toggled.emit(on)

	func set_pressed(value: bool) -> void:
		on = value
		_paint()

	func _paint(instant: bool = false) -> void:
		_track.add_theme_stylebox_override("panel", PbTheme.switch_track_style(on, accent))
		_knob.add_theme_stylebox_override("panel", PbTheme.switch_knob_style())
		var target := Vector2(30, 4) if on else Vector2(4, 4)
		if instant:
			_knob.position = target
		else:
			var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_knob, "position", target, 0.22)


## .tl-ring: the XP ring around the portrait medal in hud-tl.
class XpRing:
	extends Control
	var progress := 0.0
	var _portrait: Control = null

	func _init() -> void:
		custom_minimum_size = Vector2(84, 84)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_portrait(node: Control) -> void:
		_portrait = node
		add_child(node)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(center, r, Color("#2e2848"))
		var frac := clampf(progress / 100.0, 0.0, 1.0)
		if frac > 0.0:
			draw_arc(center, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48,
				PbTheme.accent_color("purple", "c"), 5.0)
		draw_arc(center, r - 0.5, 0.0, TAU, 48, PbTheme.paper(), 2.0)
		if _portrait != null:
			var inner := (r - 7.0) * 2.0
			_portrait.position = center - _portrait.size * 0.5


## .minimap: the round radar (bundle @2125794 canvas). CSS gives it a paper+red
## double ring and a translucent ink face; we draw the player centred with
## enemy/orb/item blips mapped from world space into the disc.
class Minimap:
	extends Control
	var world_radius := 30.0        # metres from the player that fit in the disc
	var player_pos := Vector2.ZERO
	var blips: Array = []           # [{"x","z","color","r"}]

	func _init() -> void:
		custom_minimum_size = Vector2(150, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var rad := minf(size.x, size.y) * 0.5
		# face: background #2a244073
		draw_circle(center, rad, PbTheme.css_color("#2a244073", Color(0.16, 0.14, 0.25, 0.45)))
		# blips (clip to the disc)
		for b in blips:
			var off := Vector2(float(b["x"]) - player_pos.x, float(b["z"]) - player_pos.y)
			if off.length() > world_radius:
				continue
			var p := center + off / world_radius * (rad - 4.0)
			draw_circle(p, float(b.get("r", 3.0)), b["color"])
		# player marker at the centre
		draw_circle(center, 4.5, Color.WHITE)
		draw_circle(center, 2.5, PbTheme.accent_color("blue", "c"))
		# rings: box-shadow 0 0 0 4px paper, 0 0 0 7px red
		draw_arc(center, rad - 2.0, 0.0, TAU, 64, PbTheme.paper(), 4.0)
		draw_arc(center, rad + 2.0, 0.0, TAU, 64, PbTheme.accent_color("red", "c"), 3.0)

