class_name PbTheme
extends RefCounted
## Builds the Godot Theme from PokeBonk's own CSS tokens.
##
## Source of truth: res://data/pb/ui_theme.json, extracted by
## pokebonk-web/tools-re/extract_ui_tokens.py straight out of the shipped
## stylesheet (`:root` custom properties, `.btn/.card/.chip/.seg/.lab-card`
## rules) plus the renderer's 18-type colour map. Nothing here is invented:
## radii, colours, the 4px button edge and the shadow values all come from CSS.
##
## One deliberate approximation: Godot's StyleBoxFlat has no vertical gradient,
## so the CSS ``linear-gradient(180deg, c+82% white, c 60%, cd 100%)`` is
## reproduced as a solid accent with a lightened top border and the darkened
## ``0 4px 0`` bottom edge (border_width_bottom), which is what gives the pill
## its chunky 3-D look.

const ACCENTS := {
	"yellow": {"c": "--yellow", "cd": "--yellow-d"},
	"red": {"c": "--red", "cd": "--red-d"},
	"blue": {"c": "--blue", "cd": "--blue-d"},
	"green": {"c": "--green", "cd": "--green-d"},
	"purple": {"c": "--purple", "cd": "--purple-d"},
	"orange": {"c": "--orange", "cd": "--yellow-d"},
	# .btn.ghost: {--c:var(--paper);--cd:var(--paper-3);--tc:var(--ink)}
	"ghost": {"c": "--paper", "cd": "--paper-3"},
}

const FONT_TITLE := "res://assets/fonts/MPLUSRounded-900.ttf"
const FONT_TITLE_BOLD := "res://assets/fonts/MPLUSRounded-800.ttf"
const FONT_BODY := "res://assets/fonts/Nunito-800.ttf"
const FONT_BODY_REGULAR := "res://assets/fonts/Nunito-700.ttf"

## The ported webfonts are latin subsets, so CJK (and the 中文 UI copy) needs a
## system fallback attached -- otherwise Han characters render as tofu boxes.
const CJK_FALLBACKS := ["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC",
	"Microsoft YaHei", "Heiti SC", "Source Han Sans SC", "Arial Unicode MS"]

static var _tokens: Dictionary = {}
static var _theme: Theme = null
static var _fonts := {}
static var _color_cache := {}
static var _mode := "light"
static var _decl_cache := {}
static var _sb_cache := {}


static func tokens() -> Dictionary:
	if _tokens.is_empty():
		_tokens = PbJson.as_dict(PbData.pb_table("ui_theme"))
		if _tokens.is_empty():
			push_warning("Theme: ui_theme.json missing, falling back to defaults "
						+ "(re-run tools-re/extract_ui_tokens.py)")
			_tokens = {"vars": {"light": {}, "dark": {}}, "type_colors": {}, "rules": {}}
	return _tokens


static func vars() -> Dictionary:
	var all := PbJson.as_dict(tokens().get("vars", {}))
	var light := PbJson.as_dict(all.get("light", {}))
	if _mode == "light":
		return light
	# CSS cascade semantics: the dark block overrides the light one, the rest stays.
	var merged := light.duplicate()
	for k in PbJson.as_dict(all.get("dark", {})):
		merged[k] = PbJson.as_dict(all.get("dark", {}))[k]
	return merged


static func set_mode(mode: String) -> void:
	if mode != _mode:
		_mode = mode
		reset_cache()


static func mode() -> String:
	return _mode


static func v(name: String, fallback: String = "") -> String:
	return String(vars().get(name, fallback))


## Parse one CSS colour token: #rgb / #rgba / #rrggbb / #rrggbbaa, plus the
## var()/color-mix()/rgb()/keyword forms the shipped stylesheet actually uses.
static func css_color(text: String, fallback: Color = Color.MAGENTA) -> Color:
	var t := text.strip_edges()
	if t.is_empty():
		return fallback
	if t.begins_with("var("):
		return css_color(resolve_vars(t), fallback)
	if t.begins_with("color-mix("):
		return _parse_color_mix(t, fallback)
	if t.begins_with("rgb"):
		return _parse_rgb_func(t, fallback)
	match t:
		"white": return Color.WHITE
		"black": return Color.BLACK
		"transparent": return Color(0, 0, 0, 0)
		"currentcolor": return ink()
	# Bare hex without the leading '#' (as produced by Color.to_html).
	if hex_looks_valid(t):
		return css_color("#" + t, fallback)
	if not t.begins_with("#"):
		return fallback
	var hex := t.substr(1)
	if hex.length() == 4:
		hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3]
	if hex.length() == 3:
		hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2] + "ff"
	if hex.length() == 8:
		var alpha := hex.substr(6, 2).hex_to_int()
		var col := _hex6(hex.substr(0, 6), fallback)
		col.a = float(alpha) / 255.0
		return col
	if hex.length() != 6:
		return fallback
	return _hex6(hex, fallback)


static func _hex6(hex: String, fallback: Color) -> Color:
	var value := hex.hex_to_int()
	var col := Color()
	col.r8 = (value >> 16) & 0xFF
	col.g8 = (value >> 8) & 0xFF
	col.b8 = value & 0xFF
	col.a = 1.0
	return col


static func hex_looks_valid(t: String) -> bool:
	if not (t.length() in [3, 4, 6, 8]):
		return false
	return RegEx.create_from_string("^[0-9a-fA-F]+$").search(t) != null


