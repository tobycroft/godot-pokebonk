class_name UI
extends RefCounted
## Code-side widget kit for the ported UI.
##
## The web UI is DOM + CSS; here every helper builds Controls styled from
## PbTheme (which reads the site's own extracted tokens), so the port and the
## original share one design system instead of two hand-tuned ones.


static func themify(node: Control) -> void:
	node.theme = PbTheme.build()


## Stretch a control to its parent. Scene-root Controls are *not* resized by the
## viewport (they keep their design size), so a root also gets an explicit size;
## without this the anchored layout collapses to zero width.
static func fill(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
	var parent := node.get_parent()
	# A root Control (no parent, or under a CanvasLayer/Viewport) is not resized
	# by the container system, so give it the viewport rect explicitly.
	if parent == null or not (parent is Control):
		var viewport := node.get_viewport()
		if viewport != null:
			node.size = viewport.get_visible_rect().size


## Call from a screen's _ready() so the root fills the window.
static func stretch_root(node: Control) -> void:
	fill(node)


static func label(text: String, font_size: int = 16, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PbTheme.font("body"))
	l.add_theme_font_size_override("font_size", font_size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Single-line by default: an autowrapped Label reports a ~1px minimum width in
	# Godot 4.7 (there is no fit_content_height on Label), which collapses every
	# container above it. Use paragraph() when text really must wrap.
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = false
	return l


## Wrapping body copy: explicit minimum height in lines, because a wrapped Label
## has no intrinsic height of its own.
static func paragraph(text: String, font_size: int = 14, color: Color = Color(0, 0, 0, 0),
		min_lines: int = 2) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, float(font_size) * 1.35 * float(min_lines))
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## h1/h2 in the site's rounded display face (M PLUS Rounded 1c 900).
static func title(text: String, font_size: int = 34) -> Label:
	var l := label(text, font_size, PbTheme.ink())
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = false
	return l


static func subtitle(text: String) -> Label:
	var l := label(text, 17, PbTheme.ink_muted())
	l.add_theme_font_override("font", PbTheme.font("title_bold"))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = false
	return l


static func dim(text: String) -> Label:
	return label(text, PbTheme.font_size("small"), PbTheme.ink_muted())


## Muted body copy that wraps: long CJK lines would otherwise force their
## container past its CSS min-width. (Moved from main_menu's `_dim_block`.)
static func dim_block(text: String) -> Label:
	var l := dim(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, callback: Callable, big: bool = false, accent: String = "yellow", small: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	PbTheme.paint(b, accent, big, small)
	if callback.is_valid():
		b.pressed.connect(callback)
	b.mouse_entered.connect(_btn_hover_sound.bind(b))
	return b


static func _btn_hover_sound(b: Button) -> void:
	if is_instance_valid(b) and not b.disabled:
		Audio.sfx("ui", 1.6)


## Icon lookup: the migrated sprite set (assets/ui/icons), then the item art
## (poke-ball, nugget, ... live under assets/items on the web too). Pixel-crisp
## like the site's <img class="pix">; unknown names render nothing.
static func icon_rect(name: String, px: int = 22) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for base in PackedStringArray(["res://assets/ui/icons/", "res://assets/items/"]):
		var path := base + name + ".png"
		if ResourceLoader.exists(path):
			t.texture = load(path)
			break
	return t


## kbd badge (.key / SH(name)): small rounded chip with the key caption.
static func kbd(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := PbTheme.chip_style(PbTheme.css_color(PbTheme.v("--slate", "#4a4466"), Color("#4a4466")))
	s.set_corner_radius_all(7)
	s.border_width_bottom = 2
	s.border_color = Color(0, 0, 0, 0.2)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


## .btn.small variant used by the level-up actions row.
static func small_button(text: String, callback: Callable, accent: String = "blue") -> Button:
	return button(text, callback, false, accent, true)


## .chip: pill with a coloured background, white title-font text, inset bottom edge.
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PbTheme.chip_style(color))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	l.add_theme_constant_override("shadow_offset_y", 1)
	p.add_child(l)
	return p


## Type chip. The port is Chinese-only for now, so the label comes from the mirror's zh
## `types` table (草/毒/火...) and the raw id is only a fallback.
static func type_chip(type_name: String) -> PanelContainer:
	var label := PbData.localized_name("types", type_name, App.locale)
	if label.is_empty():
		label = type_name.to_upper()
	return chip(label, PbTheme.type_color(type_name))


## Wallet-style pill: small muted caption above a bold value, in one card row.
static func stat_pill(caption: String, value: String, accent: String = "yellow") -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(104, 0)
	card.add_theme_stylebox_override("panel", PbTheme.pill_field())
	var box := vbox(0)
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var cap := dim(caption)
	cap.add_theme_font_size_override("font_size", 11)
	box.add_child(cap)
	var val := label(value, 19, PbTheme.accent_color(accent, "cd"))
	val.add_theme_font_override("font", PbTheme.font("title"))
	box.add_child(val)
	return card


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(margin: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var s := PbTheme.card_style()
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	p.add_theme_stylebox_override("panel", s)
	return p


## Full-bleed screen: backdrop + padded content column, like <div class="screen">.
static func screen() -> Control:
	var root := Control.new()
	root.name = "Screen"
	themify(root)
	var backdrop := PbBackdrop.new()
	backdrop.name = "Backdrop"
	root.add_child(backdrop)
	return root


static func content(root: Control, margin: int = 22) -> VBoxContainer:
	var box := MarginContainer.new()
	root.add_child(box)
	fill(box)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		box.add_theme_constant_override(side, margin)
	var v := vbox(10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(v)
	return v


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func grid(columns: int, sep: int = 8) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	return g


## Approximate CSS `repeat(auto-fill, minmax(min_px, 1fr))`: the column count
## comes from the laid-out width, and the GridContainer only changes when it
## differs (avoids a resize loop). Returns the effective column count.
static func autofill_columns(grid: GridContainer, min_px: float, gap: float) -> int:
	var width := grid.size.x
	if width <= 0.0:
		return grid.columns
	var cols := maxi(1, int(floor((width + gap) / (min_px + gap))))
	if grid.columns != cols:
		grid.columns = cols
	return cols


## Autowrapped Labels have no intrinsic height; measure at the laid-out width.
## (Moved from lab_screen so pokedex/other grids share the same measurement.)
static func fit_wrapped_height(l: Label) -> void:
	if l == null or l.has_meta("fit_busy") or l.size.x < 1.0:
		return
	var font := l.get_theme_font("font")
	var font_size := l.get_theme_font_size("font_size")
	var h := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, l.size.x, font_size).y
	if absf(h - l.custom_minimum_size.y) > 1.0:
		l.set_meta("fit_busy", true)
		l.custom_minimum_size.y = h
		l.call_deferred("remove_meta", "fit_busy")


## `.card:hover` / `.lab-card:hover` ring: a 3/4px hard outline drawn by the
## StyleBox's zero-offset shadow (StyleBoxFlat has no separate outline layer).
static func hover_ring_style(base: StyleBoxFlat, color: Color, px: int = 4) -> StyleBoxFlat:
	var s: StyleBoxFlat = base.duplicate()
	s.shadow_size = px
	s.shadow_offset = Vector2.ZERO
	s.shadow_color = color
	s.anti_aliasing = true
	return s


## H-13: shrink a `.banner` / `.modal h1` plate to the width of its label so it
## stays a capsule instead of a full-width band. Title label is child #1.
static func fit_capsule(plate: Control, horizontal_padding: float) -> void:
	if plate == null:
		return
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var title := plate.get_child(1) as Label
	if title == null:
		return
	plate.custom_minimum_size.x = title.get_combined_minimum_size().x + horizontal_padding * 2.0


static func progress(color: String = "green", height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", PbTheme.bar_background())
	bar.add_theme_stylebox_override("fill", PbTheme.bar_fill(PbTheme.accent_color(color, "c")))
	return bar


## Species thumbnail: PMD frame -> portrait PNG -> colour swatch, mirroring
## PbVisuals' 3-step fallback for 3D.
static func species_icon(species_id: int, scale_factor: float = 3.0, anim := "idle") -> Control:
	var holder := PanelContainer.new()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	holder.add_theme_stylebox_override("panel", empty)
	var sprite := PmdSprite.new()
	sprite.setup(species_id, anim, scale_factor)
	holder.add_child(sprite)
	return holder


## A section header inside a card (the site's .scr-title).
static func section(text: String) -> Label:
	var l := title(text, 20)
	l.add_theme_color_override("font_color", PbTheme.accent_color("blue", "cd"))
	return l


static func toast(host: Control, text: String, icon: String = "") -> void:
	# Web parity: .toasts is a centred stack under hud-top; each toast is a
	# frosted pill (.toast) that pops in and frees itself after ~3s.
	var stack: VBoxContainer = host.get_node_or_null("Toasts") as VBoxContainer
	if stack == null:
		stack = VBoxContainer.new()
		stack.name = "Toasts"
		stack.alignment = BoxContainer.ALIGNMENT_BEGIN
		stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
		stack.offset_left = -200
		stack.offset_right = 200
		stack.offset_top = 158
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# M-11: `.toasts{align-items:center}` -> the pill keeps its content width,
	# it does not stretch to the 400px stack.
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", PbTheme.toast_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var contents := hbox(8)
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", 8)
	if not icon.is_empty():
		contents.add_child(icon_rect(icon, 28))
	# `.toast{font-size:15px;font-weight:800}` -- body_bold keeps Web's 800 weight.
	var toast_label := label(text, 15, PbTheme.ink())
	toast_label.add_theme_font_override("font", PbTheme.font("body_bold"))
	contents.add_child(toast_label)
	panel.add_child(contents)
	row.add_child(panel)
	stack.add_child(row)
	anim_in(panel, "popIn")
	host.get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(row):
			var tw := row.create_tween()
			tw.tween_property(panel, "modulate:a", 0.0, 0.25)
			tw.tween_callback(row.queue_free))


## ---- web shell components --------------------------------------------------

## .scr-head: back pill (.back-btn, kbd Esc) + the skewed striped title plate.
## Returns the head row; screens wire on_back to their own return action.
static func screen_head(title_text: String, sub_text: String, on_back: Callable) -> Control:
	var row := hbox(16)
	row.name = "ScrHead"
	var back := Button.new()
	back.text = " " + App.ui("Volver")
	PbTheme.paint(back, "ghost")
	back.add_theme_stylebox_override("normal", PbTheme.back_btn_style())
	back.add_theme_stylebox_override("hover", PbTheme.back_btn_style())
	back.add_theme_stylebox_override("pressed", PbTheme.back_btn_style())
	back.add_theme_color_override("font_color", PbTheme.ink())
	back.pressed.connect(on_back)
	# .back-btn:hover translate(-3px): CSS moves the pill; containers manage our
	# position here, so modulate darkens slightly instead (documented approx).
	back.mouse_entered.connect(func(): back.modulate = Color(0.94, 0.94, 0.98))
	back.mouse_exited.connect(func(): back.modulate = Color.WHITE)
	row.add_child(back)
	row.add_child(_kbd_esc())

	# .scr-title: h1 on the red→orange striped plate, skewed -8deg (children +8).
	var plate := Control.new()
	plate.name = "ScrTitle"
	plate.custom_minimum_size = Vector2(0, 46)
	var grad := PbTheme.gradient(str(PbTheme.decls(".scr-title").get("background", "")))
	var bg := PbWidgets.GradRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.setup(grad, null, true)
	plate.add_child(bg)
	var texts := hbox(14)
	texts.set_anchors_preset(Control.PRESET_FULL_RECT)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	var h := title(title_text, 28)
	h.add_theme_font_override("font", PbTheme.font("title"))
	h.add_theme_color_override("font_color", Color.WHITE)
	h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.18))
	h.add_theme_constant_override("shadow_offset_y", 2)
	texts.add_child(h)
	if not sub_text.is_empty():
		var s := label(sub_text, 14, Color.WHITE)
		s.add_theme_font_override("font", PbTheme.font("title_bold"))
		texts.add_child(s)
	plate.add_child(texts)
	# CSS: transform:skew(-8deg) on the plate, +8deg on the children.
	# CSS transform:skew(-8deg)/children +8deg -- Godot Controls cannot
	# shear their canvas transform, so the plate tilts and the text counter-
	# rotates (documented approximation, same visual energy, see PORT_STATUS).
	plate.pivot_offset = Vector2(0, plate.custom_minimum_size.y * 0.5)
	plate.rotation = deg_to_rad(-8.0)
	texts.pivot_offset = texts.size * 0.5
	texts.rotation = deg_to_rad(8.0)
	row.add_child(plate)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


static func _kbd_esc() -> PanelContainer:
	var k := kbd("Esc")
	var s := PbTheme.chip_style(PbTheme.ink())
	s.set_corner_radius_all(7)
	s.border_width_bottom = 0
	k.add_theme_stylebox_override("panel", s)
	return k


## .seg + .pill/.pill.on: segmented filter. items=[{id, text}]; returns the
## track panel; keep UI.segment()'s return value and cast for select().
class Segment:
	var current := ""
	var on_pick: Callable
	var _inner: HBoxContainer

	func build(item_list: Array, current_id: String, pick: Callable) -> Control:
		current = current_id
		on_pick = pick
		var bg := PanelContainer.new()
		bg.name = "Seg"
		bg.add_theme_stylebox_override("panel", PbTheme.seg_track_style())
		bg.set_meta("segment", self)
		_inner = UI.hbox(4)
		_inner.add_theme_constant_override("separation", 4)
		bg.add_child(_inner)
		for item in item_list:
			var entry := PbJson.as_dict(item)
			var id := str(entry.get("id", ""))
			var b := Button.new()
			b.name = "pill-" + id
			b.flat = true
			b.text = str(entry.get("text", id))
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_on_button.bind(id))
			_inner.add_child(b)
			_repaint_button(b, id == current)
		return bg

	func _on_button(id: String) -> void:
		current = id
		_repaint()
		Audio.sfx("ui")
		if on_pick.is_valid():
			on_pick.call(id)

	func select(id: String) -> void:
		if current == id:
			return
		current = id
		_repaint()

	func _repaint() -> void:
		if _inner == null or not is_instance_valid(_inner):
			return
		for c in _inner.get_children():
			var b := c as Button
			_repaint_button(b, str(b.name).trim_prefix("pill-") == current)

	func _repaint_button(b: Button, on: bool) -> void:
		b.add_theme_stylebox_override("normal", PbTheme.pill_seg_style(on))
		b.add_theme_stylebox_override("hover", PbTheme.pill_seg_style(on))
		b.add_theme_stylebox_override("pressed", PbTheme.pill_seg_style(true))
		# M-09: `.pill{font-weight:900;font-size:13px}` in every state.
		b.add_theme_font_override("font", PbTheme.font("title"))
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", PbTheme.ink() if on else PbTheme.ink_muted())


