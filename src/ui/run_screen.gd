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
var _hazard_view: PbHazardView
var _sun: DirectionalLight3D
var _enemy_nodes: Array[MeshInstance3D] = []
var _orb_nodes: Array[MeshInstance3D] = []
var _bolt_nodes: Array[MeshInstance3D] = []
const HudFx = preload("res://src/ui/hud_fx.gd")

var _hud: RunHud
var _fx: HudFx
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
var _shop_scrim: PanelContainer
var _shop_rows: VBoxContainer
var _shop_sell_rows: VBoxContainer
var _shop_actions: HBoxContainer
var _shop_info: Label
var _shop_open := false
var _meowth_node: MeshInstance3D
var _meowth_lift := 0.0
var _prompt: Label
var _sell_armed_key := ""
var _sell_armed_t := 0.0
var _time := 0.0
var _paused := false
var _trauma := 0.0
var _last_damage_taken := 0.0
var _shake_scale := 1.0
var _msg_seen := 0
var _stage_seen := 1
var _boss_seen := false
var _music_boss := false
var _last_px := 0.0
var _last_pz := 0.0
# Third-person orbit camera. The web locks the pointer during play and feeds
# `camYaw/camPitch` from the relative mouse deltas (bundle @1551771), so the two
# axes must be run-owned state instead of the constants below.
var _cam_yaw := 0.0
var _cam_pitch := 0.45
var _cam_dist := 9.0
var _look_sensitivity := 1.0
var _look_invert_y := false
var _mouse_captured := false


func _ready() -> void:
	_build_world()
	_build_hud()
	_start_run()
	call_deferred("_build_terrain")
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

	_hazard_view = PbHazardView.new()
	_hazard_view.name = "Hazards"
	add_child(_hazard_view)

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
	# Storm event telegraphs: flat yellow discs where bolts are about to land.
	for i in 6:
		var b := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 3.0
		disc.bottom_radius = 3.0
		disc.height = 0.06
		disc.radial_segments = 32
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(1.0, 0.85, 0.22, 0.5)
		b.mesh = disc
		b.material_override = bm
		b.visible = false
		add_child(b)
		_bolt_nodes.append(b)
	# Meowth shop NPC (species 52): a billboard like the enemies, shown only while
	# PbRun's meowth timer has it on the map. Use its PMD idle sheet (full body)
	# rather than the 40x40 UI portrait, which is a face crop blown up.
	var meowth := MeshInstance3D.new()
	var meowth_quad := QuadMesh.new()
	var meowth_layout := PbVisuals.billboard_layout(52, "idle")
	_meowth_lift = float(meowth_layout["lift"])
	meowth_quad.size = meowth_layout["size"]
	var meowth_mat := StandardMaterial3D.new()
	meowth_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	meowth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	meowth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	meowth_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var meowth_tex := PbVisuals.frame_texture(52, "idle", 0.0, 0)
	if meowth_tex == null:
		meowth_tex = PbVisuals.front_texture(52)
	PbVisuals.apply_frame_texture(meowth_mat, meowth_tex)
	meowth.mesh = meowth_quad
	meowth.material_override = meowth_mat
	meowth.visible = false
	add_child(meowth)
	_meowth_node = meowth