## color-mix(in srgb, A N%, B) -- the subset the CSS ships.
static func _parse_color_mix(t: String, fallback: Color) -> Color:
	var inner := t.trim_prefix("color-mix(").trim_suffix(")")
	var parts := split_top_commas(inner)
	if parts.size() < 3:
		return fallback
	var base_txt := parts[1].strip_edges()
	if parts[0].strip_edges() == "in oklch":
		pass # srgb lerp is the documented approximation.
	var col_a := fallback
	var weight := 1.0
	var m := RegEx.create_from_string("^(.+?)\\s+(\\d+(?:\\.\\d+)?)%$").search(base_txt)
	if m != null:
		col_a = css_color(resolve_vars(m.get_string(1).strip_edges()), fallback)
		weight = m.get_string(2).to_float() / 100.0
	else:
		col_a = css_color(resolve_vars(base_txt), fallback)
	var other := css_color(resolve_vars(parts[2].strip_edges()), fallback)
	return mix(col_a, other, weight)


static func _parse_rgb_func(t: String, fallback: Color) -> Color:
	var inner := t.substr(t.find("(") + 1).trim_suffix(")")
	var nums := RegEx.create_from_string(r"[\d.]+%").search_all(inner.replace("/", " "))
	var comps := []
	for n in nums:
		comps.append(n.get_string(0).trim_suffix("%").to_float() / 100.0)
	if comps.is_empty():
		for n in RegEx.create_from_string(r"[\d.]+").search_all(inner.replace("/", " ")):
			comps.append(n.get_string(0).to_float() / 255.0)
	if comps.size() < 3:
		return fallback
	var col := Color(comps[0], comps[1], comps[2])
	if comps.size() > 3:
		col.a = comps[3]
	return col


## Resolve var(--token[, fallback]) against the active theme's vars, recursively
## (the shadow tokens reference other tokens; nested funcs included).
static func resolve_vars(value: String) -> String:
	if not "var(" in value:
		return value
	var out := value
	var guard := 0
	while "var(" in out and guard < 8:
		guard += 1
		var idx := out.find("var(")
		var depth := 0
		var j := idx + 3
		while j < out.length():
			if out[j] == "(":
				depth += 1
			elif out[j] == ")":
				depth -= 1
				if depth == 0:
					break
			j += 1
		var inner := out.substr(idx + 4, j - idx - 4)
		var comma := _top_level_comma(inner)
		var token := inner if comma < 0 else inner.substr(0, comma)
		var fallback := "" if comma < 0 else inner.substr(comma + 1)
		var replaced := String(vars().get(token.strip_edges(), fallback.strip_edges()))
		# var(--x, color-mix(...)) : fallbacks may themselves be funcs.
		replaced = resolve_vars(replaced)
		out = out.substr(0, idx) + replaced + out.substr(j + 1)
	return out


static func _top_level_comma(s: String) -> int:
	var depth := 0
	for i in s.length():
		match s[i]:
			"(": depth += 1
			")": depth -= 1
			",":
				if depth == 0:
					return i
	return -1