static func segment(items: Array, current_id: String, pick: Callable) -> Control:
	var s := Segment.new()
	return s.build(items, current_id, pick)


## .field: the pill LineEdit with the 2px --line/--blue border states.
static func field(placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	if not placeholder.is_empty():
		e.placeholder_text = placeholder
	e.add_theme_stylebox_override("normal", PbTheme.field_style(false))
	e.add_theme_stylebox_override("focus", PbTheme.field_style(true))
	e.add_theme_stylebox_override("read_only", PbTheme.field_style(false))
	e.add_theme_color_override("font_color", PbTheme.ink())
	e.add_theme_color_override("font_placeholder_color", PbTheme.ink_muted())
	e.add_theme_font_override("font", PbTheme.font("body"))
	e.add_theme_font_size_override("font_size", 16)
	return e


## .banner: the big stage announcement, top-centre, bannerIn then self-fade
## (CSS: animation 3.2s forwards; .long 5.2s). accent_raw overrides --c.
static func banner(host: Control, text: String, sub_text: String = "", accent_raw: String = "", long: bool = false) -> void:
	var layer := VBoxContainer.new()
	layer.name = "Banner"
	layer.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	layer.offset_top = float(host.size.y) * 0.2
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(layer)

	var plate := Control.new()
	plate.custom_minimum_size = Vector2(0, 64)
	var grad := PbTheme.gradient(str(PbTheme.decls(".banner h1").get("background", "")),
		{} if accent_raw.is_empty() else {"--c": accent_raw})
	var bg := PbWidgets.GradRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.setup(grad, null, true)
	plate.add_child(bg)
	var h := title(text, 40)
	h.add_theme_font_override("font", PbTheme.font("title"))
	h.add_theme_color_override("font_color", Color.WHITE)
	h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.2))
	h.add_theme_constant_override("shadow_offset_y", 3)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(h)
	plate.pivot_offset = Vector2(0, plate.custom_minimum_size.y * 0.5)
	plate.rotation = deg_to_rad(-8.0)
	layer.add_child(plate)
	if not sub_text.is_empty():
		var pill := PanelContainer.new()
		var ps := StyleBoxFlat.new()
		ps.bg_color = css_or_fallback("#16102c9e", Color(0.086, 0.063, 0.173, 0.62))
		ps.set_corner_radius_all(99)
		ps.content_margin_left = 18
		ps.content_margin_right = 18
		ps.content_margin_top = 5
		ps.content_margin_bottom = 5
		pill.add_theme_stylebox_override("panel", ps)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(label(sub_text, 17, Color.WHITE))
		layer.add_child(pill)

	var total := 5.2 if long else 3.2
	var tw := layer.create_tween()
	tw.tween_interval(total * 0.7)
	tw.tween_property(layer, "modulate:a", 0.0, total * 0.3)
	tw.tween_callback(layer.queue_free)
	anim_in(plate, "popIn")