# ------------------------------------------------------------------ hud
func _build_hud() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_hud = RunHud.new()
	_hud.name = "RunHud"
	_layer.add_child(_hud)
	UI.fill(_hud)
	# H-17 feedback layer: .lowhp / .flash / .floater sit above the HUD, below
	# the modals (z-index 60 in the web DOM).
	_fx = HudFx.new()
	_fx.name = "HudFx"
	_layer.add_child(_fx)
	UI.fill(_fx)
	# Interactable prompt (`[E] Tienda de Meowth`), shown while the NPC is near.
	_prompt = UI.label("", 18, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -120.0
	_prompt.offset_bottom = -90.0
	_prompt.visible = false
	_layer.add_child(_prompt)

	# .modal shells (CSS .modal: radial scrim, h1 plate, centred column).
	var level := UI.modal_shell("升级！选择强化")
	_modal_scrim = level["scrim"]
	var body: VBoxContainer = level["body"]
	_modal_scrim.visible = false
	_layer.add_child(_modal_scrim)
	UI.fill(_modal_scrim)
	# H-13: `.modal{align-items:center}` + `h1{padding:6px 34px}` -> the title is a
	# capsule, not a full-width band.
	UI.fit_capsule(body.get_parent().get_child(0) as Control, 34.0)
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
	UI.fit_capsule(_settle_body.get_parent().get_child(0) as Control, 34.0)

	var pause := UI.modal_shell(App.ui("En pausa"), true, func(): _toggle_pause())
	var pause_scrim: PanelContainer = pause["scrim"]
	var pause_body: VBoxContainer = pause["body"]
	var prow := UI.hbox(8)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(UI.button(App.ui("Continuar"), func(): _toggle_pause()))
	prow.add_child(UI.button("结束本局", func():
		_toggle_pause()
		_finish("exit"), false, "red"))
	pause_body.add_child(prow)
	pause_scrim.visible = false
	pause_scrim.set_meta("is_pause", true)
	_layer.add_child(pause_scrim)
	UI.fill(pause_scrim)
	UI.fit_capsule(pause_body.get_parent().get_child(0) as Control, 34.0)

	# Meowth shop (nC/aC @1103831/@1104019). The web opens it from the meowth
	# interactable (@1547939); this port shows an [E] prompt next to the NPC
	# (PbRun meowth timer, @1407519/@1407893).
	var shop := UI.modal_shell(App.ui("Meowth: «¿Tienes dinero, miau?»"), true)
	_shop_scrim = shop["scrim"]
	var shop_body: VBoxContainer = shop["body"]
	_shop_scrim.visible = false
	_layer.add_child(_shop_scrim)
	UI.fill(_shop_scrim)
	UI.fit_capsule(shop_body.get_parent().get_child(0) as Control, 34.0)
	_shop_info = UI.dim("")
	_shop_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_body.add_child(_shop_info)
	_shop_rows = UI.vbox(10)
	_shop_rows.name = "ShopRows"
	shop_body.add_child(_shop_rows)
	_shop_sell_rows = UI.vbox(6)
	_shop_sell_rows.name = "ShopSellRows"
	shop_body.add_child(_shop_sell_rows)
	_shop_actions = UI.hbox(10)
	_shop_actions.name = "ShopActions"
	_shop_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_body.add_child(_shop_actions)
	shop_body.add_child(UI.dim(App.ui("Si le compras mucho sin abrir Poké Balls, su próxima tienda saldrá más cara.")))


func _toggle_pause() -> void:
	_paused = not _paused
	for c in _layer.get_children():
		if c.get_meta("is_pause", false) == true:
			c.visible = _paused
	# Pausing releases the pointer so the pause overlay is clickable; resuming
	# captures it again (the web does the same around `state==='paused'`).
	_sync_mouse_capture()
	Audio.sfx("ui")


func _toggle_aim() -> void:
	# re keymap: aim = KeyQ. Flip the run's aim mode the way the web toggles auto/manual
	# acquisition (PbRun._tick_player reads state.aimMode every frame, pb_run.gd:265).
	var cur := str(_run.get("aimMode", "auto"))
	var next := "manual" if cur == "auto" else "auto"
	_run["aimMode"] = next
	_hud.notify(App.ui("Apuntado") + ": " + (App.ui("Automático") if next == "auto" else App.ui("Manual")))
	Audio.sfx("ui")


# ------------------------------------------------------------------ shop
func _open_shop() -> void:
	# The NPC must still be on the map: after 45 s (meowthLeaves) it is gone.
	if not PbRun.meowth_present(_run):
		return
	PbShop.open(_run)
	_shop_open = true
	_shop_scrim.visible = true
	_render_shop()
	Audio.sfx("ui")


func _close_shop() -> void:
	_shop_open = false
	_shop_scrim.visible = false
	_sell_armed_key = ""
	Audio.sfx("ui")


func _shop_reroll() -> void:
	if PbShop.reroll(_run):
		Audio.sfx("level")
		_render_shop()


func _shop_buy(index: int) -> void:
	if PbShop.buy(_run, index):
		Audio.sfx("ui")
		_render_shop()


## Selling (oT @1284315): one click arms the row for 3 s, a second click sells.
func _shop_sell(key: String) -> void:
	if _sell_armed_key == key and _time - _sell_armed_t <= 3.0:
		var price := PbShop.sell(_run, key)
		_sell_armed_key = ""
		if price > 0:
			_hud.notify(App.ui("Vender +{n}", {"n": price}))
			Audio.sfx("ui")
			_render_shop()
		return
	_sell_armed_key = key
	_sell_armed_t = _time
	Audio.sfx("ui", 1.6)
	_render_shop()


## Shop rows: item icon + name/desc + price / VENDIDO (showShop @2178449).
func _render_shop() -> void:
	for child in _shop_rows.get_children():
		child.queue_free()
	for child in _shop_sell_rows.get_children():
		child.queue_free()
	for child in _shop_actions.get_children():
		child.queue_free()
	_shop_info.text = "%d ₽" % int(_run.get("gold", 0))
	var rows := PbShop.stock(_run)
	if rows.is_empty():
		_shop_rows.add_child(UI.dim(App.ui("«Ya lo tienes todo, miau. Aquí no me queda nada para ti.»")))
	for i in rows.size():
		_shop_rows.add_child(_shop_row(i, PbJson.as_dict(rows[i])))
	var sellable := PbShop.sellable(_run)
	if not sellable.is_empty():
		_shop_sell_rows.add_child(UI.dim(App.ui("Vender tus objetos:")))
		for raw in sellable:
			_shop_sell_rows.add_child(_sell_row(PbJson.as_dict(raw)))
	var cost := PbShop.reroll_cost(_run)
	var reroll := UI.button(App.ui("Renovar surtido · {n} ₽", {"n": cost}), _shop_reroll, false, "blue", true)
	reroll.disabled = int(_run.get("gold", 0)) < cost
	_shop_actions.add_child(reroll)
	_shop_actions.add_child(UI.button(App.ui("Salir"), _close_shop, false, "ghost", true))


func _shop_row(index: int, entry: Dictionary) -> Control:
	var key := str(entry.get("key", ""))
	var def := PbShop.item_def(key)
	var meta := PbJson.as_dict(PbData.items_map().get(key, {}))
	var rc := PbTheme.rarity_color(int(def.get("rarity", 0)))
	var panel := UI.panel(12)
	panel.add_theme_stylebox_override("panel",
		PbTheme.stylebox(".card", {"rc": "#" + rc.to_html(false)}))
	var row := UI.hbox(12)
	panel.add_child(row)
	var icon_name := str(meta.get("icon", ""))
	if not icon_name.is_empty():
		row.add_child(UI.icon_rect(icon_name, 36))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label(App.t("items", int(meta.get("id", 0)), str(meta.get("name", key))), 18))
	var desc := str(meta.get("desc", ""))
	if not desc.is_empty():
		col.add_child(UI.dim(desc))
	var player := PbJson.as_dict(_run.get("player", {}))
	col.add_child(UI.dim(App.ui("Tienes {n}/{max}", {
		"n": int(PbActor.item_power(player, key)),
		"max": int(def.get("max", 10))})))
	row.add_child(col)
	var sold := bool(entry.get("sold", false))
	var price := int(entry.get("price", 0))
	var affordable := int(_run.get("gold", 0)) >= price
	var label := App.ui("VENDIDO") if sold else "%d ₽" % price
	var buy := UI.small_button(label, func(): _shop_buy(index),
		"yellow" if not sold and affordable else "ghost")
	buy.disabled = sold or not affordable or not PbShop.can_hold(_run, key)
	row.add_child(buy)
	return panel