## Split a CSS value list at top-level commas (nested funcs stay intact).
static func split_top_commas(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var current := ""
	for i in s.length():
		var ch := s[i]
		match ch:
			"(":
				depth += 1
				current += ch
			")":
				depth -= 1
				current += ch
			",":
				if depth == 0:
					out.append(current.strip_edges())
					current = ""
				else:
					current += ch
			_:
				current += ch
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


## One rule body from ui_theme.json `rules`, as raw CSS text ("" when absent).
static func rule(sel: String) -> String:
	return String(PbJson.as_dict(tokens().get("rules", {})).get(sel, ""))


## Parsed declarations of a rule; per-instance vars_for tokens (--c/--rc/...)
## are substituted so one selector can paint many instances. Custom properties
## declared inside the rule itself (`--c:var(--yellow)` in .btn) act as the
## default layer, exactly like the CSS cascade applies them on the site.
static func decls(sel: String, vars_for: Dictionary = {}) -> Dictionary:
	var key := _mode + "|" + sel
	if not _decl_cache.has(key):
		var raw := {}
		var local := {}
		for decl in _split_decls(rule(sel)):
			var colon: int = decl.find(":")
			if colon <= 0:
				continue
			var name := decl.substr(0, colon).strip_edges()
			var value := decl.substr(colon + 1).strip_edges()
			if name.begins_with("--"):
				local[name] = value
			else:
				raw[name] = value
		_decl_cache[key] = {"decls": raw, "local": local}
	var entry: Dictionary = _decl_cache[key]
	var merged := PbJson.as_dict(entry.get("local", {}))
	for k in vars_for:
		merged[("--" + String(k)) if not String(k).begins_with("--") else String(k)] = vars_for[k]
	var out := {}
	for k in PbJson.as_dict(entry.get("decls", {})):
		out[k] = _substitute(String(entry["decls"][k]), merged)
	return out


static func _split_decls(body: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var current := ""
	for i in body.length():
		var ch := body[i]
		if ch == ";" and depth == 0:
			out.append(current)
			current = ""
			continue
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		current += ch
	if not current.strip_edges().is_empty():
		out.append(current)
	return out


## Inject `--x: value` pairs into a CSS value (the web DOM sets --c/--rc/--p
## with style.setProperty; Godot passes them per call, rule-local defaults fill
## the rest). Handles the var(--x, fallback) form by dropping the fallback.
static func _substitute(value: String, vars_for: Dictionary) -> String:
	var out := value
	var search := 0
	var guard := 0
	while guard < 48:
		guard += 1
		var idx := out.find("var(", search)
		if idx < 0:
			break
		var close := _func_end(out, idx)
		var inner := out.substr(idx + 4, close - idx - 4)
		var comma := _top_level_comma(inner)
		var token := (inner if comma < 0 else inner.substr(0, comma)).strip_edges()
		var replacement: Variant = null
		if vars_for.has(token):
			replacement = vars_for[token]
		elif vars_for.has(token.trim_prefix("--")):
			replacement = vars_for[token.trim_prefix("--")]
		if replacement != null:
			out = out.substr(0, idx) + String(replacement) + out.substr(close + 1)
			search = idx + String(replacement).length()
		else:
			# keep scanning past this token; resolve_vars handles the fallback later
			search = close + 1
	return out


static func _px(value: String, fallback: float = 0.0) -> float:
	var resolved := resolve_vars(value).strip_edges()
	if resolved.is_empty():
		return fallback
	var num := RegEx.create_from_string("^-?[\\d.]+").search(resolved)
	if num == null:
		return fallback
	var n := num.get_string(0).to_float()
	# time units: "450ms"/".35s" report through _px callers as raw numbers
	if resolved.ends_with("ms"):
		return n / 1000.0
	return n


## box-shadow layers: [{x,y,blur,spread,color,inset}] straight from the CSS.
static func shadow_layers(value: String) -> Array:
	var out := []
	for layer in split_top_commas(resolve_vars(value)):
		var l := layer.strip_edges()
		if l.is_empty() or l == "none":
			continue
		var inset := l.begins_with("inset")
		if inset:
			l = l.trim_prefix("inset").strip_edges()
		# lengths come first, the colour is whatever remains (may contain spaces
		# only when funcs are involved, which have no raw spaces after resolve).
		var tokens_arr := l.split(" ", false)
		var lengths := []
		var color_txt := ""
		var collecting_color := false
		for tokv in tokens_arr:
			var tt := tokv.strip_edges()
			if collecting_color:
				color_txt += " " + tt
			elif tt.ends_with("px") or tt == "0" or tt.is_valid_float():
				lengths.append(_px(tt))
			else:
				collecting_color = true
				color_txt = tt
		if lengths.is_empty():
			continue
		out.append({
			"x": lengths[0] if lengths.size() > 0 else 0.0,
			"y": lengths[1] if lengths.size() > 1 else lengths[0],
			"blur": lengths[2] if lengths.size() > 2 else 0.0,
			"spread": lengths[3] if lengths.size() > 3 else 0.0,
			"color": css_color(color_txt, Color(0, 0, 0, 0.2)),
			"inset": inset,
		})
	return out


## linear-gradient(...) -> {type,angle,stops:[{color,pos}]}. conic/radial return
## {type,raw} so widgets can pick their own approximation (ult ring, tiles).
## Values like "var(--stripes), linear-gradient(135deg, ...)" are scanned for
## the first non-repeating linear-gradient layer.
static func gradient(value: String, vars_for: Dictionary = {}) -> Dictionary:
	var vtxt := resolve_vars(_substitute(value.strip_edges(), vars_for))
	var start := _find_linear_gradient(vtxt)
	if start < 0:
		if "conic-gradient(" in vtxt:
			var ci := vtxt.find("conic-gradient(")
			return {"type": "conic", "raw": vtxt.substr(ci, _func_end(vtxt, ci) - ci + 1)}
		if "repeating-linear-gradient(" in vtxt:
			return {"type": "stripes", "raw": vtxt}
		if "radial-gradient(" in vtxt:
			return {"type": "radial", "raw": vtxt}
		return {}
	var inner := _func_args(vtxt, start)
	var parts := split_top_commas(inner)
	if parts.is_empty():
		return {}
	var angle := 180.0
	var first := parts[0]
	if "deg" in first or first.begins_with("to "):
		angle = _px(first, 180.0)
		parts.remove_at(0)
	var stops := []
	var evenly := parts.size() - 1
	for i in parts.size():
		var toks := _split_top_spaces(String(parts[i]))
		if toks.is_empty():
			continue
		var pos := -1.0
		for j in range(1, toks.size()):
			var m := RegEx.create_from_string("^(-?[\\d.]+)(%|px|em)?").search(toks[j])
			if m != null and pos < 0.0:
				pos = m.get_string(1).to_float()
		if pos < 0.0 and evenly > 0:
			pos = float(i) / float(evenly) * 100.0
		stops.append({"color": css_color(toks[0], ink()), "pos": pos})
	return {"type": "linear", "angle": angle, "stops": stops}


## Index of a `linear-gradient(` that is not `repeating-`.
static func _find_linear_gradient(s: String) -> int:
	var idx := s.find("linear-gradient(")
	while idx > 0 and s.substr(0, idx).ends_with("repeating-"):
		idx = s.find("linear-gradient(", idx + 1)
	return idx


## End index (the closing ')') of the function call that starts at `start`.
static func _func_end(s: String, start: int) -> int:
	var open := s.find("(", start)
	var depth := 0
	var j := open
	while j < s.length():
		if s[j] == "(":
			depth += 1
		elif s[j] == ")":
			depth -= 1
			if depth == 0:
				break
		j += 1
	return j


## The argument text between a function call's parens.
static func _func_args(s: String, start: int) -> String:
	var open := s.find("(", start)
	var close := _func_end(s, start)
	return s.substr(open + 1, close - open - 1)


static func _split_top_spaces(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var current := ""
	for i in s.length():
		var ch := s[i]
		match ch:
			"(":
				depth += 1
				current += ch
			")":
				depth -= 1
				current += ch
			" ", "\t":
				if depth == 0:
					if not current.is_empty():
						out.append(current)
					current = ""
				else:
					current += ch
			_:
				current += ch
	if not current.is_empty():
		out.append(current)
	return out


## Generic StyleBoxFlat built from a shipped CSS rule: background, border-radius,
## padding, box-shadow and border all come off the rule body, so ported widgets
## reuse the site's numbers instead of hand-tuned ones.
static func stylebox(sel: String, vars_for: Dictionary = {}) -> StyleBoxFlat:
	var d := decls(sel, vars_for)
	if d.is_empty():
		push_warning("Theme: rule %s missing in ui_theme.json (re-run extract_ui_tokens.py)" % sel)
		var empty := StyleBoxFlat.new()
		return empty
	var s := StyleBoxFlat.new()
	var bg_raw := String(d.get("background", d.get("background-color", "")))
	# "background: colour; background: gradient" double-declaration: the second
	# wins on the web, so prefer a gradient layer's end colour when present.
	var fallback_col := css_color(bg_raw.split(";")[0], paper())
	if bg_raw.begins_with("linear-gradient") or "linear-gradient" in bg_raw:
		var g := gradient(bg_raw, vars_for)
		if g.has("stops") and not g["stops"].is_empty():
			# solid approximation = middle stop (the 60% body colour of .btn).
			var stops: Array = g["stops"]
			fallback_col = stops[int(stops.size() / 2)]["color"]
	s.bg_color = fallback_col
	var radius_txt := resolve_vars(String(d.get("border-radius", "")))
	if not radius_txt.is_empty() and radius_txt != "0":
		s.set_corner_radius_all(int(_px(radius_txt, 0.0)))
		if _px(radius_txt) > 900.0:
			s.corner_detail = 12
	_apply_padding(s, resolve_vars(String(d.get("padding", ""))))
	if d.has("box-shadow") and String(d["box-shadow"]) != "none":
		for layer in shadow_layers(String(d["box-shadow"])):
			if layer["inset"]:
				# inset 0 -2px shade -> bottom border (the chip's under-edge).
				if absf(layer["y"]) > 0.0 and layer["blur"] <= 4.0:
					s.border_width_bottom = int(absf(layer["y"]))
					s.border_color = layer["color"]
				continue
			if layer["spread"] > 0.0 and layer["x"] == 0.0 and layer["y"] == 0.0:
				s.set_border_width_all(int(layer["spread"]))
				s.border_color = layer["color"]
			elif layer["blur"] == 0.0 and layer["y"] >= 2.0:
				# chunky 3-D edge (0 4px 0 colour): bottom border in the dark tone.
				s.border_width_bottom = int(layer["y"])
				s.border_color = layer["color"]
			elif s.shadow_size == 0:
				s.shadow_size = int(maxf(2.0, layer["blur"] * 0.7))
				s.shadow_color = layer["color"]
				s.shadow_offset = Vector2(layer["x"], layer["y"])
	if s.shadow_size > 0:
		s.anti_aliasing = true
	if d.has("border") and not String(d["border"]).begins_with("none"):
		var b := resolve_vars(String(d["border"])).split(" ", false)
		if b.size() >= 3:
			s.set_border_width_all(int(_px(b[0])))
			s.border_color = css_color(b[2], line())
			if String(d["border"]).contains("bottom"):
				s.border_width_top = 0
				s.border_width_left = 0
				s.border_width_right = 0
	if d.has("border-color"):
		s.border_color = css_color(String(d["border-color"]), s.border_color)
	return s


static func _apply_padding(s: StyleBoxFlat, pad: String) -> void:
	if pad.is_empty():
		return
	var values := []
	for nv in pad.split(" ", false):
		var t := nv.strip_edges()
		if t.ends_with("px") or t.is_valid_float() or t == "0":
			values.append(int(_px(t)))
	match values.size():
		1:
			s.content_margin_left = values[0]
			s.content_margin_right = values[0]
			s.content_margin_top = values[0]
			s.content_margin_bottom = values[0]
		2:
			s.content_margin_top = values[0]
			s.content_margin_bottom = values[0]
			s.content_margin_left = values[1]
			s.content_margin_right = values[1]
		3:
			s.content_margin_top = values[0]
			s.content_margin_left = values[1]
			s.content_margin_right = values[1]
			s.content_margin_bottom = values[2]
		4:
			s.content_margin_top = values[0]
			s.content_margin_right = values[1]
			s.content_margin_bottom = values[2]
			s.content_margin_left = values[3]


## animation shorthand of a rule: {name, duration, delay, easing} (seconds).
static func anim_of(sel: String, fallback_name: String = "") -> Dictionary:
	var out := {"name": fallback_name, "duration": 0.0, "delay": 0.0, "easing": "ease-out"}
	var a := String(decls(sel).get("animation", ""))
	if a.is_empty():
		return out
	# Values like ".35s ease-out backwards cardIn" or "tileIn .35s var(--d,0s) backwards".
	for tokv in a.split(" ", false):
		var t := tokv.strip_edges()
		if t.begins_with("var(") or t.begins_with("calc("):
			continue
		if t.ends_with("ms") or (t.ends_with("s") and t.is_valid_float() == false):
			var secs := _px(t)
			if out["duration"] == 0.0:
				out["duration"] = secs
			else:
				out["delay"] = secs
		elif t.begins_with("cubic-bezier") or t.begins_with("ease") or t in ["linear"]:
			out["easing"] = t
		elif keyframes().has(t):
			out["name"] = t
	return out


static func keyframes() -> Dictionary:
	return PbJson.as_dict(tokens().get("keyframes", {}))


## Frames of one @keyframes as [{pos, decl: value}]; the port's Tween guide.
static func keyframe_frames(name: String) -> Array:
	var body := String(keyframes().get(name, ""))
	var out := []
	if body.is_empty():
		return out
	for m in RegEx.create_from_string(r"([\d.]+%|from|to)\s*\{").search_all(body):
		var pos := m.get_string(1)
		var pct := 100.0
		if pos == "from":
			pct = 0.0
		elif pos == "to":
			pct = 100.0
		else:
			pct = pos.trim_suffix("%").to_float()
		var start := body.find("{", m.get_start()) + 1
		var end := body.find("}", start)
		var frame := {"pos": pct / 100.0}
		for decl in _split_decls(body.substr(start, end - start)):
			var colon := decl.find(":")
			if colon > 0:
				frame[decl.substr(0, colon).strip_edges()] = decl.substr(colon + 1).strip_edges()
		out.append(frame)
	return out


# ---- shared JS tables (rarity / danger), offsets recorded in the JSON -------
static func _js_table(where: String, which: String) -> Array:
	var grp := PbJson.as_dict(tokens().get(where, {}))
	var txt := String(PbJson.as_dict(grp.get(which, {})).get("text", ""))
	var out := []
	if txt.is_empty():
		return out
	for item in split_top_commas(txt.trim_prefix("[").trim_suffix("]")):
		var m := RegEx.create_from_string(r"`([^`]+)`|(\d+(?:\.\d+)?)").search(item)
		if m == null:
			continue
		var s := m.get_string(1)
		if not s.is_empty():
			out.append(s)
		else:
			out.append(m.get_string(2).to_float())
	return out


## rarity 0..4 -> --r0..--r4 token colours (nD @1386869).
static func rarity_color(rarity: int) -> Color:
	var idx := clampi(rarity, 0, 4)
	return css_color(v("--r%d" % idx, "#9aa4b8"), Color("#9aa4b8"))


## bp-dot colours (news @54849): the small rarity pips.
static func rarity_dot_color(rarity: int) -> Color:
	var colors := _js_table("rarity", "dot_colors")
	if colors.is_empty():
		return rarity_color(rarity)
	return css_color(String(colors[clampi(rarity, 0, colors.size() - 1)]), rarity_color(rarity))


static func rarity_labels() -> Array:
	# es source strings (news @54781); screens map them to their own gloss.
	return _js_table("rarity", "labels")


## danger meter (main @2122027): segment thresholds and colours.
static func danger_thresholds() -> Array:
	return _js_table("danger", "thresholds")


static func danger_colors() -> Array:
	return _js_table("danger", "colors")


static func danger_level(value: float) -> int:
	var th := danger_thresholds()
	var lvl := 0
	for i in th.size():
		if value >= float(th[i]):
			lvl = i
	return lvl


static func line() -> Color:
	return css_color(v("--line", "#e4e0f0"), Color("#e4e0f0"))


## colour-mix(in srgb, var(--x) N%, other) -- the subset the CSS actually uses.
static func mix(base: Color, other: Color, weight: float) -> Color:
	return base * weight + other * (1.0 - weight)


static func accent_color(accent: String, which: String = "c") -> Color:
	var map := PbJson.as_dict(ACCENTS.get(accent, ACCENTS["yellow"]))
	var token := String(map.get(which, "--yellow"))
	var key := accent + ":" + which
	if _color_cache.has(key):
		return _color_cache[key]
	var col := css_color(v(token, "#ffcc33"), Color("#ffcc33"))
	_color_cache[key] = col
	return col


static func type_color(type_name: String) -> Color:
	var table := PbJson.as_dict(tokens().get("type_colors", {}))
	var hex := String(table.get(type_name, ""))
	if hex.is_empty():
		return Color("#9aa4b8")
	return css_color(hex, Color("#9aa4b8"))


static func font(weight: String = "body") -> Font:
	if _fonts.is_empty():
		var cjk := _cjk_fallback()
		var paths := {
			"title": FONT_TITLE,
			"title_bold": FONT_TITLE_BOLD,
			"body": FONT_BODY,
			"body_regular": FONT_BODY_REGULAR,
		}
		for key in paths.keys():
			var path := String(paths[key])
			if ResourceLoader.exists(path):
				var loaded := load(path)
				if loaded is FontFile and cjk != null:
					(loaded as FontFile).fallbacks = [cjk]
				_fonts[key] = loaded
			else:
				push_warning("Theme: font missing at %s (run the import step)" % path)
	return _fonts.get(weight, ThemeDB.fallback_font)


static func _cjk_fallback() -> Font:
	if _fonts.has("cjk"):
		return _fonts["cjk"]
	var sys := SystemFont.new()
	sys.font_names = CJK_FALLBACKS
	sys.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_fonts["cjk"] = sys
	return sys


static func radius() -> int:
	return v("--radius", "22px").trim_suffix("px").to_int()


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", card_style())
	t.set_stylebox("panel", "Panel", card_style(Color("#f3f1fa")))
	t.set_stylebox("normal", "Button", button_style("yellow"))
	t.set_stylebox("hover", "Button", button_style("yellow", 0.10))
	t.set_stylebox("pressed", "Button", button_style("yellow", 0.0, true))
	t.set_stylebox("disabled", "Button", button_disabled())
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("normal", "OptionButton", pill_field())
	t.set_stylebox("pressed", "OptionButton", pill_field(true))
	t.set_stylebox("selected", "OptionButton", pill_field(true))
	t.set_stylebox("hover", "OptionButton", pill_field())
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", line_style())
	t.set_stylebox("read_only", "LineEdit", line_style())
	t.set_stylebox("focus", "LineEdit", line_style(true))
	t.set_stylebox("background", "ProgressBar", bar_background())
	t.set_stylebox("fill", "ProgressBar", bar_fill(Color("#36c96a")))
	t.set_stylebox("background", "HSlider", bar_background())
	t.set_stylebox("slider", "HSlider", slider_knob())
	t.set_color("font_color", "Label", ink())
	t.set_font("font", "Label", font("body"))
	t.set_font_size("font_size", "Label", 15)
	t.set_color("font_color", "Button", Color("#2a2440"))
	t.set_font("font", "Button", font("title_bold"))
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "OptionButton", ink())
	t.set_color("font_selected_color", "OptionButton", ink())
	t.set_constant("h_separation", "BoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	_theme = t
	return t


static func ink() -> Color:
	return css_color(v("--ink", "#2a2440"), Color("#2a2440"))


static func ink_muted() -> Color:
	return css_color(v("--muted", "#7a7494"), Color("#7a7494"))


static func paper(shift: float = 0.0) -> Color:
	var token := "--paper" if shift <= 0.0 else ("--paper-2" if shift <= 1.0 else "--paper-3")
	return css_color(v(token, "#ffffff"), Color.WHITE)


## .card: { background: var(--paper); border-radius: 22px;
##          box-shadow: 0 10px 28px #1a124638, 0 2px 6px #1a12461f }
static func card_style(override: Color = Color(1, 1, 1, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = override if override.a > 0.0 else paper()
	var r := maxi(6, radius())
	s.set_corner_radius_all(r)
	s.shadow_size = 14
	s.shadow_color = css_color("#1a124638", Color(0.1, 0.07, 0.27, 0.22))
	s.shadow_offset = Vector2(0, 8)
	s.anti_aliasing = true
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


## .btn: pill + vertical gradient + 0 4px 0 dark edge + soft drop shadow.
## StyleBoxFlat has one border colour, so the gradient's lighter top is folded
## into the background and the dark bottom edge carries the border colour.
static func button_style(accent: String = "yellow", lighten: float = 0.0, pressed: bool = false) -> StyleBoxFlat:
	var c := accent_color(accent, "c")
	var cd := accent_color(accent, "cd")
	var s := StyleBoxFlat.new()
	s.bg_color = mix(c, Color.WHITE, 0.06) if pressed else mix(c, Color.WHITE, 0.14 + lighten)
	s.set_corner_radius_all(999)
	s.corner_detail = 12
	s.border_width_bottom = 2 if pressed else 6
	s.border_color = mix(cd, Color.BLACK, 0.25)
	s.shadow_size = 0 if pressed else 8
	s.shadow_color = css_color("#1a124626", Color(0.1, 0.07, 0.27, 0.15))
	s.shadow_offset = Vector2(0, 4 if pressed else 8)
	s.anti_aliasing = true
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 12 if pressed else 10
	s.content_margin_bottom = 12
	return s


static func button_disabled() -> StyleBoxFlat:
	var s := button_style("yellow")
	s.bg_color = Color(s.bg_color, 0.45)
	s.border_color = Color(s.border_color, 0.5)
	s.shadow_size = 0
	s.border_width_bottom = 3
	return s


static func pill_field(pressed: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = paper(1.0) if not pressed else mix(paper(1.0), Color.WHITE, 0.4)
	s.set_corner_radius_all(999)
	s.corner_detail = 10
	s.border_width_bottom = 2
	s.border_color = css_color(v("--line", "#e4e0f0"), Color("#e4e0f0"))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func line_style(focused: bool = false) -> StyleBoxFlat:
	var s := pill_field(focused)
	s.bg_color = paper(2.0)
	if focused:
		s.border_color = accent_color("blue", "c")
	return s


static func bar_background() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = mix(paper(1.0), ink(), 0.10)
	s.set_corner_radius_all(999)
	s.corner_detail = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.content_margin_left = 0
	s.content_margin_right = 0
	return s


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(999)
	s.corner_detail = 8
	s.anti_aliasing = true
	return s


static func slider_knob() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.WHITE
	s.set_corner_radius_all(999)
	s.set_border_width_all(3)
	s.border_color = css_color(v("--ink", "#2a2440"), Color("#2a2440"))
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.shadow_size = 4
	s.shadow_color = css_color("#1a124633", Color(0.1, 0.07, 0.27, 0.2))
	return s


## ---- semantic wrappers over the extracted component rules ------------------
## Each one folds the CSS double-declarations (colour layer + gradient layer)
## into the closest StyleBoxFlat approximation; see the gradient/stripe notes
## in docs/PORT_STATUS.md.

## .hud-top: frosted pill panel with the striped --bc stage band on top.
static func hud_top_style() -> StyleBoxFlat:
	return stylebox(".hud-top")


## .timer: the poké-ball pill clock; .final swaps in the red pulse gradient.
static func timer_style(final: bool = false) -> StyleBoxFlat:
	var s := stylebox(".timer")
	if final:
		var g := gradient(String(decls(".timer.final").get("background", "")))
		if g.has("stops") and not g["stops"].is_empty():
			s.bg_color = g["stops"][0]["color"]
	return s


## .card .top: rarity band. The 135° gradient is sampled at its mid stop and
## the stripes overlay is drawn separately (UI.stripes_overlay).
static func card_top_style(rc: Color) -> StyleBoxFlat:
	var s := stylebox(".card .top", {"rc": "#" + rc.to_html(false)})
	return s


## .card.offer body: paper card ringed in the rarity colour (--rc hover outline
## is applied by UI.card_offer through mouse_entered/exited).
static func offer_card_style(rc: Color, hovered: bool = false) -> StyleBoxFlat:
	var s := stylebox(".card")
	if hovered:
		var hs := stylebox(".card:hover")
		s.border_width_top = hs.border_width_top
		s.border_width_bottom = 4
		s.border_color = hs.border_color
	else:
		s.border_color = rc
	return s


## .scr-title: skewed red→orange striped plate behind the screen h1.
static func scr_title_style(accent_raw: String = "") -> StyleBoxFlat:
	var d := decls(".scr-title")
	var bg := String(d.get("background", ""))
	if not accent_raw.is_empty():
		bg = bg.replace("var(--red)", accent_raw)
	var s := StyleBoxFlat.new()
	var g := gradient(bg)
	s.bg_color = g["stops"][0]["color"] if g.has("stops") and g["stops"].size() > 0 else accent_color("red", "c")
	s.set_corner_radius_all(int(_px(resolve_vars(String(d.get("border-radius", "14px"))))))
	_apply_padding(s, resolve_vars(String(d.get("padding", ""))))
	for layer in shadow_layers(String(d.get("box-shadow", ""))):
		if layer["blur"] == 0.0 and layer["y"] >= 2.0:
			s.border_width_bottom = int(layer["y"])
			s.border_color = layer["color"]
		s.shadow_size = int(maxf(s.shadow_size, layer["blur"] * 0.7))
		s.shadow_color = layer["color"]
		s.shadow_offset = Vector2(layer["x"], layer["y"])
	if s.shadow_size > 0:
		s.anti_aliasing = true
	return s


## .screen.dim + .modal: the radial scrim behind popups.
static func modal_scrim() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# radial-gradient(#1e144626,#140e329e): take the outer (dominant) colour.
	s.bg_color = css_color("#140e329e", Color(0.08, 0.055, 0.196, 0.62))
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	return s


## .pill / .pill.on inside .seg: segmented filter chips.
static func pill_seg_style(on: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var d := decls(".pill.on") if on else decls(".pill")
	s.bg_color = css_color(String(d.get("background", "0 0")), Color(0, 0, 0, 0)) if on else Color(0, 0, 0, 0)
	if on and s.bg_color.a <= 0.0:
		s.bg_color = paper()
	s.set_corner_radius_all(999)
	s.corner_detail = 10
	_apply_padding(s, resolve_vars(String(d.get("padding", "7px 14px"))))
	if on:
		for layer in shadow_layers(String(d.get("box-shadow", ""))):
			if layer["blur"] == 0.0 and layer["y"] >= 1.0:
				s.border_width_bottom = int(layer["y"])
				s.border_color = layer["color"]
			elif s.shadow_size == 0:
				s.shadow_size = int(layer["blur"] * 0.7)
				s.shadow_color = layer["color"]
				s.shadow_offset = Vector2(layer["x"], layer["y"])
	return s


static func seg_track_style() -> StyleBoxFlat:
	return stylebox(".seg")


## .switch off/on: 58x32 track; the knob is a child Control painted by UI.switch.
static func switch_track_style(on: bool, accent: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = css_color("#d4cfe6", Color("#d4cfe6")) if not on else (
		accent if accent.a > 0.0 else accent_color("green", "c"))
	s.set_corner_radius_all(99)
	s.corner_detail = 10
	if not on:
		for layer in shadow_layers(String(decls(".switch").get("box-shadow", ""))):
			if layer["inset"]:
				s.draw_center = true
	return s


static func switch_knob_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = paper()
	s.set_corner_radius_all(999)
	s.shadow_size = 4
	s.shadow_color = css_color("#00000040", Color(0, 0, 0, 0.25))
	s.shadow_offset = Vector2(0, 2)
	s.anti_aliasing = true
	return s


## .field / .field:focus: pill input with the 2px --line / --blue border.
## The focus rule only restates border-colour + background, so both merge.
static func field_style(focused: bool = false) -> StyleBoxFlat:
	var s := stylebox(".field")
	if focused:
		var f := decls(".field:focus")
		s.bg_color = css_color(String(f.get("background", "")), paper())
		s.border_color = css_color(String(f.get("border-color", "")), accent_color("blue", "c"))
	return s


## .back-btn: paper pill with its 3px bottom edge.
static func back_btn_style() -> StyleBoxFlat:
	return stylebox(".back-btn")


## .toast: frosted pill row in the top-centre stack.
static func toast_style() -> StyleBoxFlat:
	return stylebox(".toast")


## .kgoal: the stage-goal card (hud right column).
static func kgoal_style() -> StyleBoxFlat:
	return stylebox(".kgoal")


## .wallet: gold pill; the >b amount uses the fixed #b8860b ink.
static func wallet_style() -> StyleBoxFlat:
	return stylebox(".wallet")


static func wallet_gold() -> Color:
	return css_color("#b8860b", Color("#b8860b"))


## hpbar fill states (CSS .hpbar>i / .mid / .low gradients): the port samples
## the vertical gradient into {top,base} so the bar can fake it with two tones.
static func hpbar_colors() -> Dictionary:
	var out := {}
	for pair in [["high", ".hpbar>i"], ["mid", ".hpbar.mid>i"], ["low", ".hpbar.low>i"]]:
		var g := gradient(String(decls(String(pair[1])).get("background", "")))
		var stops: Array = g.get("stops", [])
		var top: Color = stops[0]["color"] if stops.size() > 0 else accent_color("green", "c")
		var base: Color = stops[stops.size() - 1]["color"] if stops.size() > 1 else top
		out[String(pair[0])] = {"top": top, "base": base}
	return out


## --stripes: repeating-linear-gradient(-45deg, #ffffff24 0 10px, #fff0 10px 20px)
## -> {angle, color, period}; UI draws the overlay from these numbers.
static func stripes() -> Dictionary:
	var raw := v("--stripes", "")
	var out := {"angle": -45.0, "color": Color(1, 1, 1, 0.14), "period": 20.0}
	var ang := RegEx.create_from_string("gradient\\((-?[\\d.]+)deg").search(raw)
	if ang != null:
		out["angle"] = ang.get_string(1).to_float()
	var col := RegEx.create_from_string(r"gradient\([^,]+,\s*([^\s)]+)").search(raw)
	if col != null:
		out["color"] = css_color(col.get_string(1), Color(1, 1, 1, 0.14))
	var per := RegEx.create_from_string(r"(\d+)px\s+(\d+)px\)").search(raw)
	if per != null:
		out["period"] = float(per.get_string(2))
	return out


## Repaint one button with an accent + size, mirroring .btn / .btn.small /
## .btn.big (padding and font-size come from those rules).
static func paint(button: Button, accent: String = "yellow", big: bool = false, small: bool = false) -> Button:
	button.add_theme_stylebox_override("normal", button_style(accent))
	button.add_theme_stylebox_override("hover", button_style(accent, 0.10))
	button.add_theme_stylebox_override("pressed", button_style(accent, 0.0, true))
	button.add_theme_stylebox_override("disabled", button_disabled())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink_col := css_color(v("--ink", "#2a2440"), Color("#2a2440"))
	var on_ink := ink_col
	# .btn.red/.blue/.green invert the text to white (--tc:#fff); yellow keeps ink.
	if accent in ["red", "blue", "green", "purple"]:
		on_ink = Color.WHITE
	button.add_theme_color_override("font_color", on_ink)
	button.add_theme_color_override("font_disabled_color", Color("#7a7494"))
	button.add_theme_color_override("font_hover_color", on_ink)
	button.add_theme_font_override("font", font("title_bold"))
	var fs := 13 if small else (22 if big else 17)
	button.add_theme_font_size_override("font_size", fs)
	# Sizes straight off .btn.small/.btn/.btn.big padding.
	var pad_size_sel := ".btn"
	if small:
		pad_size_sel = ".btn.small"
	elif big:
		pad_size_sel = ".btn.big"
	var pd := decls(pad_size_sel)
	var pad := resolve_vars(String(pd.get("padding", "12px 26px")))
	var nums := pad.split(" ", false)
	var pad_v := int(_px(String(nums[0]))) if nums.size() > 0 else 12
	var pad_h := int(_px(String(nums[1]))) if nums.size() > 1 else 26
	var normal := button_style(accent)
	normal.content_margin_left = pad_h
	normal.content_margin_right = pad_h
	normal.content_margin_top = pad_v - 2
	normal.content_margin_bottom = pad_v
	button.add_theme_stylebox_override("normal", normal)
	var hover := button_style(accent, 0.10)
	hover.content_margin_left = pad_h
	hover.content_margin_right = pad_h
	hover.content_margin_top = pad_v - 2
	hover.content_margin_bottom = pad_v
	button.add_theme_stylebox_override("hover", hover)
	button.focus_mode = Control.FOCUS_NONE
	return button


## Re-paint a panel as a .card (or a .lab-card tile with an accent ring).
static func paint_card(panel: Control, accent_ring: Color = Color(0, 0, 0, 0)) -> void:
	var s := card_style()
	if accent_ring.a > 0.0:
		s.border_width_left = 3
		s.border_width_right = 3
		s.border_width_top = 3
		s.border_color = accent_ring
	if panel is PanelContainer:
		(panel as PanelContainer).add_theme_stylebox_override("panel", s)
	elif panel is Panel:
		(panel as Panel).add_theme_stylebox_override("panel", s)


## .chip: title font, white text with a 1px shadow, pill, inset bottom shade.
static func chip_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(999)
	s.corner_detail = 8
	s.border_width_bottom = 2
	s.border_color = Color(0, 0, 0, 0.15)
	s.shadow_color = Color(0, 0, 0, 0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	return s


## The site's striped texture (--stripes) used on meters and hype bars.
static func stripes_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.draw_center = true
	s.set_corner_radius_all(999)
	s.corner_detail = 8
	return s


static func reset_cache() -> void:
	_theme = null
	_fonts = {}
	_color_cache = {}
	_decl_cache = {}
	_sb_cache = {}
	_tokens = {}