static func css_or_fallback(text: String, fallback: Color) -> Color:
	return PbTheme.css_color(text, fallback)


## Tween replay of a CSS entrance keyframe (cardIn/tileIn/offerIn/popIn/...).
## The frame body carries translateY/scale/opacity; a missing 100% frame means
## "natural state", exactly as in the browser. `stagger` mirrors --i/--d.
static func anim_in(node: Control, kind: String, stagger: int = 0) -> void:
	anim_in_simple(node, kind, stagger)


## Simplified entrance: fade+scale from the CSS frame values. Position is left
## to the container (tweening it would fight the layout), so we slide via the
## pivot-scaled transform + a brief modulate fade, matching cardIn/offerIn/popIn.
static func anim_in_simple(node: Control, kind: String, stagger: int = 0) -> void:
	var frames := PbTheme.keyframe_frames(kind)
	if frames.is_empty() or not is_instance_valid(node):
		return
	var from := PbJson.as_dict(frames[0])
	var scale := 1.0
	var tr := str(from.get("transform", ""))
	var sc := RegEx.create_from_string(r"scale\(([.\d]+)\)").search(tr)
	if sc != null:
		scale = sc.get_string(1).to_float()
	node.modulate.a = float(str(from.get("opacity", "1")).to_float())
	node.pivot_offset = node.get_combined_minimum_size() * 0.5
	node.scale = Vector2(scale, scale)
	var tw := node.create_tween()
	tw.set_ease(Tween.EASE_OUT)
	if stagger > 0:
		tw.tween_interval(float(stagger) * 0.06)
	tw.tween_property(node, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.3)