## Sell row: name + owned count + `Vender +n` (armed state asks for a second
## press within 3 s).
func _sell_row(entry: Dictionary) -> Control:
	var key := str(entry.get("key", ""))
	var meta := PbJson.as_dict(PbData.items_map().get(key, {}))
	var row := UI.hbox(8)
	var name := UI.label(App.t("items", int(meta.get("id", 0)), str(meta.get("name", key))), 16)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(UI.dim("%d" % int(entry.get("count", 0))))
	var armed := _sell_armed_key == key and _time - _sell_armed_t <= 3.0
	var label := App.ui("¿Vender? Pulsa otra vez") if armed \
		else App.ui("Vender +{n}", {"n": int(entry.get("price", 0))})
	row.add_child(UI.small_button(label, func(): _shop_sell(key), "red" if armed else "ghost"))
	return row


# ------------------------------------------------------------------ run flow
func _start_run() -> void:
	var settings := PbJson.as_dict(Save.store.get("settings", {}))
	Audio.apply_profile_settings(settings)
	var start := Save.handle("POST", "/runs/start", {}, {})
	var species := App.selected_species
	if species <= 0:
		species = 4
	_run = PbRun.create(species, str(Save.store.get("lastBiome", "forest")),
		int(start.get("seed", 0)), Save.lab_deltas())
	if _run.is_empty():
		push_error("Run: could not start (unknown species %d)" % species)
		return
	_run["run_id"] = str(start.get("id", "run-local"))
	_run["aimMode"] = str(settings.get("aimMode", "auto"))
	_shake_scale = clampf(float(settings.get("shake", 1.0)), 0.0, 1.0)
	# Orbit camera settings (web profile: sensitivity 1, invertY off, camDist 9).
	_cam_yaw = 0.0
	_cam_pitch = clampf(float(PbData.const_of("camera.pitch", 0.45)), -0.25, 1.25)
	_cam_dist = clampf(float(settings.get("camDist", PbData.const_of("camera.dist", 9.0))), 4.5, 26.0)
	_look_sensitivity = clampf(float(settings.get("sensitivity", 1.0)), 0.1, 3.0)
	_look_invert_y = bool(settings.get("invertY", false))
	_sync_mouse_capture()
	_time = 0.0
	_last_damage_taken = 0.0
	_trauma = 0.0
	_msg_seen = 0
	_stage_seen = int(_run.get("stage", 1))
	_boss_seen = false
	_music_boss = false
	_modal_state = ""
	_banish_mode = false
	_banish_pick = -1
	_settle_scrim.visible = false
	_modal_scrim.visible = false
	_shop_open = false
	_shop_scrim.visible = false
	_sell_armed_key = ""
	_hud.build(_run)
	if _fx != null:
		_fx.set_low_hp(1.0, false)
	Audio.start_run_music()
	Audio.play_cry(species)


## Build the arena from the run's own seed + biome, so the same seed walks the same map as
## the web client (PbTerrain is asserted against the shipped generator, see tools/terrain_reference.mjs).
func _build_terrain() -> void:
	var biome_id := str(_run.get("biome", "forest"))
	var seed_value := int(_run.get("seed", 0))
	var biome_dict := PbData.biome(biome_id)
	if biome_dict.is_empty():
		push_warning("Run: unknown biome %s, falling back to a flat arena" % biome_id)
		return
	var started := Time.get_ticks_msec()
	_terrain = PbTerrain.create(biome_dict, PbData.world_pack(biome_id), seed_value)
	# PbHazards needs the height field for flat-spot sampling; it stays in-memory
	# only (runs are not persisted mid-stage).
	_run["terrain"] = _terrain
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


## Storm event telegraphs: one yellow disc per queued bolt, faded by its delay.
func _sync_bolts() -> void:
	var marks: Array = PbWeatherEvents.markers(_run)
	for i in _bolt_nodes.size():
		var node := _bolt_nodes[i]
		if i >= marks.size():
			node.visible = false
			continue
		var mark := PbJson.as_dict(marks[i])
		node.visible = true
		var mx := float(mark.get("x", 0.0))
		var mz := float(mark.get("z", 0.0))
		node.position = Vector3(mx, _ground_y(mx, mz) + 0.12, mz)


