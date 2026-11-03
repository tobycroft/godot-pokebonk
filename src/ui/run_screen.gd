extends Node3D
## The arena: a real-time horde run driven entirely by the ported simulation
## (PbRun/PbActor/PbDamage/PbFusion), rendered with the migrated assets.
##
## Presentation notes: the web game streams a .glb per species; this port uses
## the shipped PMD sheets as billboards (PbVisuals.avatar fallback chain) and
## places the two real .glb props that pokebonk-web does ship, so both asset
## paths are exercised. Camera pitch/distance come from the recovered run class
## defaults (camPitch .45, camDist 9, offset 1506673).

const ARENA_SIZE := 140.0
const ENEMY_POOL := 64

var _run: Dictionary = {}
var _player_node: Node3D
var _camera: Camera3D
var _enemy_nodes: Array[MeshInstance3D] = []
var _orb_nodes: Array[MeshInstance3D] = []
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _stats_label: Label
var _moves_label: Label
var _log_label: Label
var _modal: VBoxContainer
var _modal_box: PanelContainer
var _settle: VBoxContainer
var _settle_box: PanelContainer
var _time := 0.0
var _paused := false
var _trauma := 0.0
var _last_damage_taken := 0.0
var _shake_scale := 1.0


func _ready() -> void:
	_build_world()
	_build_hud()
	_start_run()


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.06, 0.08, 0.12)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.75, 0.8, 0.95)
	settings.ambient_light_energy = 0.55
	env.environment = settings
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_SIZE, ARENA_SIZE)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	var biome := String(Save.store.get("lastBiome", "forest"))
	var ground_tex := "res://assets/env/%s/ground.png" % biome
	if ResourceLoader.exists(ground_tex):
		mat.albedo_texture = load(ground_tex)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		# Godot 4 tiles through uv1_scale (the 3.x u_scale/v_scale pair is gone).
		mat.uv1_scale = Vector3(24.0, 24.0, 24.0)
	else:
		mat.albedo_color = Color(0.2, 0.32, 0.22)
		push_warning("Run: biome texture missing (%s), using flat colour" % ground_tex)
	ground.material_override = mat
	add_child(ground)

	# Real .glb props that ship with pokebonk-web: proves the model pipeline.
	for prop in ["tower_portal", "tower_pillar"]:
		var path := "res://assets/models/%s.glb" % prop
		if ResourceLoader.exists(path):
			var packed = load(path)
			if packed is PackedScene:
				var node: Node = packed.instantiate()
				if node is Node3D:
					(node as Node3D).position = Vector3(-8.0 if prop == "tower_portal" else 9.0, 0.0, -6.0)
					add_child(node)
		else:
			push_warning("Run: prop model missing %s" % path)

	_player_node = Node3D.new()
	add_child(_player_node)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true

	for i in ENEMY_POOL:
		var m := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.4, 1.4)
		var em := StandardMaterial3D.new()
		em.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		em.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.mesh = quad
		m.material_override = em
		m.visible = false
		add_child(m)
		_enemy_nodes.append(m)
	for i in 48:
		var o := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		var om := StandardMaterial3D.new()
		om.albedo_color = Color(0.45, 1.0, 0.55)
		om.emission_enabled = true
		om.emission = Color(0.35, 0.9, 0.45)
		o.mesh = sphere
		o.material_override = om
		o.visible = false
		add_child(o)
		_orb_nodes.append(o)


# ------------------------------------------------------------------ hud
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Control.new()
	hud.name = "Hud"
	UI.fill(hud)
	UI.themify(hud)
	layer.add_child(hud)
	var top := UI.vbox(4)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(16, 12)
	top.custom_minimum_size = Vector2(380, 0)
	hud.add_child(top)
	_stats_label = UI.label("", 16)
	top.add_child(_stats_label)
	_hp_bar = UI.progress("red", 18)
	top.add_child(_hp_bar)
	_xp_bar = UI.progress("blue", 10)
	top.add_child(_xp_bar)
	_moves_label = UI.dim("")
	top.add_child(_moves_label)

	var bottom := UI.vbox(4)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(16, -110)
	bottom.custom_minimum_size = Vector2(600, 100)
	hud.add_child(bottom)
	_log_label = UI.dim("")
	bottom.add_child(_log_label)
	var controls := UI.hbox(6)
	bottom.add_child(controls)
	controls.add_child(UI.button("融合 (F)", func(): _try_fusion()))
	controls.add_child(UI.button("暂停 (P)", func(): _paused = not _paused))
	controls.add_child(UI.button("结束本局", func(): _finish("exit")))

	_modal_box = UI.panel(18)
	_modal_box.set_anchors_preset(Control.PRESET_CENTER)
	_modal_box.visible = false
	hud.add_child(_modal_box)
	_modal = UI.vbox(8)
	_modal_box.add_child(_modal)

	_settle_box = UI.panel(18)
	_settle_box.set_anchors_preset(Control.PRESET_CENTER)
	_settle_box.visible = false
	hud.add_child(_settle_box)
	_settle = UI.vbox(8)
	_settle_box.add_child(_settle)