## Web number formatting P(): 1-decimal k/M/B/T/Q abbreviations (bundle @97500,
## dl table); below 10k it is plain rounded integers, matching the site.
static func fmt_num(value: float) -> String:
	if value >= 1.0e18:
		var exp := int(floor(log(value) / log(10.0)))
		var mant := value / pow(10.0, float(exp)) * 10.0
		return "%.1fe%d" % [mant / 10.0, exp]
	for pair in [[1.0e15, "Q"], [1.0e12, "T"], [1.0e9, "B"], [1.0e6, "M"]]:
		if value >= float(pair[0]):
			return _trim_one(value / float(pair[0])) + str(pair[1])
	if value >= 1.0e4:
		return _trim_one(value / 1000.0) + "k"
	return str(int(round(value)))


static func _trim_one(value: float) -> String:
	var rounded: float = floor(value * 10.0 + 1e-9) / 10.0
	var s := "%.1f" % rounded
	if s.ends_with(".0"):
		s = s.trim_suffix(".0")
	return s


## rl(): m:ss whole seconds (stage timer). il(): m:ss.d (runclock).
static func fmt_clock(total: float) -> String:
	var t := int(maxf(0.0, floor(total)))
	return "%d:%02d" % [int(t / 60.0), t % 60]


static func fmt_clock_t(total: float) -> String:
	var t := maxf(0.0, total)
	var m := int(t / 60.0)
	return "%d:%04.1f" % [m, t - float(m) * 60.0]