func _process(delta: float) -> void:
	if _run.is_empty():
		return
	_sync_mouse_capture()
	_time += delta
	var dt := minf(delta, 1.0 / 15.0)
	if str(_run.get("state", "play")) == "over":
		_render(dt)
		_hud.sync(_run, dt)
		_show_settle_once()
		return
	if _paused:
		_render(dt)
		return
	if _shop_open:
		if _sell_armed_key != "" and _time - _sell_armed_t > 3.0:
			_sell_armed_key = ""
			_render_shop()
		_render(dt)
		return
	if str(_run.get("state", "play")) == "modal":
		_render(dt)
		_update_modal()
		return
	# Evolution cinematic (PbEvo): gameplay is paused, the avatar swap already
	# follows player.species_id in _render(), and the reveal comes through
	# _pump_events() as a banner.
	if str(_run.get("state", "play")) == "evolving":
		PbRun.tick(_run, dt)
		_render(dt)
		_hud.sync(_run, dt)
		_pump_events()
		return
	_move_input(dt)
	PbRun.tick(_run, dt)
	_render(dt)
	_hud.sync(_run, dt)
	_pump_events()
	_sync_run_music()
	if str(_run.get("state", "play")) == "modal":
		Audio.sfx("level")


## Pointer lock is part of gameplay: the web captures it while playing (or in the
## evolution cinematic) and releases it for pause/shop/modal/over, so overlays
## stay clickable. Keep the same state machine here.
func _can_look() -> bool:
	if _run.is_empty() or _paused or _shop_open:
		return false
	var state := str(_run.get("state", "play"))
	return state == "play" or state == "evolving"


func _sync_mouse_capture() -> void:
	var want := _can_look()
	_mouse_captured = want
	if DisplayServer.get_name() == "headless":
		return
	var mode := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


## Mouse look + wheel zoom (bundle @1551771: 0.0024 rad/px, invertY flips the
## pitch sign, wheel clamps the boom distance). Returns true when consumed.
func _look_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if not _mouse_captured or not _can_look():
			return false
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		_cam_yaw -= rel.x * 0.0024 * _look_sensitivity
		var pitch_sign := -1.0 if _look_invert_y else 1.0
		_cam_pitch = clampf(_cam_pitch + rel.y * 0.0024 * _look_sensitivity * pitch_sign, -0.25, 1.25)
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not _can_look():
				return false
			_cam_dist = clampf(_cam_dist + (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0), 4.5, 26.0)
			# Persist the zoom like the web profile's `camDist` setting.
			var settings := PbJson.as_dict(Save.store.get("settings", {}))
			settings["camDist"] = snappedf(_cam_dist, 0.1)
			Save.store["settings"] = settings
			return true
	return false


func _exit_tree() -> void:
	# Never leave the macOS cursor hidden when leaving the run.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
		var speed := float(PbJson.as_dict(player.get("stats", {})).get("moveSpeed", 1.0)) * 6.0 \
			* float(player.get("hazardSlow", 1.0))
		dir = dir.normalized()
		# Camera-relative WASD, matching the web: forward = away from the camera,
		# right = camera right (bundle @866266).
		var wx := sin(_cam_yaw) * dir.y + cos(_cam_yaw) * dir.x
		var wz := cos(_cam_yaw) * dir.y - sin(_cam_yaw) * dir.x
		var nx := float(player.get("x", 0.0)) + wx * speed * dt
		var nz := float(player.get("z", 0.0)) + wz * speed * dt
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
		# PMD sheets store 8 rows clockwise from "down/front": row 0 faces +z
		# (towards the start camera), row 2 faces +x, row 4 faces -z, row 6 -x.
		player["facing"] = posmod(roundi(atan2(wx, wz) / (PI / 4.0)), 8)
	var lim := _terrain.walk_lim() if _terrain != null else ARENA_SIZE * 0.5 - 2.0
	player["x"] = clampf(float(player.get("x", 0.0)), -lim, lim)
	player["z"] = clampf(float(player.get("z", 0.0)), -lim, lim)


func _unhandled_input(event: InputEvent) -> void:
	if _look_input(event):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var modal := str(_run.get("state", "")) == "modal" and _modal_scrim.visible
	var over := str(_run.get("state", "")) == "over"
	if _shop_open:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
			_close_shop()
		return
	match event.keycode:
		KEY_R:
			# re keymap: ult/fusion = KeyR (moved off F to align with re).
			if not modal and not _paused and not over:
				_try_fusion()
		KEY_F:
			# re keymap: reroll = KeyF (offer modal only).
			if modal:
				_act_reroll()
		KEY_X:
			# re keymap: skip = KeyX (offer modal only).
			if modal:
				_act_skip()
		KEY_Z:
			# re keymap: banish = KeyZ (offer modal only).
			if modal:
				_act_banish_toggle()
		KEY_Q:
			# re keymap: aim = KeyQ -> toggle runtime aim mode (auto/manual).
			if not _paused and not over:
				_toggle_aim()
		KEY_E:
			# re keymap: capture throw = KeyE (kS.tryThrow/throwBall @1082671).
			# The meowth interactable shares the key and wins while the NPC is near.
			if not modal and not _paused and not over:
				if PbRun.meowth_near(_run):
					_open_shop()
				elif PbCapture.throw_ball(_run):
					Audio.sfx("ui")
		KEY_P:
			if not over:
				_toggle_pause()
		KEY_ESCAPE:
			if over:
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
		KEY_4, KEY_KP_4:
			if modal:
				_offer_key(3)