# ------------------------------------------------------------------ run flow
func _start_run() -> void:
	var settings := PbJson.as_dict(Save.store.get("settings", {}))
	Audio.apply_profile_settings(settings)
	var start := Save.handle("POST", "/runs/start", {}, {})
	var species := App.selected_species
	if species <= 0:
		species = 4
	_run = PbRun.create(species, String(Save.store.get("lastBiome", "forest")),
		int(start.get("seed", 0)), Save.lab_deltas())
	if _run.is_empty():
		push_error("Run: could not start (unknown species %d)" % species)
		return
	_run["run_id"] = String(start.get("id", "run-local"))
	_run["aimMode"] = String(settings.get("aimMode", "auto"))
	_shake_scale = clampf(float(settings.get("shake", 1.0)), 0.0, 1.0)
	_time = 0.0
	_last_damage_taken = 0.0
	_trauma = 0.0
	_settle_box.visible = false
	_modal_box.visible = false
	Audio.play_music("menu")
	Audio.play_cry(species)
	_log(_message_tail())


func _process(delta: float) -> void:
	if _run.is_empty():
		return
	_time += delta
	var dt := minf(delta, 1.0 / 15.0)
	if String(_run.get("state", "play")) == "over":
		_render(dt)
		_show_settle_once()
		return
	if _paused or String(_run.get("state", "play")) == "modal":
		_render(dt)
		_update_modal()
		return
	_move_input(dt)
	PbRun.tick(_run, dt)
	_render(dt)
	if String(_run.get("state", "play")) == "modal":
		Audio.sfx("level")
	_update_hud()


func _move_input(dt: float) -> void:
	var player: Dictionary = _run["player"]
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		var speed := float(PbJson.as_dict(player.get("stats", {})).get("moveSpeed", 1.0)) * 6.0
		dir = dir.normalized()
		player["x"] = float(player.get("x", 0.0)) + dir.x * speed * dt
		player["z"] = float(player.get("z", 0.0)) + dir.y * speed * dt
		player["facing"] = 2 if dir.x > 0.0 else 6
	var half := ARENA_SIZE * 0.5 - 2.0
	player["x"] = clampf(float(player.get("x", 0.0)), -half, half)
	player["z"] = clampf(float(player.get("z", 0.0)), -half, half)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F:
				_try_fusion()
			KEY_P:
				_paused = not _paused
			KEY_ESCAPE:
				if String(_run.get("state", "")) == "over":
					App.back_to_menu()
				else:
					_finish("exit")


# ------------------------------------------------------------------ render
func _render(dt: float) -> void:
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	_player_node.position = Vector3(px, 0.0, pz)
	if _player_node.get_child_count() == 0:
		_player_node.add_child(PbVisuals.avatar(int(player.get("species_id", 1))))
	else:
		# Billboard frames: swap the texture using the PMD sheet timings.
		var node = _player_node.get_child(0)
		if node is MeshInstance3D:
			var anim := "walk" if absf(player.get("x", 0.0) - px) > 0.0 else "idle"
			var tex := PbVisuals.frame_texture(int(player.get("species_id", 1)),
				String(anim), _time, int(player.get("facing", 2)))
			var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null and tex != null:
				mat.albedo_texture = tex
	var pitch := float(PbData.const_of("camera.pitch", 0.45))
	var dist := float(PbData.const_of("camera.dist", 9.0))
	# Hit feedback: the run class carries a `trauma` value that shake() adds to.
	var taken_now := float(PbJson.as_dict(_run.get("stats", {})).get("damageTaken", 0.0))
	if taken_now > _last_damage_taken + 0.001:
		_trauma = minf(1.0, _trauma + 0.3)
		_last_damage_taken = taken_now
		Audio.sfx("hit")
	_trauma = maxf(0.0, _trauma - dt * 2.5)
	var shake_amount := _trauma * _trauma * 0.6 * _shake_scale
	var shake_offset := Vector3(PbRng.randf_range(-shake_amount, shake_amount),
		PbRng.randf_range(-shake_amount, shake_amount), 0.0)
	_camera.position = Vector3(px, sin(pitch) * dist, pz + cos(pitch) * dist) + shake_offset
	_camera.look_at(Vector3(px + shake_offset.x * 0.3, 1.0, pz + shake_offset.z * 0.3), Vector3.UP)

	var pool: Dictionary = _run.get("enemies", {})
	var used := 0
	for entry in PbEnemies.live_indices(pool):
		if used >= ENEMY_POOL:
			break
		var i := int(entry)
		if not PbEnemies.is_alive(pool, i):
			continue
		var node := _enemy_nodes[used]
		used += 1
		node.visible = true
		var scale := float(PbEnemies.get_field(pool, "scale", i))
		node.position = Vector3(float(PbEnemies.get_field(pool, "x", i)), scale * 0.55,
			float(PbEnemies.get_field(pool, "z", i)))
		(node.mesh as QuadMesh).size = Vector2(1.4, 1.4) * scale
		var species := int(PbEnemies.get_field(pool, "species", i))
		var mat := node.material_override as StandardMaterial3D
		var tex := PbVisuals.frame_texture(species, "walk", _time + float(i) * 0.11, 1)
		if mat != null and tex != null:
			mat.albedo_texture = tex
			var hp_ratio := 1.0
			var maxhp := float(PbEnemies.get_field(pool, "maxHp", i))
			if maxhp > 0.0:
				hp_ratio = clampf(float(PbEnemies.get_field(pool, "hp", i)) / maxhp, 0.0, 1.0)
			mat.albedo_color = Color(1.0, 0.35 + 0.65 * hp_ratio, 0.35 + 0.65 * hp_ratio)
	for i in range(used, ENEMY_POOL):
		_enemy_nodes[i].visible = false

	var orbs: Array = PbJson.as_array(_run.get("orbs", []))
	var orb_used := 0
	for raw in orbs:
		if orb_used >= _orb_nodes.size():
			break
		var orb := PbJson.as_dict(raw)
		var node2 := _orb_nodes[orb_used]
		orb_used += 1
		node2.visible = true
		node2.position = Vector3(float(orb["x"]), 0.4, float(orb["z"]))
	for i in range(orb_used, _orb_nodes.size()):
		_orb_nodes[i].visible = false


