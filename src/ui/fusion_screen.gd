extends Control
## Bill's fusion machine: browse the recovered fusion catalogue and preview what
## a fusion would do with the current stats.
##
## All numbers come from the ported pipeline: PbFusion.recipe_for/offers (Uw/Gw),
## PbFusion.fused_def (JC) and PbDamage.move_instance (yA), so the preview and an
## in-run fusion use the same code path.


var _moves: Array = []
var _list: VBoxContainer
var _preview: VBoxContainer
var _status: Label
var _max_level := true
var _filter := "all"
var _catalogue: Array = []


func _ready() -> void:
	UI.fill(self)
	var scr := UI.screen()
	add_child(scr)
	UI.fill(scr)
	var root := UI.content(scr, 18)

	root.add_child(UI.screen_head("融合机器", "Máquina de fusión", func(): App.back_to_menu()))
	_status = UI.dim("")
	root.add_child(_status)
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	# ---- left: the actor's move list + toggles
	var left := UI.panel(12)
	row.add_child(left)
	var lv := UI.vbox(6)
	left.add_child(lv)
	lv.add_child(UI.label("当前招式", 18))
	var actor := _actor()
	_moves = PbJson.as_array(actor.get("moves", []))
	for i in _moves.size():
		var m = _moves[i]
		if m == null:
			lv.add_child(UI.dim("槽 %d：(空)" % i))
			continue
		var def := PbJson.as_dict(PbJson.as_dict(m).get("def", {}))
		lv.add_child(UI.label("槽 %d：%s [%s/%s] Lv%d" % [
			i, String(def.get("name", "?")), String(def.get("type", "")),
			String(def.get("arch", "")), int(PbJson.as_dict(m).get("level", 1))], 14))
	lv.add_child(HSeparator.new())
	lv.add_child(UI.button("把招式设为 8 级（可融合）", func(): _toggle_levels()))
	var swap := UI.hbox(6)
	lv.add_child(swap)
	swap.add_child(UI.button("重新随机招式", func(): _reroll_moves()))
	swap.add_child(UI.button("返回", func(): App.back_to_menu(), false, "ghost"))

	# ---- middle: offers / catalogue
	var mid := UI.panel(12)
	mid.custom_minimum_size = Vector2(360, 0)
	row.add_child(mid)
	var mv := UI.vbox(4)
	mid.add_child(mv)
	mv.add_child(UI.label("可融合组合", 18))
	var kind_items := []
	for kind in ["all", "signature", "reaction", "type", "glitch"]:
		kind_items.append({"id": kind, "text": _kind_label(kind)})
	mv.add_child(UI.segment(kind_items, _filter, func(id): _set_filter(id)))
	var sc := UI.scroll()
	sc.custom_minimum_size = Vector2(340, 380)
	mv.add_child(sc)
	_list = UI.vbox(3)
	sc.add_child(_list)

	# ---- right: preview
	var right := UI.panel(12)
	right.custom_minimum_size = Vector2(420, 0)
	row.add_child(right)
	_preview = UI.vbox(4)
	right.add_child(_preview)

	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


func _actor() -> Dictionary:
	var profile: Dictionary = Save.load_profile()
	var species := int(profile.get("starter", 0))
	if species <= 0:
		species = int(profile.get("lastSpecies", 4))
	var actor := PbActor.create(species, Save.lab_deltas())
	if actor.is_empty():
		actor = PbActor.create(1)
	return actor


func _toggle_levels() -> void:
	_max_level = not _max_level
	_reroll_moves()


func _reroll_moves() -> void:
	# Rebuild the actor and (optionally) push every move to the fusion threshold.
	var actor := _actor()
	_moves = PbJson.as_array(actor.get("moves", []))
	if _max_level:
		for i in _moves.size():
			if _moves[i] != null:
				PbJson.as_dict(_moves[i])["level"] = PbFusion.MOVE_MAX_LEVEL
	_status.text = "宝可梦 %s · 招式等级 %s · 目录共 %d 条融合配方（签名/类型/反应/故障）" % [
		String(actor.get("name", "?")),
		"全部 8 级" if _max_level else "1 级（未达融合门槛）",
		_catalogue_size(),
	]
	refresh()


func _catalogue_size() -> int:
	if _catalogue.is_empty():
		_catalogue = PbFusion.all_recipes()
	return _catalogue.size()


func _set_filter(kind: String) -> void:
	_filter = kind
	refresh()