# ------------------------------------------------------------------ events
## Route new PbRun messages the way the web routes them: stage-ups and boss
## spawns become banners (.banner), everything else a toast (.toast).
func _pump_events() -> void:
	var msgs: Array = PbJson.as_array(_run.get("messages", []))
	while _msg_seen < msgs.size():
		var text := str(msgs[_msg_seen])
		_msg_seen += 1
		if text.begins_with("stage"):
			var n := int(text.get_slice(" ", 1))
			_hud.show_banner(App.ui("Fase {n}", {"n": n}), "击杀首领才能进入下一阶段", "#ff5a5f")
			Audio.sfx("level")
			_sync_run_music()
		elif text.begins_with("boss!"):
			_hud.show_banner("首领出现了！", text.trim_prefix("boss!"), "#e82a5a", true)
			Audio.sfx("boss")
			_sync_run_music()
		elif text.begins_with("fused"):
			_hud.show_banner("融合成功！", text.trim_prefix("fused "), "#8a5cff")
		elif text.begins_with("banner|"):
			# Capture flow (kS @1074615): `banner|title|body|colour[|big]`.
			var parts := text.split("|")
			var color := str(parts[3]) if parts.size() > 3 else "#f7c948"
			var big := parts.size() > 4 and str(parts[4]) == "big"
			_hud.show_banner(str(parts[1]), str(parts[2]) if parts.size() > 2 else "", color, big)
		else:
			_hud.notify(text)
	var stage := int(_run.get("stage", 1))
	if stage != _stage_seen:
		_stage_seen = stage
	if bool(_run.get("bossSpawned", false)) and not _boss_seen:
		_boss_seen = true


## Web `musicFor()`: boss track while a boss is alive, else the run's ingame track.
## Mirrors its 0.5s poll at the stage/boss event points; the state flag avoids
## restarting the same fade on every frame.
func _sync_run_music() -> void:
	var boss := _boss_alive()
	if boss == _music_boss:
		return
	_music_boss = boss
	Audio.play_run_music(boss)


func _boss_alive() -> bool:
	if not bool(_run.get("bossSpawned", false)):
		return false
	var index := int(_run.get("bossIndex", -1))
	if index < 0:
		return false
	return PbEnemies.is_alive(PbJson.as_dict(_run.get("enemies", {})), index)


# ------------------------------------------------------------------ render
## Screen-space anchor for the .floater: the hit number in the web build is a
## world-space vfx.number over the damaged actor; we project the player's head.
func _player_screen_point() -> Vector2:
	var viewport := get_viewport().get_visible_rect().size
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var head := Vector3(px, _ground_y(px, pz) + 1.2, pz)
	if _camera == null or not _camera.is_inside_tree():
		return viewport * Vector2(0.5, 0.55)
	var p := _camera.unproject_position(head)
	return Vector2(clampf(p.x, 40.0, viewport.x - 40.0), clampf(p.y, 60.0, viewport.y - 60.0))