func _update_hud() -> void:
	var player: Dictionary = _run["player"]
	var stats := PbJson.as_dict(player.get("stats", {}))
	var run_stats: Dictionary = _run["stats"]
	var first_move := ""
	for raw in PbJson.as_array(player.get("moves", [])):
		if raw != null:
			var inst := PbJson.as_dict(raw)
			var built := PbJson.as_dict(inst.get("computed", {}))
			first_move = "%s cd %.2fs dps %.0f" % [String(PbJson.as_dict(inst.get("def", {})).get("name", "?")),
				float(built.get("cd", 0)), float(built.get("dps", 0))]
			break
	_stats_label.text = "第 %d/%d 阶段  %.0fs  击杀 %d  伤害 %.0f  金币 %.0f  闪避 %d  暴击 %d\n%s" % [
		int(_run["stage"]), PbRun.STAGES, float(_run["time"]),
		int(run_stats.get("kills", 0)), float(run_stats.get("damage", 0.0)),
		float(_run.get("gold", 0)), int(run_stats.get("dodges", 0)), int(run_stats.get("crits", 0)),
		String(player.get("name", "?")),
	]
	_hp_bar.max_value = maxf(1.0, float(player.get("maxHp", 100)))
	_hp_bar.value = float(player.get("hp", 0))
	_xp_bar.max_value = maxf(1.0, float(player.get("xpNext", 1)))
	_xp_bar.value = float(player.get("xp", 0))
	_moves_label.text = "Lv%d  HP %.0f/%.0f  x%.2f dmg  护甲 %.1f(减伤 %.0f%%)  %s" % [
		int(player.get("level", 1)), float(player.get("hp", 0)), float(player.get("maxHp", 0)),
		float(stats.get("damage", 1)), float(stats.get("armor", 0)),
		PbStats.armor_mitigation(float(stats.get("armor", 0))) * 100.0, first_move]


func _message_tail() -> String:
	var msgs: Array = PbJson.as_array(_run.get("messages", []))
	return "\n".join(msgs.slice(-4)) if not msgs.is_empty() else "准备战斗…"


func _log(text: String) -> void:
	_log_label.text = text


