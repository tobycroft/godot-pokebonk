extends Control
class_name PbBackdrop
## The web app's page background, rebuilt from the ported CSS tokens.
##
## Layers (top of the stack last), matching the site's light theme:
##   1. vertical paper gradient (--paper -> --paper-2)
##   2. soft accent blobs in --yellow/--blue/--purple/--green at low alpha
##   3. the --stripes diagonal band used behind headers
## Drawn with _draw() instead of shaders so it also works on the Compatibility
## renderer and while exporting for web.

@export var accent_strength := 0.16


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var size_now := size
	if size_now.x <= 0.0:
		size_now = get_viewport_rect().size
	var paper := PbTheme.paper()
	var paper2 := PbTheme.paper(1.0)
	var steps := 24
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var col := PbTheme.mix(paper, paper2, (t0 + t1) * 0.5)
		draw_rect(Rect2(0, size_now.y * t0, size_now.x, size_now.y * (t1 - t0) + 1.0), col)

	var accents := ["yellow", "blue", "purple", "green", "orange"]
	var spots := [
		Vector2(0.10, 0.14), Vector2(0.86, 0.10), Vector2(0.72, 0.86),
		Vector2(0.16, 0.82), Vector2(0.50, 0.04),
	]
	for i in spots.size():
		var p := Vector2(spots[i].x * size_now.x, spots[i].y * size_now.y)
		var radius := minf(size_now.x, size_now.y) * (0.22 + 0.06 * float(i % 3))
		var color := PbTheme.accent_color(accents[i % accents.size()], "c")
		color.a = accent_strength
		draw_circle(p, radius, color)
		color.a = accent_strength * 0.55
		draw_circle(p + Vector2(radius * 0.45, radius * 0.25), radius * 0.6, color)

	# --stripes: repeating-linear-gradient(-45deg, #ffffff24 0 10px, transparent 10px 20px)
	var band := Rect2(0, 0, size_now.x, minf(180.0, size_now.y * 0.28))
	var stripe := PbTheme.css_color("#ffffff24", Color(1, 1, 1, 0.14))
	var y := band.position.y - band.size.x
	var index := 0
	while y < band.end.y:
		if index % 2 == 0:
			var next_y := y + 20.0
			var polygon := PackedVector2Array([
				Vector2(0, y), Vector2(band.size.x, y - band.size.x),
				Vector2(band.size.x, next_y - band.size.x), Vector2(0, next_y),
			])
			draw_colored_polygon(polygon, stripe)
		y += 20.0
		index += 1