func _render(dt: float) -> void:
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var py := _ground_y(px, pz)
	_player_node.position = Vector3(px, py, pz)
	if _view != null:
		_view.tick(dt, Vector3(px, py, pz), _camera)
		# Map weather events blend their `look` over the biome look: fog near/far,
		# sky colours, sun tint + intensity, eclipse darkening.
		_view.apply_weather_look(PbWeatherEvents.look_overrides(_run),
			PbWeatherEvents.look_weight(_run))
		var look: Dictionary = _view.current_look()
		var flash := PbWeatherEvents.flash(_run)
		_sun.light_energy = clampf(0.7 * float(look.get("light", 1.0)) + flash * 1.8, 0.12, 2.4)
		_sun.light_color = PbWorldView.color_from_int(int(look.get("sun", 16773590)))
		_sync_bolts()
	if _hazard_view != null:
		_hazard_view.sync(_run, _terrain)
	if _player_node.get_child_count() == 0:
		_player_node.add_child(PbVisuals.avatar(int(player.get("species_id", 1))))
	else:
		# Billboard frames: swap the texture using the PMD sheet timings.
		var node = _player_node.get_child(0)
		if node is MeshInstance3D:
			# Compare against last frame's position (not px, which equals this frame's x).
			var moved := absf(px - _last_px) > 1e-4 or absf(pz - _last_pz) > 1e-4
			var anim := "walk" if moved else "idle"
			var species := int(player.get("species_id", 1))
			var tex := PbVisuals.frame_texture(species, anim, _time, int(player.get("facing", 0)))
			var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
			var mesh := (node as MeshInstance3D).mesh
			if mesh is QuadMesh:
				var layout := PbVisuals.billboard_layout(species, anim)
				(mesh as QuadMesh).size = layout["size"]
				(node as MeshInstance3D).position = Vector3(0, float(layout["lift"]), 0)
			if tex != null:
				PbVisuals.apply_frame_texture(mat, tex)
	_last_px = px
	_last_pz = pz
	var pitch := _cam_pitch
	var dist := _cam_dist
	# Hit feedback: the run class carries a `trauma` value that shake() adds to.
	var taken_now := float(PbJson.as_dict(_run.get("stats", {})).get("damageTaken", 0.0))
	if taken_now > _last_damage_taken + 0.001:
		var dealt := taken_now - _last_damage_taken
		_trauma = minf(1.0, _trauma + 0.3)
		_last_damage_taken = taken_now
		Audio.sfx("hit")
		# H-17: `.flash` on every player hit + the .floater damage number (the
		# stylesheet paints it white with a 5px ink stroke).
		if _fx != null:
			_fx.flash()
			_fx.spawn_floater(UI.fmt_num(dealt), Color.WHITE, _player_screen_point())
	if _fx != null:
		var hp_ratio := clampf(float(player.get("hp", 0.0)) / maxf(1.0, float(player.get("maxHp", 1.0))), 0.0, 1.0)
		_fx.set_low_hp(hp_ratio, bool(player.get("dead", false)))
	_trauma = maxf(0.0, _trauma - dt * 2.5)
	var shake_amount := _trauma * _trauma * 0.6 * _shake_scale
	var shake_offset := Vector3(PbRng.randf_range(-shake_amount, shake_amount),
		PbRng.randf_range(-shake_amount, shake_amount), 0.0)
	# Same rig as the reference (pitch .45, dist 9), riding the height field and
	# orbiting the player on the mouse-driven yaw.
	var cos_pitch := cos(pitch)
	# Keep the boom above the height field even at the -0.25 pitch clamp.
	var cam_y := maxf(py + sin(pitch) * dist, py + 0.4)
	_camera.position = Vector3(
		px + sin(_cam_yaw) * cos_pitch * dist,
		cam_y,
		pz + cos(_cam_yaw) * cos_pitch * dist) + shake_offset
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
		var species := int(PbEnemies.get_field(pool, "species", i))
		var layout := PbVisuals.billboard_layout(species, "walk", scale)
		# Enemies stand on the height field, not on a flat plane; `lift` keeps the
		# sprite's opaque feet (not the padded frame edge) on that point.
		node.position = Vector3(ex, _ground_y(ex, ez) + float(layout["lift"]), ez)
		(node.mesh as QuadMesh).size = layout["size"]
		var mat := node.material_override as StandardMaterial3D
		var tex := PbVisuals.frame_texture(species, "walk", _time + float(i) * 0.11, 1)
		if tex == null:
			# Mirror re's front/<id>.png fallback: a missing PMD sheet must show the
			# static portrait, never an untextured (white) quad.
			tex = PbVisuals.front_texture(species)
		if mat != null:
			PbVisuals.apply_frame_texture(mat, tex)
			if tex != null:
				var hp_ratio := 1.0
				var maxhp := float(PbEnemies.get_field(pool, "maxHp", i))
				if maxhp > 0.0:
					hp_ratio = clampf(float(PbEnemies.get_field(pool, "hp", i)) / maxhp, 0.0, 1.0)
				mat.albedo_color = Color(1.0, 0.35 + 0.65 * hp_ratio, 0.35 + 0.65 * hp_ratio)
				# Golden Meowth + eclipse shiny reads through the billboard tint.
				if PbWeatherEvents.is_event_meowth(_run, i):
					mat.albedo_color = Color(1.45, 1.12, 0.4)
				elif PbEnemies.flags(pool, i) & int(PbEnemies.Flag["Shiny"]) != 0:
					mat.albedo_color = Color(1.35, 1.1, 1.6)
			else:
				mat.albedo_color = PbVisuals.color_for(PbData.species(species))
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
		var om := node2.material_override as StandardMaterial3D
		if om != null:
			var is_coin := str(orb.get("kind", "xp")) == "coin"
			om.albedo_color = Color(1.0, 0.8, 0.2) if is_coin else Color(0.45, 1.0, 0.55)
			om.emission = Color(1.0, 0.75, 0.15) if is_coin else Color(0.35, 0.9, 0.45)
	for i in range(orb_used, _orb_nodes.size()):
		_orb_nodes[i].visible = false

	# Meowth NPC + `[E]` prompt. The prompt hides while a modal/shop is open.
	var meowth_here := PbRun.meowth_present(_run)
	_meowth_node.visible = meowth_here
	if meowth_here:
		var mx := float(_run.get("meowthX", 0.0))
		var mz := float(_run.get("meowthZ", 0.0))
		_meowth_node.position = Vector3(mx, _ground_y(mx, mz) + _meowth_lift
			+ sin(_time * 2.0) * 0.08, mz)
	var play_state := str(_run.get("state", "play")) == "play"
	var prompt_on := meowth_here and PbRun.meowth_near(_run) and not _shop_open \
		and not _paused and play_state and not _modal_scrim.visible \
		and not _settle_scrim.visible
	_prompt.visible = prompt_on
	if prompt_on:
		_prompt.text = "[E] " + App.ui("Tienda de Meowth")


