extends Control
class_name PbBackdrop
## The web app's page background (H-01).
##
## Web truth: `html,body{background:#1a1630}` -- dark in *both* themes -- with a
## purple haze on top (`radial-gradient(circle at 50% 40%, #3a2f7a, #1a1630 70%)`
## from .rotate-hint/.auth-hero). The old paper gradient, accent blobs and white
## --stripes band had no source in the stylesheet and made every screen look
## washed out; they are gone.
##
## Drawn with _draw() instead of shaders so it also works on the Compatibility
## renderer and while exporting for web.

## 0 = flat #1a1630, 1 = full #3a2f7a haze. Kept low: the site's haze is subtle.
@export_range(0.0, 1.0) var glow_strength := 0.32
## Centre of the haze as a fraction of the viewport (`at 50% 40%` in CSS,
## nudged to the top edge because the port's shell has no rotate hint).
@export var glow_center := Vector2(0.5, 0.05)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var size_now := size
	if size_now.x <= 0.0 or size_now.y <= 0.0:
		size_now = get_viewport_rect().size
	var base := PbTheme.page_bg()
	draw_rect(Rect2(Vector2.ZERO, size_now), base)
	if glow_strength <= 0.0:
		return

	var glow := PbTheme.page_glow()
	var center := Vector2(glow_center.x * size_now.x, glow_center.y * size_now.y)
	var radius := maxf(size_now.x, size_now.y) * 0.85
	# Concentric discs from the rim inward: outer discs equal the base colour, so
	# the ring edges disappear and only a soft radial falloff remains.
	var steps := 28
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)
		# mix() weights its first argument, so weight = base share.
		var col := PbTheme.mix(base, glow, 1.0 - (1.0 - t) * glow_strength)
		draw_circle(center, radius * t, col)
