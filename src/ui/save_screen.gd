extends Control
## Save manager -- the Godot counterpart of save-ui.js + save-manager.js.
##
## Everything is file-backed under user:// instead of localStorage, and the
## import path keeps the web build's tolerance rules (strip junk around the JSON,
## back up first, reject non-save payloads).


var _summary: Label
var _backups: VBoxContainer
var _input: LineEdit
var _log: Label
var _exported_path: String = ""
var _backup_count := 0
var _pending_reset: Variant = null
var _pending_restore := ""


func _ready() -> void:
	UI.fill(self)
	var scr := UI.screen()
	add_child(scr)
	UI.fill(scr)
	var root := UI.content(scr, 18)

	root.add_child(UI.screen_head(App.ui("Guardar"), "Gestor de guardado", func(): App.back_to_menu()))
	root.add_child(UI.paragraph("Godot 存档位置：user://pb.offline.profile.json（等价于浏览器 localStorage）", 13, PbTheme.ink_muted(), 1))
	_summary = UI.label("", 15)
	root.add_child(_summary)

	var row := UI.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	var actions := UI.vbox(6)
	row.add_child(actions)
	actions.add_child(UI.button(App.ui("Guardar"), func(): _do(_save_now())))
	actions.add_child(UI.button("导出到文件", func(): _do(_export_file())))
	actions.add_child(UI.button("复制存档文本（打印到控制台）", func(): _do(_export_console())))
	actions.add_child(UI.button("自动备份（保留最近 5 份）", func(): _do(_backup())))
	actions.add_child(UI.button(App.ui("Volver"), func(): App.back_to_menu(), false, "ghost"))
	# Danger zone (web save-ui.js groups destructive actions below a red rule).
	actions.add_child(HSeparator.new())
	actions.add_child(UI.button("重置为满解锁存档", func(): _confirm_reset(true), false, "red"))
	actions.add_child(UI.button("重置为空存档", func(): _confirm_reset(false), false, "red"))

	var middle := UI.vbox(6)
	row.add_child(middle)
	middle.add_child(UI.label("从文本导入（粘贴 web 版导出的 JSON）", 15))
	_input = LineEdit.new()
	_input.custom_minimum_size = Vector2(520, 34)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "{\"v\":1,\"profile\":{...}}"
	middle.add_child(_input)
	middle.add_child(UI.button("导入文本", func(): _do(_import_text())))
	middle.add_child(UI.button("从文件导入 (user:// 内最新 pokebonk-save-*.json)", func(): _do(_import_file())))

	var right := UI.vbox(6)
	row.add_child(right)
	right.add_child(UI.label("自动备份列表", 15))
	var sc := UI.scroll()
	sc.custom_minimum_size = Vector2(300, 240)
	right.add_child(sc)
	_backups = UI.vbox(3)
	sc.add_child(_backups)

	_log = UI.dim("")
	root.add_child(_log)
	refresh()
	# save-ui.js nags on entry when it has been a while since the last backup.
	if Save.stale_seconds() > 300.0 or Save.list_backups().is_empty():
		UI.toast(self, "距上次备份已较久，建议先导出或自动备份")


func _do(result: String) -> void:
	_log.text = result
	Audio.sfx("ui")
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		App.back_to_menu()


func _save_now() -> String:
	Save.save()
	return "已写入 %s" % Save._path()


func _export_file() -> String:
	_exported_path = Save.export_to_file()
	return "导出完成：%s" % _exported_path


func _export_console() -> String:
	var text := Save.export_string()
	print(text.substr(0, mini(400, text.length())))
	return "存档文本长度 %d 字符（前 400 字已打印到控制台）" % text.length()


func _backup() -> String:
	var id := Save.auto_backup()
	return "已生成备份 %s" % id if not id.is_empty() else "备份失败（无存档？）"


func _import_text() -> String:
	var res := Save.import_text(_input.text)
	if res == "ok":
		return "导入成功（旧存档已自动备份）"
	return "导入失败：%s" % res


func _import_file() -> String:
	var dir := DirAccess.open("user://")
	if dir == null:
		return "无法读取 user://"
	var candidates: Array = []
	for f in dir.get_files():
		if f.begins_with("pokebonk-save-"):
			candidates.append(f)
	candidates.sort()
	if candidates.is_empty():
		return "没有找到导出的存档文件"
	var text := FileAccess.get_file_as_string("user://%s" % str(candidates[-1]))
	var res := Save.import_text(text)
	return "导入 %s → %s" % [str(candidates[-1]), res]


func _reset(to_full: bool) -> String:
	Save.auto_backup()
	Save.reset(to_full)
	return "已重置为%s存档" % ("满解锁" if to_full else "空白")


## Two-step destructive confirm, mirroring save-ui.js's "再点一次确认" pattern.
func _confirm_reset(to_full: bool) -> void:
	if _pending_reset != null and bool(_pending_reset) == to_full:
		_pending_reset = null
		_do(_reset(to_full))
		return
	_pending_reset = to_full
	Audio.sfx("deny")
	UI.toast(self, "再次点击「%s」以确认重置（会先自动备份）" % (
		"满解锁" if to_full else "空存档"))


func refresh() -> void:
	var s := Save.summary()
	_summary.text = "训练家 %s · 星尘 %d · 邦币 %d · 联盟 %d · 图鉴 %d · 对局记录 %d · 距上次保存 %.0fs" % [
		str(s.get("name", "—")), int(s.get("stardust", 0)), int(s.get("bonk", 0)),
		int(s.get("league", 0)), int(s.get("captured", 0)), int(s.get("runs", 0)),
		Save.stale_seconds()]
	for c in _backups.get_children():
		c.queue_free()
	var backups := Save.list_backups()
	if backups.is_empty():
		_backups.add_child(UI.dim("（暂无备份）"))
	for raw in backups.slice(0, 5):
		var b := PbJson.as_dict(raw)
		var sum := PbJson.as_dict(b.get("summary", {}))
		var label := UI.dim("%s · %s · 星尘 %d" % [str(b.get("time", "?")),
			str(sum.get("name", "?")), int(sum.get("stardust", 0))])
		_backups.add_child(label)
		var bid := str(b.get("id", ""))
		var restore_btn := UI.button("恢复这份", func(): _confirm_restore(bid), false, "blue")
		if _pending_restore == bid:
			restore_btn.text = "再次点击确认恢复"
		_backups.add_child(restore_btn)
	_backup_count = backups.size()


## Two-step confirm before overwriting the live save with a backup.
func _confirm_restore(id: String) -> void:
	if _pending_restore == id:
		_pending_restore = ""
		_do(_restore(id))
		return
	_pending_restore = id
	Audio.sfx("deny")
	UI.toast(self, "再次点击「恢复这份」以确认（当前存档会先自动备份）")
	refresh()


func _restore(id: String) -> String:
	return "已恢复 %s" % id if Save.restore_backup(id) else "恢复失败：%s" % id
