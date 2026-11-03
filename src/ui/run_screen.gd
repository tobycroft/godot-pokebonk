extends Node3D
## The arena: a real-time horde run driven entirely by the ported simulation
## (PbRun/PbActor/PbDamage/PbFusion), rendered with the migrated assets.
##
## Presentation notes: the web game streams a .glb per species; this port uses
## the shipped PMD sheets as billboards (PbVisuals.avatar fallback chain) and
## places the two real .glb props that pokebonk-web does ship, so both asset
## paths are exercised. Camera pitch/distance come from the recovered run class
## defaults (camPitch .45, camDist 9, offset 1506673).
##
## The HUD is the web DOM rebuilt node-for-node (RunHud, diff-list #1); the
## level-up modal uses the real .card.offer cards (diff-list #2) with the
## reroll/skip/banish flow of showLevelUp() (bundle @2172425).

const ARENA_SIZE := 140.0
const ENEMY_POOL := 64

var _run: Dictionary = {}
var _player_node: Node3D
var _camera: Camera3D
var _terrain: PbTerrain
var _view: PbWorldView
var _sun: DirectionalLight3D
var _enemy_nodes: Array[MeshInstance3D] = []
var _orb_nodes: Array[MeshInstance3D] = []
var _hud: RunHud
var _layer: CanvasLayer
var _modal_scrim: PanelContainer
var _modal_cards: HBoxContainer
var _modal_actions: HBoxContainer
var _modal_mini: HBoxContainer
var _modal_state := ""
var _banish_mode := false
var _banish_pick := -1
var _settle_scrim: PanelContainer
var _settle_body: VBoxContainer
var _time := 0.0
var _paused := false
var _trauma := 0.0
var _last_damage_taken := 0.0
var _shake_scale := 1.0
var _msg_seen := 0
var _stage_seen := 1
var _boss_seen := false


func _ready() -> void:
	_build_world()
	_build_hud()
	_start_run()
	_build_terrain()
	# QA hook (like --pb-shot): render the level-up modal immediately for screenshots.
	if "--pb-offer-demo" in OS.get_cmdline_user_args():
		_run["pendingLevels"] = 1
		PbRun.open_offers(_run)
		_update_modal()


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
	_sun = sun
	# The height field, props and water arrive once the run's seed/biome are known.
	_view = PbWorldView.new()
	_view.name = "World"
	add_child(_view)

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
	_layer = CanvasLayer.new()
	add_child(_layer)
	_hud = RunHud.new()
	_hud.name = "RunHud"
	_layer.add_child(_hud)
	UI.fill(_hud)

	# .modal shells (CSS .modal: radial scrim, h1 plate, centred column).
	var level := UI.modal_shell("升级！选择强化")
	_modal_scrim = level["scrim"]
	var body: VBoxContainer = level["body"]
	_modal_scrim.visible = false
	_layer.add_child(_modal_scrim)
	UI.fill(_modal_scrim)
	body.add_theme_constant_override("separation", 16)
	_modal_cards = UI.hbox(16)
	_modal_cards.name = "Cards"
	_modal_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(_modal_cards)
	_modal_actions = UI.hbox(12)
	_modal_actions.name = "Actions"
	body.add_child(_modal_actions)
	_modal_mini = UI.hbox(6)
	_modal_mini.name = "BuildMini"
	body.add_child(_modal_mini)

	var settle := UI.modal_shell("本局结算", true)
	_settle_scrim = settle["scrim"]
	_settle_body = settle["body"]
	_settle_scrim.visible = false
	_layer.add_child(_settle_scrim)
	UI.fill(_settle_scrim)

	var pause := UI.modal_shell("已暂停", true)
	var pause_scrim: PanelContainer = pause["scrim"]
	var pause_body: VBoxContainer = pause["body"]
	var prow := UI.hbox(8)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(UI.button("继续", func(): _toggle_pause()))
	prow.add_child(UI.button("结束本局", func():
		_toggle_pause()
		_finish("exit"), false, "red"))
	pause_body.add_child(prow)
	pause_scrim.visible = false
	pause_scrim.set_meta("is_pause", true)
	_layer.add_child(pause_scrim)
	UI.fill(pause_scrim)