# ------------------------------------------------------------------ modals
## showLevelUp() parity (bundle @2173200): h1 + .cards of .card.offer + the
## reroll/skip/banish actions + buildMini current-move row.
func _update_modal() -> void:
	if str(_run.get("state", "play")) != "modal":
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
		# H-16: `.card .key` shows the 1-4 pick shortcut (matches KEY_1..KEY_4).
		data["key"] = str(i + 1)
		_modal_cards.add_child(UI.card_offer(data, func(): _offer_key(i), i))
	# .actions: btn blue/ghost/red small with counts + kbd hints, disabled at 0.
	var reroll := UI.small_button("F " + App.ui("Refrescar ({n})", {"n": int(_run.get("rerolls", 0))}), _act_reroll, "blue")
	reroll.disabled = int(_run.get("rerolls", 0)) <= 0
	reroll.add_child(_action_icon("reroll"))
	_modal_actions.add_child(reroll)
	var skip := UI.small_button("X " + App.ui("Saltar ({n})", {"n": int(_run.get("skips", 0))}), _act_skip, "ghost")
	skip.disabled = int(_run.get("skips", 0)) <= 0
	skip.add_child(_action_icon("skip"))
	_modal_actions.add_child(skip)
	var banish := UI.small_button("Z " + (App.ui("Cancelar") if _banish_mode else App.ui("Desterrar ({n})", {"n": int(_run.get("banishes", 0))})),
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
		var chip := UI.chip("%s Lv%d" % [App.t("moves", int(def.get("id", 0)), str(def.get("name", "?"))), int(inst.get("level", 1))],
			PbTheme.type_color(str(def.get("type", "normal"))))
		_modal_mini.add_child(chip)
	if _banish_mode:
		# CSS .cards.banning: hue-rotate the row, outline the picked card red.
		_modal_cards.modulate = Color(1.15, 0.9, 0.9)
		_hud.notify(App.ui("Desterrar pide confirmación: pulsa la carta otra vez para desterrarla."))
	else:
		_modal_cards.modulate = Color.WHITE
	Audio.sfx("level")


func _action_icon(name: String) -> Control:
	return UI.icon_rect(name, 18)


## .card.offer payload from a PbCards card (structure per offerCard(); amounts
## untouched). Rarity mapping is estimated -- see PORT_STATUS.
func _offer_card_data(card: Dictionary) -> Dictionary:
	var kind := str(card.get("kind", "stat"))
	var mods: Array = PbJson.as_array(card.get("mods", []))
	var label_text := str(card.get("label", ""))
	var out := {"lines": [], "mods": mods}
	var rc: Color
	var rar := 0
	match kind:
		"new_move":
			var def := PbMoves.resolve(str(card.get("move_key", "")))
			var type_name := str(def.get("type", "normal"))
			rc = PbTheme.type_color(type_name)
			out["rar_text"] = App.ui("Movimiento")
			out["kind_text"] = App.ui("NUEVO")
			out["title"] = App.t("moves", int(def.get("id", 0)), str(def.get("name", "?")))
			out["sub"] = "%s · %s" % [App.ui("Físico") if str(def.get("cls", "physical")) == "physical" else App.ui("Especial"),
				str(def.get("arch", ""))]
			out["lines"] = [str(def.get("desc", ""))]
			out["icon_name"] = type_name if ResourceLoader.exists("res://assets/ui/icons/%s.png" % type_name) else "poke-ball"
			rar = mini(4, int(roundf(float(def.get("dmg", 10.0)) / 12.0)))
		"move_upgrade":
			var def2 := _move_def_by_key(str(card.get("move_key", "")))
			rar = clampi(int(card.get("rarity", 0)), 0, PbCards.RARITY_MULT.size() - 1)
			rc = PbTheme.rarity_color(rar)
			out["rar_text"] = App.ui("MEJORA")
			out["kind_text"] = "升级"
			out["title"] = App.t("moves", int(def2.get("id", 0)), str(def2.get("name", card.get("move_key", "?"))))
			var lvl := int(card.get("level", 1))
			out["sub"] = App.ui("Nivel {a} → {b} (máx. {max})", {
				"a": lvl, "b": int(card.get("next_level", lvl + 1)),
				"max": int(card.get("cap", PbActor.MOVE_MAX_LEVEL))})
			# Ey() picks 2 (3 at rarity >= 1.6) ups: list every one, not just the first.
			var lines := []
			for mod in mods:
				lines.append(_mod_line(PbJson.as_dict(mod)))
			out["lines"] = lines if not lines.is_empty() else [label_text]
			out["icon_name"] = str(def2.get("type", "")) if ResourceLoader.exists("res://assets/ui/icons/%s.png" % str(def2.get("type", ""))) else ""
		"new_vit", "up_vit":
			# qS() @1100020: title = vitamin name, sub = level -> level+1 / "Nueva
			# vitamina", line = the rarity-scaled increment, icon = `item:`+ icon.
			var vdef := PbVitamins.def_of(str(card.get("vit", "")))
			var vstat := str(vdef.get("stat", ""))
			rar = clampi(int(card.get("rarity", 0)), 0, PbCards.RARITY_MULT.size() - 1)
			rc = PbTheme.rarity_color(rar)
			out["rar_text"] = _rar_name(rar)
			# The `.kind` badge: `newVit` -> NUEVA, everything else -> MEJORA.
			out["kind_text"] = App.ui("NUEVA") if kind == "new_vit" else App.ui("MEJORA")
			out["title"] = App.ui(str(vdef.get("name", card.get("vit", "?"))))
			var lvl := int(card.get("level", 0))
			out["sub"] = App.ui("Nueva vitamina") if lvl <= 0 else App.ui(
				"Nivel {a} → {b} (máx. {max})", {"a": lvl, "b": lvl + 1,
				"max": int(card.get("cap", PbVitamins.LEVEL_CAP))})
			var value := float(PbCards.RARITY_MULT[rar])
			var amount := float(vdef.get("per", 0.0)) * value
			var pct := str(vdef.get("kind", "mul")) == "mul" \
				or vstat in ["critChance", "evasion", "lifesteal"]
			var amount_text := ("+%s%%" % _trim_num(amount * 100.0, 1)) if pct \
				else ("+%s" % _trim_num(amount, 2))
			if bool(vdef.get("dice", false)):
				out["lines"] = [App.ui("Tira el dado: la estadística de una vitamina al azar, ×{n}",
					{"n": _trim_num(PbVitamins.DICE_SCALE * value, 2)})]
			elif not PbJson.as_array(vdef.get("extra", [])).is_empty():
				# qS: extra vitamins show the stat label, then one line per side mod.
				out["lines"] = ["%s %s" % [amount_text, PbCards._label(vstat).to_lower()]]
				for raw_extra in PbJson.as_array(vdef.get("extra", [])):
					var extra := PbJson.as_dict(raw_extra)
					out["lines"].append("+%s%% %s" % [
						_trim_num(float(extra.get("mul", 0.0)) * value * 100.0, 1),
						PbCards._label(str(extra.get("stat", ""))).to_lower()])
			else:
				out["lines"] = ["%s %s" % [amount_text, str(vdef.get("desc", vstat)).to_lower()]]
				var note := str(vdef.get("note", ""))
				if not note.is_empty():
					out["lines"].append(note)
			out["icon_name"] = str(vdef.get("icon", ""))
		"type":
			rc = PbTheme.type_color(str(card.get("type", "normal")))
			out["rar_text"] = "属性"
			out["kind_text"] = App.ui("MEJORA")
			out["title"] = label_text
			out["sub"] = "%s 属性加成" % App.t("types", str(card.get("type", "")), str(card.get("type", "")))
			for raw in mods:
				out["lines"].append(_mod_line(PbJson.as_dict(raw)))
			out["icon_name"] = str(card.get("type", "")) if ResourceLoader.exists("res://assets/ui/icons/%s.png" % str(card.get("type", ""))) else ""
		_:
			var mod0 := PbJson.as_dict(mods[0]) if not mods.is_empty() else {}
			# estimated magnitude -> rarity band (0..2), flagged as ours
			var mag := absf(float(mod0.get("mul", 0)) - 1.0) * 100.0 if mod0.has("mul") else absf(float(mod0.get("add", 0.0))) * 100.0
			rar = 0 if mag < 10.0 else (1 if mag < 18.0 else 2)
			rc = PbTheme.rarity_color(rar)
			out["rar_text"] = _rar_name(rar)
			out["kind_text"] = App.ui("MEJORA")
			out["title"] = label_text
			out["sub"] = str(card.get("stat", ""))
			for raw in mods:
				out["lines"].append(_mod_line(PbJson.as_dict(raw)))
	out["rc"] = rc
	out["shine"] = rar >= 2
	out["key"] = ""
	return out


func _rar_name(rar: int) -> String:
	var zh := [App.ui("Común"), App.ui("Poco común"), App.ui("Raro"), App.ui("Épico"), App.ui("Legendario")]
	return str(zh[clampi(rar, 0, zh.size() - 1)])


## JS `+n.toFixed(k)` drops trailing zeros (10.0 -> "10"); mirror that here.
func _trim_num(value: float, decimals: int) -> String:
	var text := ("%." + str(decimals) + "f") % value
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text


func _mod_line(mod: Dictionary) -> String:
	if mod.has("add"):
		var v := float(mod["add"])
		return "%s +%s" % [str(mod.get("stat", "?")), ("%d%%" % int(roundf(v * 100.0)) if absf(v) < 1.0 else str(v))]
	return "%s ×%.2f" % [str(mod.get("stat", "?")), float(mod.get("mul", 1.0))]


func _move_def_by_key(key: String) -> Dictionary:
	var player: Dictionary = _run.get("player", {})
	for raw in PbJson.as_array(player.get("moves", [])):
		if raw == null:
			continue
		var def := PbJson.as_dict(PbJson.as_dict(raw).get("def", {}))
		if str(def.get("key", "")) == key:
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
			_hud.notify("再按一次确认放逐「%s」" % str(PbJson.as_dict(offers[index]).get("label", "?")))
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
		_hud.show_banner(App.ui("Fusión") + ": " + App.t("moves", int(fdef.get("id", 0)), str(fdef.get("name", "?"))),
			"伤害 %.0f · 段数 %.1f" % [float(fdef.get("dmg", 0)),
				float(PbJson.as_dict(fdef.get("fusion", {})).get("hits", 1))], "#8a5cff")


# ------------------------------------------------------------------ settle
func _finish(how: String) -> void:
	if str(_run.get("state", "")) == "settled":
		return
	var result := PbRun.finish(_run, how)
	PbRun.result(_run)
	_run["state"] = "settled"
	var res := Save.handle("POST", "/runs/%s/finish" % str(_run.get("run_id", "local")), {}, {"result": result})
	App.last_result = result
	App.last_settle = res
	# Web leaves the arena on toMenu, which restarts the menu/halloween track.
	Audio.play_music("menu")
	Audio.sfx("boss")
	_show_settle(result, res)


func _show_settle_once() -> void:
	if _settle_scrim.visible:
		return
	_finish(str(_run.get("endHow", "exit")))


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
	row.add_child(_settle_card(App.ui("Resultado"),
		App.ui("¡Victoria!") if bool(result.get("victory", false)) else App.ui("Derrota"),
		str(result.get("endHow", "")), PbTheme.accent_color("green", "c")))
	row.add_child(_settle_card("战绩", "%d 阶段 · %s" % [int(result.get("stage", 0)), UI.fmt_clock(float(result.get("time", 0)))],
		"%d 击杀 · %s 伤害 · Lv%d" % [int(result.get("kills", 0)), UI.fmt_num(float(result.get("damage", 0))),
			int(result.get("level", 0))], PbTheme.accent_color("blue", "c")))
	var fusions: Array = PbJson.as_array(result.get("fusions", []))
	row.add_child(_settle_card(App.ui("Fusión"), "%d 次" % fusions.size(), ", ".join(fusions),
		PbTheme.accent_color("purple", "c")))
	row.add_child(_settle_card(App.ui("Premios"), App.ui("+{n} de Polvo Estelar", {"n": UI.fmt_num(int(reward.get("stardust", 0)))}),
		"余额 %s · 记录 %s" % [UI.fmt_num(int(Save.store.get("stardust", 0))), str(record.get("id", "?"))],
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
