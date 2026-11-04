extends Control
## In-run feedback layer (H-17), mirrored from the web build's HUD DOM:
##   .lowhp  inset red glow shown while hp < 25% (`.lowhp{inset 0 0 160px 50px
##           #ff142866; animation:.8s infinite alternate pulse}` -> brightness 1.35)
##   .flash  hit vignette (`inset 0 0 120px 30px #ff283c8c`, .on = opacity 1,
##           then transition:opacity .3s back to 0)
##   .floater  `26px/900` number with a 5px ink stroke that follows @keyframes
##             floatUp (0%: +10px/scale .5/alpha 0 -> 15%: alpha 1/scale 1.2 ->
##             30%: scale 1 -> 100%: -70px/alpha 0) over 1s.
## Timeline values come from main-oZVl1tJD-mvpjh5lt.css; no new numbers invented.

const LOW_HP_RATIO := 0.25

var _lowhp: InsetGlow = null
var _flash: InsetGlow = null
var _pulse: Tween = null
var _flash_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lowhp = InsetGlow.new()
	add_child(_lowhp)
	_lowhp.setup(Color("#ff142866"), 160.0, 50.0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_lowhp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lowhp.visible = false

	_flash = InsetGlow.new()
	add_child(_flash)
	_flash.setup(Color("#ff283c8c"), 120.0, 30.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false


## Feed the low-hp overlay: `.lowhp` is shown while ratio < .25 and the actor is
## alive; the pulse alternates 0.8s between normal and brightness(1.35).
func set_low_hp(ratio: float, dead: bool) -> void:
	if _lowhp == null:
		return
	var low := ratio < LOW_HP_RATIO and not dead
	if low == _lowhp.visible:
		return
	_lowhp.visible = low
	if low:
		_pulse = _lowhp.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_lowhp, "modulate", Color(1.35, 1.35, 1.35), 0.8)
		_pulse.tween_property(_lowhp, "modulate", Color.WHITE, 0.8)
	else:
		if _pulse != null:
			_pulse.kill()
			_pulse = null
		_lowhp.modulate = Color.WHITE


## `.flash.on{opacity:1;transition:none}` then the class is removed straight
## away, so the vignette starts at 1 and fades over the .3s transition.
func flash() -> void:
	if _flash == null:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_flash.visible = true
	_flash.modulate.a = 1.0
	_flash_tween = _flash.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.3)
	_flash_tween.tween_callback(func() -> void: _flash.visible = false)


## Spawn a .floater at a screen point (world damage numbers are anchored on the
## hit actor in the web build; the caller projects that position).
func spawn_floater(text: String, color: Color, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", PbTheme.font("title"))
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", PbTheme.ink())
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	label.reset_size()
	# translate(-50%,-100%): centre the label on x, bottom on the spawn point.
	label.pivot_offset = label.size * 0.5
	label.position = at - Vector2(label.size.x * 0.5, label.size.y)
	label.scale = Vector2(0.5, 0.5)
	label.modulate.a = 0.0
	var base_y := label.position.y
	var tw := label.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		var a := 1.0
		var s := 1.0
		var dy := 0.0
		if t < 0.15:
			var k := t / 0.15
			a = k
			s = lerpf(0.5, 1.2, k)
			dy = lerpf(10.0, 0.0, k)
		elif t < 0.30:
			var k := (t - 0.15) / 0.15
			s = lerpf(1.2, 1.0, k)
		else:
			var k := (t - 0.30) / 0.70
			a = 1.0 - k
			dy = lerpf(0.0, -70.0, k)
		if not is_instance_valid(label):
			return
		label.modulate.a = a
		label.scale = Vector2(s, s)
		label.position.y = base_y + dy
	, 0.0, 1.0, 1.0)
	tw.tween_callback(label.queue_free)


## Custom-drawn inset shadow (CSS `inset 0 0 <blur>px <spread>px <color>`):
## concentric edge bands, solid out to `spread`, then fading over `blur`.
class InsetGlow:
	extends Control
	var color := Color("#ff142866")
	var blur := 160.0
	var spread := 50.0

	func setup(what_color: Color, what_blur: float, what_spread: float) -> void:
		color = what_color
		blur = what_blur
		spread = what_spread
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var reach := blur + spread
		var limit := minf(reach, minf(size.x, size.y) * 0.5)
		var steps := 24
		var step := reach / float(steps)
		for i in steps:
			var d0 := step * float(i)
			if d0 >= limit:
				break
			var d1 := minf(step * float(i + 1), limit)
			var a := 1.0
			if d0 > spread:
				a = clampf(1.0 - (d0 - spread) / blur, 0.0, 1.0)
			var band := color
			band.a *= a
			var thickness := d1 - d0
			draw_rect(Rect2(0.0, d0, size.x, thickness), band)
			draw_rect(Rect2(0.0, size.y - d1, size.x, thickness), band)
			draw_rect(Rect2(d0, 0.0, thickness, size.y), band)
			draw_rect(Rect2(size.x - d1, 0.0, thickness, size.y), band)