func _toggle_pause() -> void:
	_paused = not _paused
	for c in _layer.get_children():
		if c.get_meta("is_pause", false) == true:
			c.visible = _paused
	Audio.sfx("ui")


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
	_msg_seen = 0
	_stage_seen = int(_run.get("stage", 1))
	_boss_seen = false
	_modal_state = ""
	_banish_mode = false
	_banish_pick = -1
	_settle_scrim.visible = false
	_modal_scrim.visible = false
	_hud.build(_run)
	Audio.play_music("menu")
	Audio.play_cry(species)


## Build the arena from the run's own seed + biome, so the same seed walks the same map as
## the web client (PbTerrain is asserted against the shipped generator, see tools/terrain_reference.mjs).
func _build_terrain() -> void:
	var biome_id := String(_run.get("biome", "forest"))
	var seed_value := int(_run.get("seed", 0))
	var biome_dict := PbData.biome(biome_id)
	if biome_dict.is_empty():
		push_warning("Run: unknown biome %s, falling back to a flat arena" % biome_id)
		return
	var started := Time.get_ticks_msec()
	_terrain = PbTerrain.create(biome_dict, PbData.world_pack(biome_id), seed_value)
	var palette_all := PbData.world_palettes()
	var palette := PbJson.as_dict(PbJson.as_dict(palette_all.get("by_pack")).get(biome_id))
	_view.setup(_terrain, biome_dict, PbData.world_pack(biome_id), palette, PbData.world_fx())
	_view.place_models()
	# Lights and environment follow the biome's own look (sun colour/intensity + fog).
	var light := PbJson.as_float(biome_dict.get("light"), 1.0)
	_sun.light_energy = clampf(0.7 * light, 0.3, 1.6)
	_sun.light_color = PbWorldView.color_from_int(int(PbJson.as_int(biome_dict.get("sun"), 16773590)))
	print("Run: terrain %s seed=%d in %d ms (res=%d, props=%d)" % [
		biome_id, seed_value, Time.get_ticks_msec() - started, _terrain.res, _terrain.props.size()])


