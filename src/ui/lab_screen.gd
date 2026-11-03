extends Control
## Research lab: the 22 permanent upgrades from api-core.js's LAB table.
##
## Buying goes through the ported route POST /lab/<id>/buy, so cost (10*(rank+1)),
## MAX / NO_STARDUST errors and the stardust spend all behave like the web build.


var _stardust: Label
var _rows := {}


func _ready() -> void:
	UI.fill(self)
	var scr := UI.screen()
	add_child(scr)
	UI.fill(scr)
	var root := UI.content(scr, 18)

	root.add_child(UI.title("研究所 / Laboratorio"))
	root.add_child(UI.paragraph("永久强化，每局生效。花费 = 10 ×(当前等级+1)，与 web 版 api-core 一致。", 13, PbTheme.ink_muted(), 1))
	_stardust = UI.label("", 18, PbTheme.accent_color("blue", "cd"))
	_stardust.add_theme_font_override("font", PbTheme.font("title"))
	root.add_child(_stardust)

	var sc := UI.scroll()
	root.add_child(sc)
	var grid := UI.grid(3, 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for row in Save.lab_table():
		var entry := PbJson.as_dict(row)
		grid.add_child(_card(String(entry["id"]), int(entry["max"])))

	var footer := UI.hbox(8)
	root.add_child(footer)
	footer.add_child(UI.button("返回 / Volver", func(): App.back_to_menu()))
	footer.add_child(UI.dim("左滑可查看全部 22 项强化；数据来自 api-core.js 的 LAB 表。"))
	refresh()


func _card(id: String, max_rank: int) -> Control:
	var panel := UI.panel(10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(4)
	panel.add_child(v)
	v.add_child(UI.label(_name(id), 16))
	var rank := UI.dim("等级 0/%d" % max_rank)
	v.add_child(rank)
	var cost := UI.dim("花费 10")
	v.add_child(cost)
	var buy := UI.button("升级", func(): _buy(id))
	buy.size_flags_horizontal = Control.SIZE_FILL
	v.add_child(buy)
	_rows[id] = {"max": max_rank, "rank": rank, "cost": cost, "buy": buy}
	return panel


func _buy(id: String) -> void:
	var res := Save.lab_buy(id)
	if not bool(res.get("ok", false)):
		Audio.sfx("deny")
		match String(res.get("error", "")):
			"MAX":
				UI.toast(self, "%s 已满级" % id)
			"NO_STARDUST":
				UI.toast(self, "星尘不足")
	else:
		Audio.sfx("level")
	refresh()


func refresh() -> void:
	_stardust.text = "星尘 / Polvo estelar: %d    邦币 / Bonk: %d" % [
		int(Save.store.get("stardust", 0)), int(Save.store.get("bonk", 0))]
	var wallet := int(Save.store.get("stardust", 0))
	for id in _rows.keys():
		var entry: Dictionary = _rows[id]
		var rank := Save.lab(id)
		var max_rank := int(entry["max"])
		(entry["rank"] as Label).text = "等级 %d/%d" % [rank, max_rank]
		var cost := 10 * (rank + 1)
		(entry["cost"] as Label).text = "已满级" if rank >= max_rank else "花费 %d 星尘" % cost
		(entry["buy"] as Button).disabled = rank >= max_rank or wallet < cost


func _name(id: String) -> String:
	var names := {
		"slot-move": "第 4 个招式槽", "slot-vit": "维生素槽 +1",
		"reroll": "重掷选项", "skip": "跳过选项", "banish": "禁用选项",
		"dmg": "伤害", "hp": "生命", "spd": "移动速度", "xp": "经验获取",
		"gold": "金币", "luck": "幸运", "magnet": "拾取范围", "regen": "回复",
		"armor": "护甲", "revive": "初始复活", "research": "研究加成",
		"party": "同伴槽", "area": "范围", "atkspd": "攻击速度", "ult": "终极技",
		"bag": "背包",
	}
	return "%s  (%s)" % [String(names.get(id, id)), id]