## Chinese gloss for the recipe kind filter (data keys stay English).
func _kind_label(kind: String) -> String:
	var zh := {"all": "全部", "signature": "签名", "reaction": "反应",
		"type": "同属性", "glitch": "故障"}
	return String(zh.get(kind, kind))


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var offers := PbFusion.offers(_moves)
	var shown := 0
	for raw in offers:
		var offer := PbJson.as_dict(raw)
		var recipe := PbJson.as_dict(offer.get("recipe", {}))
		if _filter != "all" and String(recipe.get("kind", "")) != _filter:
			continue
		shown += 1
		var names: Array = PbJson.as_array(offer.get("names", []))
		var b := UI.button("%s  ←  %s + %s  [%s]" % [
			String(recipe.get("name", "?")), String(names[0]) if names.size() > 0 else "?",
			String(names[1]) if names.size() > 1 else "?", String(recipe.get("kind", "?"))],
			func(): _preview_recipe(recipe))
		b.custom_minimum_size = Vector2(320, 34)
		b.disabled = not bool(offer.get("ready", false))
		_list.add_child(b)
		var need: Array = PbJson.as_array(offer.get("need", []))
		if not need.is_empty():
			_list.add_child(UI.dim("   需要：" + ", ".join(need)))
	if shown == 0:
		# Fall back to browsing the whole recovered catalogue.
		_catalogue_size()
		for entry in _catalogue:
			if _filter != "all" and String(entry.get("kind", "")) != _filter:
				continue
			var b2 := UI.button("目录：%s [%s]" % [String(entry.get("name", "?")), String(entry.get("kind", ""))],
				func(): _preview_recipe(entry))
			b2.custom_minimum_size = Vector2(320, 30)
			_list.add_child(b2)
			if _list.get_child_count() > 200:
				break
	_preview_recipe(PbJson.as_dict(PbFusion.by_key("fu-1")))


func _preview_recipe(recipe: Dictionary) -> void:
	for c in _preview.get_children():
		c.queue_free()
	if recipe.is_empty():
		_preview.add_child(UI.dim("无配方"))
		return
	var fused := PbFusion.fused_def(recipe)
	_preview.add_child(UI.label("★ %s" % String(fused.get("name", "?")), 20))
	var types := UI.hbox(6)
	_preview.add_child(types)
	types.add_child(UI.type_chip(String(fused.get("type", ""))))
	if fused.get("type2") != null:
		types.add_child(UI.type_chip(String(fused["type2"])))
	_preview.add_child(UI.dim(String(fused.get("desc", ""))))

	var actor := PbActor.create(int(Save.store.get("starter", 0)) if int(Save.store.get("starter", 0)) > 0 else 1)
	var built := PbDamage.move_instance(fused, PbActor.actor_for_damage(actor), 1)
	var table := UI.grid(2, 3)
	_preview.add_child(table)
	var rows := [
		["原型 arch", String(fused.get("arch", ""))],
		["基础威力 dmg", "%.2f  (fusion 原型 17 × 配方 power %.2f)" % [float(fused.get("dmg", 0)), float(recipe.get("power", 1))]],
		["冷却 cd", "%.2fs（融合下限 0.60s）" % float(built.get("cd", 0))],
		["段数 hits", "%.1f" % float(PbJson.as_dict(fused.get("fusion", {})).get("hits", 1))],
		["单次实际伤害 real", "%.1f" % float(built.get("real", 0))],
		["理论 dps", "%.1f" % float(built.get("dps", 0))],
		["范围 area", "%.2f（融合走 My() 上限 3.4 缩放）" % float(built.get("area", 0))],
		["穿透 pierce", "%d" % int(built.get("pierce", 0))],
		["附加状态", "%s  概率 %.0f%%" % [str(fused.get("status")), float(built.get("statusChance", 0)) * 100.0]],
		["会心 crit", "%.1f%%" % (float(built.get("crit", 0)) * 100.0)],
		["repeats 追加", "是（最多 2 次，第二次 70% 伤害）" if bool(recipe.get("repeats", false)) else "否"],
	]
	for r in rows:
		table.add_child(UI.dim(String(r[0])))
		table.add_child(UI.label(String(r[1]), 14))
	_preview.add_child(HSeparator.new())
	_preview.add_child(UI.dim("配方 key：%s · 素材：%s" % [
		String(recipe.get("key", "")), ", ".join(PbJson.as_array(recipe.get("moves", [])))]))