## .mm-item: a nav tile (icon square + title/subtitle column + a coloured 4px
## bottom edge). Matches the web main-menu navigation (diff-list #5).
static func mm_tile(icon_name: String, title_text: String, sub_text: String,
		accent: Color, on_click: Callable, big: bool = false) -> Control:
	var tile := Button.new()
	tile.flat = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(0, 66 if not big else 84)
	var s := PbTheme.stylebox(".mm-item", {"--c": "#" + accent.to_html(false)})
	s.content_margin_left = 10
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	tile.add_theme_stylebox_override("normal", s)
	tile.add_theme_stylebox_override("hover", s)
	tile.add_theme_stylebox_override("pressed", s)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := hbox(10)
	row.add_theme_constant_override("separation", 10)
	tile.add_child(row)
	# A Button is not a Container, so the row has to be pinned to the tile's rect; without this
	# the tile only reports its stylebox as minimum size and grid columns collapse.
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := PanelContainer.new()
	var ic_s := PbTheme.stylebox(".mm-ic", {"--c": "#" + accent.to_html(false)})
	ic.add_theme_stylebox_override("panel", ic_s)
	ic.custom_minimum_size = Vector2(48, 48) if not big else Vector2(56, 56)
	ic.add_child(icon_rect(icon_name, 36 if not big else 42))
	row.add_child(ic)
	var tx := vbox(0)
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tx)
	var b := label(title_text, 19 if not big else 22, PbTheme.ink())
	b.add_theme_font_override("font", PbTheme.font("title"))
	tx.add_child(b)
	if not sub_text.is_empty():
		var sm := label(sub_text, 12, PbTheme.ink_muted())
		sm.add_theme_font_override("font", PbTheme.font("body"))
		tx.add_child(sm)
	if on_click.is_valid():
		tile.pressed.connect(on_click)
	tile.mouse_entered.connect(func():
		tile.pivot_offset = tile.size * 0.5
		var tw := tile.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tile, "scale", Vector2(1.03, 1.03), 0.12)
		Audio.sfx("ui", 1.6))
	tile.mouse_exited.connect(func():
		var tw := tile.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tile, "scale", Vector2.ONE, 0.12))
	return tile