## Height of the walkable surface at (x, z): terrain, or the water/ice above it.
func _ground_y(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	return _terrain.surface(x, z)


func _process(delta: float) -> void:
	if _run.is_empty():
		return
	_time += delta
	var dt := minf(delta, 1.0 / 15.0)
	if String(_run.get("state", "play")) == "over":
		_render(dt)
		_hud.sync(_run, dt)
		_show_settle_once()
		return
	if _paused:
		_render(dt)
		return
	if String(_run.get("state", "play")) == "modal":
		_render(dt)
		_update_modal()
		return
	_move_input(dt)
	PbRun.tick(_run, dt)
	_render(dt)
	_hud.sync(_run, dt)
	_pump_events()
	if String(_run.get("state", "play")) == "modal":
		Audio.sfx("level")


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
		var nx := float(player.get("x", 0.0)) + dir.x * speed * dt
		var nz := float(player.get("z", 0.0)) + dir.y * speed * dt
		# Prop colliders block the way: the same cylinder test the reference runs against its
		# collider grid. When a diagonal move hits, slide along the axis that is still free.
		if _terrain == null:
			player["x"] = nx
			player["z"] = nz
		else:
			var cx := float(player.get("x", 0.0))
			var cz := float(player.get("z", 0.0))
			if not _terrain.hit_prop(nx, nz, _ground_y(nx, nz) + 0.6, 0.45):
				player["x"] = nx
				player["z"] = nz
			elif not _terrain.hit_prop(nx, cz, _ground_y(nx, cz) + 0.6, 0.45):
				player["x"] = nx
			elif not _terrain.hit_prop(cx, nz, _ground_y(cx, nz) + 0.6, 0.45):
				player["z"] = nz
		player["facing"] = 2 if dir.x > 0.0 else 6
	var lim := _terrain.walk_lim() if _terrain != null else ARENA_SIZE * 0.5 - 2.0
	player["x"] = clampf(float(player.get("x", 0.0)), -lim, lim)
	player["z"] = clampf(float(player.get("z", 0.0)), -lim, lim)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var modal := String(_run.get("state", "")) == "modal" and _modal_scrim.visible
	match event.keycode:
		KEY_F:
			if not modal and not _paused:
				_try_fusion()
		KEY_P:
			if String(_run.get("state", "play")) != "over":
				_toggle_pause()
		KEY_ESCAPE:
			if String(_run.get("state", "")) == "over":
				App.back_to_menu()
			elif modal:
				pass # the web blocks dismissal mid-choice
			else:
				_toggle_pause()
		KEY_1, KEY_KP_1:
			if modal:
				_offer_key(0)
		KEY_2, KEY_KP_2:
			if modal:
				_offer_key(1)
		KEY_3, KEY_KP_3:
			if modal:
				_offer_key(2)


# ------------------------------------------------------------------ events
## Route new PbRun messages the way the web routes them: stage-ups and boss
## spawns become banners (.banner), everything else a toast (.toast).
func _pump_events() -> void:
	var msgs: Array = PbJson.as_array(_run.get("messages", []))
	while _msg_seen < msgs.size():
		var text := String(msgs[_msg_seen])
		_msg_seen += 1
		if text.begins_with("stage"):
			var n := int(text.get_slice(" ", 1))
			_hud.show_banner("第 %d 阶段" % n, "击杀首领才能进入下一阶段", "#ff5a5f")
			Audio.sfx("level")
		elif text.begins_with("boss!"):
			_hud.show_banner("首领出现了！", text.trim_prefix("boss!"), "#e82a5a", true)
			Audio.sfx("boss")
		elif text.begins_with("fused"):
			_hud.show_banner("融合成功！", text.trim_prefix("fused "), "#8a5cff")
		else:
			_hud.notify(text)
	var stage := int(_run.get("stage", 1))
	if stage != _stage_seen:
		_stage_seen = stage
	if bool(_run.get("bossSpawned", false)) and not _boss_seen:
		_boss_seen = true


# ------------------------------------------------------------------ render
func _render(dt: float) -> void:
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var py := _ground_y(px, pz)
	_player_node.position = Vector3(px, py, pz)
	if _view != null:
		_view.tick(dt, Vector3(px, py, pz), _camera)
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
	# Same rig as the reference (pitch .45, dist 9), riding the height field.
	_camera.position = Vector3(px, py + sin(pitch) * dist, pz + cos(pitch) * dist) + shake_offset
	_camera.look_at(Vector3(px + shake_offset.x * 0.3, py + 1.0, pz + shake_offset.z * 0.3), Vector3.UP)

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
		var ex := float(PbEnemies.get_field(pool, "x", i))
		var ez := float(PbEnemies.get_field(pool, "z", i))
		# Enemies stand on the height field, not on a flat plane.
		node.position = Vector3(ex, _ground_y(ex, ez) + scale * 0.55, ez)
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
		node2.position = Vector3(float(orb["x"]), _ground_y(float(orb["x"]), float(orb["z"])) + 0.4, float(orb["z"]))
	for i in range(orb_used, _orb_nodes.size()):
		_orb_nodes[i].visible = false


# ------------------------------------------------------------------ modals
## showLevelUp() parity (bundle @2173200): h1 + .cards of .card.offer + the
## reroll/skip/banish actions + buildMini current-move row.
func _update_modal() -> void:
	if String(_run.get("state", "play")) != "modal":
		_modal_scrim.visible = false
		return
	var token := "offers:%d" % int(_run.get("pendingLevels", 0))
	if _modal_state == token:
		_modal_scrim.visible = true
		return
	_modal_state = token
	_modal_scrim.visible = true
	for c in _modal_cards.get_children():
		c.queue_free()
	for c in _modal_actions.get_children():
		c.queue_free()
	for c in _modal_mini.get_children():
		c.queue_free()
	var offers: Array = PbJson.as_array(_run.get("offers", []))
	for i in offers.size():
		var card := PbJson.as_dict(offers[i])
		var data := _offer_card_data(card)
		_modal_cards.add_child(UI.card_offer(data, func(): _offer_key(i), i))
	# .actions: btn blue/ghost/red small with counts + kbd hints, disabled at 0.
	var reroll := UI.small_button("刷新 (%d)" % int(_run.get("rerolls", 0)), _act_reroll, "blue")
	reroll.disabled = int(_run.get("rerolls", 0)) <= 0
	reroll.add_child(_action_icon("reroll"))
	_modal_actions.add_child(reroll)
	var skip := UI.small_button("跳过 (%d)" % int(_run.get("skips", 0)), _act_skip, "ghost")
	skip.disabled = int(_run.get("skips", 0)) <= 0
	skip.add_child(_action_icon("skip"))
	_modal_actions.add_child(skip)
	var banish := UI.small_button("取消" if _banish_mode else "放逐 (%d)" % int(_run.get("banishes", 0)),
		_act_banish_toggle, "red" if not _banish_mode else "ghost")
	if not _banish_mode:
		banish.disabled = int(_run.get("banishes", 0)) <= 0
	_modal_actions.add_child(banish)
	# buildMini: current moves as .ult-row style chips.
	var player: Dictionary = _run.get("player", {})
	for raw in PbJson.as_array(player.get("moves", [])):
		if raw == null:
			continue
		var inst := PbJson.as_dict(raw)
		var def := PbJson.as_dict(inst.get("def", {}))
		if def.is_empty():
			continue
		var chip := UI.chip("%s Lv%d" % [String(def.get("name", "?")), int(inst.get("level", 1))],
			PbTheme.type_color(String(def.get("type", "normal"))))
		_modal_mini.add_child(chip)
	if _banish_mode:
		# CSS .cards.banning: hue-rotate the row, outline the picked card red.
		_modal_cards.modulate = Color(1.15, 0.9, 0.9)
		_hud.notify("选择要放逐的卡：再点一次同一张确认")
	else:
		_modal_cards.modulate = Color.WHITE
	Audio.sfx("level")


func _action_icon(name: String) -> Control:
	return UI.icon_rect(name, 18)


## .card.offer payload from a PbCards card (structure per offerCard(); amounts
## untouched). Rarity mapping is estimated -- see PORT_STATUS.
func _offer_card_data(card: Dictionary) -> Dictionary:
	var kind := String(card.get("kind", "stat"))
	var mods: Array = PbJson.as_array(card.get("mods", []))
	var label_text := String(card.get("label", ""))
	var out := {"lines": [], "mods": mods}
	var rc: Color
	var rar := 0
	match kind:
		"new_move":
			var def := PbMoves.resolve(String(card.get("move_key", "")))
			var type_name := String(def.get("type", "normal"))
			rc = PbTheme.type_color(type_name)
			out["rar_text"] = "招式"
			out["kind_text"] = "新"
			out["title"] = String(def.get("name", "?"))
			out["sub"] = "%s · %s" % ["物理" if String(def.get("cls", "physical")) == "physical" else "特殊",
				String(def.get("arch", ""))]
			out["lines"] = [String(def.get("desc", ""))]
			out["icon_name"] = type_name if ResourceLoader.exists("res://assets/ui/icons/%s.png" % type_name) else "poke-ball"
			rar = mini(4, int(roundf(float(def.get("dmg", 10.0)) / 12.0)))
		"move_upgrade":
			var def2 := _move_def_by_key(String(card.get("move_key", "")))
			rc = PbTheme.rarity_color(rar)
			out["rar_text"] = "强化"
			out["kind_text"] = "升级"
			out["title"] = String(def2.get("name", card.get("move_key", "?")))
			out["sub"] = label_text
			out["lines"] = [_mod_line(PbJson.as_dict(mods[0])) if not mods.is_empty() else label_text]
			out["icon_name"] = String(def2.get("type", "")) if ResourceLoader.exists("res://assets/ui/icons/%s.png" % String(def2.get("type", ""))) else ""
		"type":
			rc = PbTheme.type_color(String(card.get("type", "normal")))
			out["rar_text"] = "属性"
			out["kind_text"] = "强化"
			out["title"] = label_text
			out["sub"] = "%s 属性加成" % App.t("types", String(card.get("type", "")), String(card.get("type", "")))
			for raw in mods:
				out["lines"].append(_mod_line(PbJson.as_dict(raw)))
			out["icon_name"] = String(card.get("type", "")) if ResourceLoader.exists("res://assets/ui/icons/%s.png" % String(card.get("type", ""))) else ""
		_:
			var mod0 := PbJson.as_dict(mods[0]) if not mods.is_empty() else {}
			# estimated magnitude -> rarity band (0..2), flagged as ours
			var mag := absf(float(mod0.get("mul", 0)) - 1.0) * 100.0 if mod0.has("mul") else absf(float(mod0.get("add", 0.0))) * 100.0
			rar = 0 if mag < 10.0 else (1 if mag < 18.0 else 2)
			rc = PbTheme.rarity_color(rar)
			out["rar_text"] = _rar_name(rar)
			out["kind_text"] = "强化"
			out["title"] = label_text
			out["sub"] = String(card.get("stat", ""))
			for raw in mods:
				out["lines"].append(_mod_line(PbJson.as_dict(raw)))
	out["rc"] = rc
	out["shine"] = rar >= 2
	out["key"] = ""
	return out


func _rar_name(rar: int) -> String:
	var zh := ["常见", "较少", "稀有", "史诗", "传说"]
	return String(zh[clampi(rar, 0, zh.size() - 1)])


func _mod_line(mod: Dictionary) -> String:
	if mod.has("add"):
		var v := float(mod["add"])
		return "%s +%s" % [String(mod.get("stat", "?")), ("%d%%" % int(roundf(v * 100.0)) if absf(v) < 1.0 else str(v))]
	return "%s ×%.2f" % [String(mod.get("stat", "?")), float(mod.get("mul", 1.0))]


func _move_def_by_key(key: String) -> Dictionary:
	var player: Dictionary = _run.get("player", {})
	for raw in PbJson.as_array(player.get("moves", [])):
		if raw == null:
			continue
		var def := PbJson.as_dict(PbJson.as_dict(raw).get("def", {}))
		if String(def.get("key", "")) == key:
			return def
	return PbMoves.resolve(key)


## Hotkey/click path, mirroring the web's two-step banish confirm.
func _offer_key(index: int) -> void:
	var offers: Array = PbJson.as_array(_run.get("offers", []))
	if index < 0 or index >= offers.size():
		return
	if _banish_mode:
		if _banish_pick == index:
			_do_banish(index)
		else:
			_banish_pick = index
			_outline_picked(index)
			_hud.notify("再按一次确认放逐「%s」" % String(PbJson.as_dict(offers[index]).get("label", "?")))
			Audio.sfx("ui")
		return
	if PbRun.choose_offer(_run, index):
		Audio.sfx("ui")
		_modal_state = ""
		_banish_mode = false
		_banish_pick = -1


func _outline_picked(index: int) -> void:
	for i in _modal_cards.get_child_count():
		var card := _modal_cards.get_child(i) as PanelContainer
		var rc: Color = card.get_meta("rc", PbTheme.rarity_color(0))
		var base := PbTheme.stylebox(".card", {"rc": "#" + rc.to_html(false)})
		if i == index:
			# CSS .card offer banish outline: 4px solid #ff4a4a.
			base.set_border_width_all(4)
			base.border_color = PbTheme.css_color("#ff4a4a", Color("#ff4a4a"))
		card.add_theme_stylebox_override("panel", base)


func _act_reroll() -> void:
	if int(_run.get("rerolls", 0)) <= 0:
		Audio.sfx("deny")
		return
	PbRun.reroll(_run)
	_modal_state = ""


func _act_skip() -> void:
	if int(_run.get("skips", 0)) <= 0:
		Audio.sfx("deny")
		return
	PbRun.skip(_run)
	_modal_state = ""
	_banish_mode = false
	_banish_pick = -1


func _act_banish_toggle() -> void:
	if _banish_mode:
		_banish_mode = false
		_banish_pick = -1
	else:
		if int(_run.get("banishes", 0)) <= 0:
			Audio.sfx("deny")
			return
		_banish_mode = true
		_banish_pick = -1
	_modal_state = ""


func _do_banish(index: int) -> void:
	PbRun.banish(_run, index)
	_banish_mode = false
	_banish_pick = -1
	_modal_state = ""
	Audio.sfx("deny")
	_hud.notify("已放逐，重新抽卡")


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
		_hud.notify("尚不可融合：需要两个招式都升到 %d 级" % PbFusion.MOVE_MAX_LEVEL)
		return
	var inst := PbRun.fuse(_run, PbJson.as_dict(ready[0]))
	if not inst.is_empty():
		Audio.sfx("fusion")
		var fdef := PbJson.as_dict(inst.get("def", {}))
		_hud.show_banner("融合：%s" % String(fdef.get("name", "?")),
			"伤害 %.0f · 段数 %.1f" % [float(fdef.get("dmg", 0)),
				float(PbJson.as_dict(fdef.get("fusion", {})).get("hits", 1))], "#8a5cff")


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
	if _settle_scrim.visible:
		return
	_finish(String(_run.get("endHow", "exit")))


## .modal h1 + detail cards (.card.mini style) + .actions buttons.
func _show_settle(result: Dictionary, res: Dictionary) -> void:
	_modal_scrim.visible = false
	_settle_scrim.visible = true
	for c in _settle_body.get_children():
		c.queue_free()
	var reward := PbJson.as_dict(res.get("reward", {}))
	var record := PbJson.as_dict(res.get("record", {}))
	var row := UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_settle_body.add_child(row)
	row.add_child(_settle_card("结果",
		"胜利！" if bool(result.get("victory", false)) else "失败",
		String(result.get("endHow", "")), PbTheme.accent_color("green", "c")))
	row.add_child(_settle_card("战绩", "%d 阶段 · %s" % [int(result.get("stage", 0)), UI.fmt_clock(float(result.get("time", 0)))],
		"%d 击杀 · %s 伤害 · Lv%d" % [int(result.get("kills", 0)), UI.fmt_num(float(result.get("damage", 0))),
			int(result.get("level", 0))], PbTheme.accent_color("blue", "c")))
	var fusions: Array = PbJson.as_array(result.get("fusions", []))
	row.add_child(_settle_card("融合", "%d 次" % fusions.size(), ", ".join(fusions),
		PbTheme.accent_color("purple", "c")))
	row.add_child(_settle_card("奖励", "+%s 星尘" % UI.fmt_num(int(reward.get("stardust", 0))),
		"余额 %s · 记录 %s" % [UI.fmt_num(int(Save.store.get("stardust", 0))), String(record.get("id", "?"))],
		PbTheme.accent_color("yellow", "c")))
	var actions := UI.hbox(8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_settle_body.add_child(actions)
	actions.add_child(UI.button("再来一局", func(): _start_run()))
	actions.add_child(UI.button("返回主菜单", func(): App.back_to_menu(), false, "ghost"))


func _settle_card(title_text: String, value_text: String, sub_text: String, rc: Color) -> Control:
	var panel := PanelContainer.new()
	var s := PbTheme.card_style()
	s.content_margin_left = 14
	s.content_margin_right = 14
	var body := UI.vbox(2)
	panel.add_child(body)
	var head := UI.hbox(6)
	body.add_child(head)
	var badge := UI.chip(title_text, rc)
	head.add_child(badge)
	var val := UI.title(value_text, 20)
	val.add_theme_color_override("font_color", PbTheme.ink())
	body.add_child(val)
	if not sub_text.is_empty():
		body.add_child(UI.dim(sub_text))
	panel.custom_minimum_size = Vector2(200, 0)
	return panel