# ------------------------------------------------------------------ modals
func _update_modal() -> void:
	if String(_run.get("state", "play")) != "modal":
		_modal_box.visible = false
		return
	if _modal.get_child_count() > 0 and String(_modal.get_meta("state", "")) == "offers:%d" % int(_run["pendingLevels"]):
		_modal_box.visible = true
		return
	_modal_box.visible = true
	_modal_box.position = Vector2(-260, -180)
	for c in _modal.get_children():
		c.queue_free()
	_modal.add_child(UI.label("升级！选择强化 (1-3)", 20))
	var offers: Array = PbJson.as_array(_run.get("offers", []))
	if offers.is_empty():
		_modal.add_child(UI.dim("（没有可选强化，按任意继续）"))
		_modal.add_child(UI.button("继续", func(): _resume_without_offer()))
	for i in offers.size():
		var card := PbJson.as_dict(offers[i])
		var mods := UI.hbox(4)
		var label_text := "%s  ·  %s" % [String(card.get("kind", "?")), String(card.get("label", ""))]
		var b := UI.button(label_text, func(): _pick(i))
		b.custom_minimum_size = Vector2(420, 40)
		_modal.add_child(b)
		_modal.add_child(mods)
		for raw in PbJson.as_array(card.get("mods", [])):
			var mod := PbJson.as_dict(raw)
			mods.add_child(UI.dim("[%s %s]" % [String(mod.get("stat", "")),
				"add %.2f" % float(mod.get("add", 0)) if mod.has("add") else "mul %.2f" % float(mod.get("mul", 1))]))
	var controls := UI.hbox(6)
	_modal.add_child(controls)
	controls.add_child(UI.button("重掷 %d" % int(_run["rerolls"]), func(): _act_reroll()))
	controls.add_child(UI.button("跳过 %d" % int(_run["skips"]), func(): _act_skip()))
	controls.add_child(UI.button("禁用 %d" % int(_run["banishes"]), func(): _act_banish()))
	_modal.set_meta("state", "offers:%d" % int(_run["pendingLevels"]))


func _pick(index: int) -> void:
	if PbRun.choose_offer(_run, index):
		Audio.sfx("ui")
	_modal.set_meta("state", "")


func _resume_without_offer() -> void:
	_run["pendingLevels"] = 0
	_run["offers"] = []
	_run["state"] = "play"
	_modal.set_meta("state", "")


func _act_reroll() -> void:
	PbRun.reroll(_run)
	_modal.set_meta("state", "")


func _act_skip() -> void:
	PbRun.skip(_run)
	_modal.set_meta("state", "")


func _act_banish() -> void:
	PbRun.banish(_run, 0)
	_modal.set_meta("state", "")


# ------------------------------------------------------------------ fusion
func _try_fusion() -> void:
	var offers := PbRun.fusion_offers(_run)
	var ready := []
	for raw in offers:
		var offer := PbJson.as_dict(raw)
		if bool(offer.get("ready", false)):
			ready.append(offer)
	if ready.is_empty():
		Audio.sfx("deny")
		_log("尚不可融合：需要两个招式都升到 8 级（当前可融合组合 %d）" % offers.size())
		return
	var inst := PbRun.fuse(_run, PbJson.as_dict(ready[0]))
	if not inst.is_empty():
		Audio.sfx("fusion")
		_log("融合成功：%s（伤害 %.0f，段数 %.1f）" % [
			String(PbJson.as_dict(inst.get("def", {})).get("name", "?")),
			float(PbJson.as_dict(inst.get("def", {})).get("dmg", 0)),
			float(PbJson.as_dict(inst.get("def", {}).get("fusion", {})).get("hits", 1))])


# ------------------------------------------------------------------ settle
func _finish(how: String) -> void:
	if String(_run.get("state", "")) == "settled":
		return
	var result := PbRun.finish(_run, how)
	PbRun.result(_run)
	_run["state"] = "settled"
	var res := Save.handle("POST", "/runs/%s/finish" % String(_run.get("run_id", "local")), {}, {"result": result})
	App.last_result = result
	App.last_settle = res
	Audio.sfx("boss")
	_show_settle(result, res)


func _show_settle_once() -> void:
	if _settle_box.visible:
		return
	_finish(String(_run.get("endHow", "exit")))


func _show_settle(result: Dictionary, res: Dictionary) -> void:
	_modal_box.visible = false
	_settle_box.visible = true
	_settle_box.position = Vector2(-260, -200)
	for c in _settle.get_children():
		c.queue_free()
	_settle.add_child(UI.title("本局结算"))
	var reward := PbJson.as_dict(res.get("reward", {}))
	var record := PbJson.as_dict(res.get("record", {}))
	var lines := [
		"结果：%s（%s）" % ["胜利" if bool(result.get("victory", false)) else "失败", String(result.get("endHow", ""))],
		"阶段 %d · 时长 %.0fs · 击杀 %d · 伤害 %.0f · 等级 %d" % [
			int(result.get("stage", 0)), float(result.get("time", 0)), int(result.get("kills", 0)),
			float(result.get("damage", 0)), int(result.get("level", 0))],
		"融合 %d 次：%s" % [PbJson.as_array(result.get("fusions", [])).size(),
			", ".join(PbJson.as_array(result.get("fusions", [])))],
		"星尘 +%d（余额 %d）· 记录 id %s" % [int(reward.get("stardust", 0)),
			int(Save.store.get("stardust", 0)), String(record.get("id", "?"))],
	]
	for line in lines:
		_settle.add_child(UI.label(line, 15))
	var row := UI.hbox(8)
	_settle.add_child(row)
	row.add_child(UI.button("再来一局", func(): _start_run()))
	row.add_child(UI.button("返回主菜单", func(): App.back_to_menu()))