## .card.offer: the level-up card (top band with rarity gradient + badges, body
## with title/sub/lines, key chip, hover lift like .card:hover, offerIn entry).
## `data` = {rc: Color, rar_text, kind_text, icon_name, title, sub, lines, mods,
## key, shine}. Root is a PanelContainer (a real container, so its column lays
## out); a transparent Button overlay handles press/hover. Returns the root.
static func card_offer(data: Dictionary, on_pick: Callable, index: int = 0) -> Control:
	var rc: Color = data.get("rc", PbTheme.rarity_color(0))
	var card := PanelContainer.new()
	card.name = "OfferCard%d" % index
	card.custom_minimum_size = Vector2(236, 300)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# M-03: .card:hover adds `0 0 0 4px var(--rc)` and lifts 4px.
	var card_style := PbTheme.stylebox(".card", {"rc": "#" + rc.to_html(false)})
	var card_hover := UI.hover_ring_style(card_style, rc, 4)
	card.add_theme_stylebox_override("panel", card_style)
	card.clip_contents = true

	var box := vbox(0)
	box.name = "Body"
	card.add_child(box)

	# -- top band: .card .top (135deg gradient over --rc, stripes, shine) -------
	var top := Control.new()
	top.name = "Top"
	top.custom_minimum_size = Vector2(0, 110)
	var grad := PbTheme.gradient(str(PbTheme.decls(".card .top").get("background", "")),
		{"--rc": "#" + rc.to_html(false)})
	var band := PbWidgets.GradRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.setup(grad, null, true)
	top.add_child(band)
	if bool(data.get("shine", false)):
		var shine := PbWidgets.GradRect.new()
		shine.set_anchors_preset(Control.PRESET_FULL_RECT)
		shine.setup({"type": "linear", "angle": 110.0, "stops": [
			{"color": Color(1, 1, 1, 0), "pos": 30.0}, {"color": Color(1, 1, 1, 0.6), "pos": 50.0},
			{"color": Color(1, 1, 1, 0), "pos": 70.0}]}, null, false)
		top.add_child(shine)
		_shine_loop(shine)
	var icon := Control.new()
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.name = "Icon"
	var icon_name := str(data.get("icon_name", ""))
	if not icon_name.is_empty():
		icon.add_child(icon_rect(icon_name, 64))
	top.add_child(icon)
	var rar := str(data.get("rar_text", ""))
	if not rar.is_empty():
		var rar_badge := _card_pill(rar, PbTheme.css_color(PbTheme.v("--w92", "#ffffffeb"), Color(1, 1, 1, 0.92)),
			PbTheme.ink())
		rar_badge.position = Vector2(10, 10)
		top.add_child(rar_badge)
	var kind_txt := str(data.get("kind_text", ""))
	if not kind_txt.is_empty():
		var kind_badge := _card_pill(kind_txt, PbTheme.css_color("#2a2440bf", Color(0.16, 0.14, 0.25, 0.75)), Color.WHITE)
		kind_badge.anchor_left = 1.0
		kind_badge.anchor_right = 1.0
		kind_badge.offset_left = -84
		kind_badge.offset_right = -10
		kind_badge.offset_top = 10
		kind_badge.offset_bottom = 32
		top.add_child(kind_badge)
	box.add_child(top)

	# -- body: .bd (h3 title, sub, ul lines, affects, .key) --------------------
	var bd := vbox(6)
	bd.name = "Bd"
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 16)
	margins.add_theme_constant_override("margin_right", 16)
	margins.add_theme_constant_override("margin_top", 14)
	margins.add_theme_constant_override("margin_bottom", 14)
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_child(bd)
	box.add_child(margins)
	var h3 := title(str(data.get("title", "?")), 21)
	h3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bd.add_child(h3)
	var sub := str(data.get("sub", ""))
	if not sub.is_empty():
		var sl := label(sub, 13, PbTheme.ink_muted())
		sl.add_theme_font_override("font", PbTheme.font("title_bold"))
		bd.add_child(sl)
	var lines: Array = PbJson.as_array(data.get("lines", []))
	for line in lines:
		var li := label("· " + str(line), 15, PbTheme.ink())
		li.add_theme_font_override("font", PbTheme.font("body"))
		li.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bd.add_child(li)
	var affects := str(data.get("affects", ""))
	if not affects.is_empty():
		var ap := PanelContainer.new()
		var asb := StyleBoxFlat.new()
		asb.bg_color = PbTheme.mix(rc, Color.WHITE, 0.86)
		asb.set_corner_radius_all(10)
		asb.content_margin_left = 10
		asb.content_margin_right = 10
		asb.content_margin_top = 4
		asb.content_margin_bottom = 4
		ap.add_theme_stylebox_override("panel", asb)
		ap.add_child(label(affects, 13, PbTheme.ink()))
		bd.add_child(ap)
	var key_txt := str(data.get("key", ""))
	if not key_txt.is_empty():
		bd.add_child(_card_key(key_txt))

	# -- click overlay + hover lift (.card:hover) ------------------------------
	var click := Button.new()
	click.name = "Click"
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.add_child(click)
	if on_pick.is_valid():
		click.pressed.connect(on_pick)
	click.mouse_entered.connect(func():
		Audio.sfx("ui", 1.6)
		card.add_theme_stylebox_override("panel", card_hover)
		card.pivot_offset = card.size * 0.5
		if not card.has_meta("rest_y"):
			card.set_meta("rest_y", card.position.y)
		var rest := float(card.get_meta("rest_y"))
		var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(card, "scale", Vector2(1.05, 1.05), 0.12)
		tw.parallel().tween_property(card, "position:y", rest - 4.0, 0.12))
	click.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", card_style)
		var rest := card.position.y
		if card.has_meta("rest_y"):
			rest = float(card.get_meta("rest_y"))
		var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.12)
		tw.parallel().tween_property(card, "position:y", rest, 0.12))
	anim_in_simple(card, "offerIn", index)
	card.set_meta("rc", rc)
	return card


## `.card .key`: title font, white on --slate, radius 8, padding 1px 8px, 12px/900,
## right-aligned at the end of the body column.
static func _card_key(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = PbTheme.css_color(PbTheme.v("--slate", "#4b5679"), Color("#4b5679"))
	s.set_corner_radius_all(8)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p


static func _card_pill(text: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(99)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PbTheme.font("title"))
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", fg)
	p.add_child(l)
	return p


static func _shine_loop(shine: Control) -> void:
	# CSS .card .top:after -- the 2.4s sweeping gloss (keyframes shine).
	var tw := shine.create_tween().set_loops()
	shine.modulate.a = 0.9
	tw.tween_property(shine, "position", Vector2(-120, 0), 1.2)
	tw.tween_property(shine, "position", Vector2(120, 0), 1.2)


## .modal h1: the skewed striped popup title ("¡Nivel N!" / "本局结算").
static func modal_title(text: String, small: bool = false) -> Control:
	var plate := Control.new()
	plate.name = "ModalH1"
	plate.custom_minimum_size = Vector2(0, 60 if not small else 44)
	var grad := PbTheme.gradient(str(PbTheme.decls(".modal h1").get("background", "")))
	var bg := PbWidgets.GradRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.setup(grad, null, true)
	plate.add_child(bg)
	var h := title(text, 40 if not small else 28)
	h.add_theme_font_override("font", PbTheme.font("title"))
	h.add_theme_color_override("font_color", Color.WHITE)
	h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.15))
	h.add_theme_constant_override("shadow_offset_y", 3)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(h)
	plate.pivot_offset = Vector2(0, plate.custom_minimum_size.y * 0.5)
	plate.rotation = deg_to_rad(-8.0)
	return plate


## .modal scrim panel: dim radial backdrop hosting the popup column.
## M-10: fade-in (`@keyframes modalIn` opacity 0->1 over .2s), keyboard focus
## parked on the scrim, and a left click outside the dialog dismisses when
## `on_dismiss` is supplied.
static func modal_shell(title_text: String, small_title: bool = false,
		on_dismiss: Callable = Callable()) -> Dictionary:
	var scrim := PanelContainer.new()
	scrim.name = "Modal"
	scrim.add_theme_stylebox_override("panel", PbTheme.modal_scrim())
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.focus_mode = Control.FOCUS_ALL
	var col := vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# PASS so clicks on the empty backdrop still bubble up to the scrim.
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	scrim.add_child(col)
	var head := modal_title(title_text, small_title)
	col.add_child(head)
	var body := vbox(10)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(body)
	var fade := func() -> void:
		if not scrim.is_inside_tree() or not scrim.visible:
			return
		scrim.modulate.a = 0.0
		scrim.grab_focus()
		var tw := scrim.create_tween()
		tw.tween_property(scrim, "modulate:a", 1.0, 0.2)
	scrim.visibility_changed.connect(func():
		if scrim.visible:
			fade.call())
	scrim.ready.connect(fade)
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and on_dismiss.is_valid():
				if not body.get_global_rect().has_point(mb.global_position) \
						and not head.get_global_rect().has_point(mb.global_position):
					on_dismiss.call()
					scrim.accept_event())
	return {"scrim": scrim, "body": body}
