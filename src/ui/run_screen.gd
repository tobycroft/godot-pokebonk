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
# Attack-cast visuals. The web's per-move vfx table (bundle main-C5MieX6g @439385)
# is a set of runtime pixel-shape closures, not data; each entry exposes some
# combination of `strike/hit/draw/trail/cone/beam/nova/boom/sky+warn/dash/orbit/
# zone/link/cast/aura` plus an optional `shape/color/size` projectile. The port
# plays one form per archetype, picked from the dominant primitive shared by the
# moves of that archetype (see FX_FORM). Every form reuses the same small pools
# below, tinted from PbTheme.type_color so no colour is hard-coded here.
const PROJ_POOL := 28
const SPARK_POOL := 128
const RING_POOL := 20
const DISC_POOL := 12
const BEAM_POOL := 40
var _fx_root: Node3D
var _proj_nodes: Array[MeshInstance3D] = []
var _spark_nodes: Array[MeshInstance3D] = []
var _ring_nodes: Array[MeshInstance3D] = []
var _disc_nodes: Array[MeshInstance3D] = []
var _beam_nodes: Array[MeshInstance3D] = []
var _proj_cursor := 0
var _spark_cursor := 0
var _ring_cursor := 0
var _disc_cursor := 0
var _beam_cursor := 0
var _glow_tex: ImageTexture
var _ring_tex: ImageTexture
var _strip_tex: ImageTexture
## Archetype -> web form. Derived by matching every move of each port archetype
## against its entry in the web vfx table (Ah/Am/Pm/Um/Jm/$m, @437192): e.g. all
## `beam` archetype moves carry `beam()`, all `meteor`/`smite` carry `sky+warn`,
## all `cone` carry `cone()`. `random` (metronome) has no entry at all, so it
## stays silent, as in the web.
const FX_FORM := {
	"strike": "melee",
	"dash": "dash",
	"bolt": "projectile",
	"homing": "projectile",
	"barrage": "projectile",
	"boomerang": "projectile",
	"wave": "projectile",
	"drain": "projectile",
	"orb": "boom",
	"lob": "boom",
	"vortex": "boom",
	"trap": "boom",
	"nova": "nova",
	"spin": "nova",
	"meteor": "sky",
	"smite": "sky",
	"beam": "beam",
	"cone": "cone",
	"orbit": "orbit",
	"chain": "link",
	"aura": "aura",
	"trail": "zone",
	"buff": "aura",
	"weather": "aura",
	"random": "none",
	"slam": "nova",
}
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
var _altar_node: Node3D
var _altar_light: OmniLight3D
var _portal_node: Node3D
var _portal_light: OmniLight3D
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
# Player vertical motion. The web actor is a height-field walker with a real vertical
# velocity (`vel.y -= 30*dt`, bundle @870247), Space jump (`vel.y = 11*sqrt(jumpHeight)`,
# second jump 0.92x, @870202), a 0.6 step limit probed `radius*0.8` ahead (`ne/.6, re=radius*.8`,
# @871154) and ground snapping within 0.9 while walking downhill. Feet height used to be
# `_ground_y()` teleported every frame, which removed jumping and let the actor walk up any
# cliff; these keep the same sim state (x/z) and only simulate y.
const PLAYER_RADIUS := 0.5
const GRAVITY := 30.0
const JUMP_SPEED := 11.0
const STEP_LIMIT := 0.6
const PROBE_DIST := PLAYER_RADIUS * 0.8
const GROUND_SNAP := 0.9
## Types that auto-climb a blocked step in the web (`wb`): fighting/bug/ghost (plus floats).
const CLIMB_TYPES := ["fighting", "bug", "ghost"]
## Shift (`dash='ShiftLeft'` @7387; also ShiftRight/ControlLeft @867905). The web
## has no stamina: a ground tap sets `slideT=.55, slideCd=.9` and a 1.9x
## (`E*1.9`, 2.3x on ice) velocity that decays by `exp(-2.2*dt)` (@868273). An
## airborne tap dives (`vel.y=-34`, horizontal x.35, @868067); landing calls
## `slam()` (@855540) with `mb=2` cooldown, `hb=8` fall normalisation and
## `gb=6.3` base move speed (@834772).
const BASE_SPEED := 6.3
const SLIDE_TIME := 0.55
const SLIDE_CD := 0.9
const SLIDE_MUL := 1.9
const SLIDE_DECAY := 2.2
const DIVE_FALL_SPEED := 34.0
const DIVE_MIN_HEIGHT := 1.2
const DIVE_HORIZONTAL := 0.35
const SLAM_CD := 2.0
var _player_py := 0.0
var _player_vy := 0.0
var _grounded := true
var _jumps_left := 0
var _py_ready := false
var _cam_follow_y := 0.0
var _cam_follow_ready := false
## Shift state: slide timer, cooldown, decaying speed + captured world direction;
## dive flag, apex height (for the landing fall) and the slam cooldown.
var _slide_t := 0.0
var _slide_cd := 0.0
var _slide_speed := 0.0
var _slide_dir := Vector2.ZERO
var _diving := false
var _apex := 0.0
var _slam_cd := 0.0


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
	_build_attack_fx()

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
	# Boss altar + portal: the web's `boss` interactable loads models/boss.glb
	# (@1287232 `boss:['boss',6.2]`; 6.2 is the authored height, the glb is already
	# in world units) and `portal` loads portal.glb, absent from this mirror, so
	# the tower gate reuses the local tower_portal.glb at the same authored scale.
	_altar_node = _build_prop("boss", 1.0, Color(1.0, 0.72, 0.28), 1.6)
	add_child(_altar_node)
	_altar_light = _altar_node.get_meta("light")
	_portal_node = _build_prop("tower_portal", 1.0, Color(0.62, 0.45, 1.0), 1.3)
	add_child(_portal_node)
	_portal_light = _portal_node.get_meta("light")


## One `assets/models/<key>.glb` prop plus the emissive OmniLight the world
## shader would otherwise supply for the altar/portal glow.
func _build_prop(key: String, scale_v: float, light_color: Color, light_energy: float) -> Node3D:
	var root := Node3D.new()
	root.visible = false
	var path := "res://assets/models/%s.glb" % key
	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var node: Node = (packed as PackedScene).instantiate()
			if node is Node3D:
				(node as Node3D).scale = Vector3.ONE * scale_v
				root.add_child(node)
	var light := OmniLight3D.new()
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = 8.0
	light.position = Vector3(0.0, 2.2, 0.0)
	root.add_child(light)
	root.set_meta("light", light)
	return root


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


## The altar interaction (@1297900): the guardian appears 6-10 units away
## and its `boss!` message becomes the usual banner.
func _wake_guardian() -> void:
	if not PbRun.wake_guardian(_run):
		return
	Audio.sfx("boss")
	_sync_run_music()


## enterPortal (@1532894): taking the portal advances the stage; the next tick
## closes the run once the last stage is cleared.
func _enter_portal() -> void:
	if not PbRun.enter_portal(_run):
		return
	Audio.sfx("level")
	_sync_run_music()


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
	# `.item-row h4{font-family:var(--font-title);...font-weight:900}`.
	var item_name := UI.label(App.t("items", int(meta.get("id", 0)), str(meta.get("name", key))), 18,
		PbTheme.ink())
	item_name.add_theme_font_override("font", PbTheme.font("title"))
	col.add_child(item_name)
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
	# Vertical state re-seeds from the new spawn point on the next frame.
	_player_py = 0.0
	_player_vy = 0.0
	_grounded = true
	_jumps_left = 0
	_py_ready = false
	_cam_follow_ready = false
	_slide_t = 0.0
	_slide_cd = 0.0
	_slide_speed = 0.0
	_slide_dir = Vector2.ZERO
	_diving = false
	_apex = 0.0
	_slam_cd = 0.0
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
	# Re-pick the altar on the real height field (create() only had the fallback).
	PbRun.place_altar(_run, true)
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


# ------------------------------------------------------------------ attack fx
# The web draws each cast from runtime pixel shapes (bundle @439385) and ships
# no fire/element png/glb asset to port, so the soft glow is generated at runtime
# and tinted per event by PbTheme.type_color.
func _glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	# Hand-built radial alpha falloff: GradientTexture2D's radial fill left a
	# hard square edge in the additive pass, which read as UI boxes in-run.
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			# Solid core with a soft rim: a pure quadratic fell off so fast that
			# the shapes read as faint smears against the bright grass.
			var a := 1.0
			if d > 0.35:
				a = pow((1.0 - d) / 0.65, 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


## Hollow ring mask for nova/impact waves (the web's `ring()` primitive).
func _ring_texture() -> ImageTexture:
	if _ring_tex != null:
		return _ring_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := smoothstep(0.5, 0.82, d) * (1.0 - smoothstep(0.86, 1.0, d))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex


func _glow_material(billboard := true, ring := false, strip := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Normal alpha, not additive: the additive pass clipped to white over the
	# bright grass field and lost the element colour (the web's own shapes are
	# solid-colour pixel sprites; only its separate glow layer is additive).
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if strip:
		mat.albedo_texture = _strip_texture()
	elif ring:
		mat.albedo_texture = _ring_texture()
	else:
		mat.albedo_texture = _glow_texture()
	mat.albedo_color = Color.WHITE
	return mat


## Solid strip with soft edges across its width: the shape the web's `beams`
## queue draws (a straight quad), unlike the round glow used for orbs.
func _strip_texture() -> ImageTexture:
	if _strip_tex != null:
		return _strip_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var v := float(y) / float(size - 1)
		var a := pow(1.0 - absf(v - 0.5) * 2.0, 0.7)
		for x in size:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	_strip_tex = ImageTexture.create_from_image(img)
	return _strip_tex


func _make_fx_quad(size: float, billboard: bool, ring := false, strip := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	node.mesh = quad
	node.material_override = _glow_material(billboard, ring, strip)
	node.visible = false
	_fx_root.add_child(node)
	return node


func _build_attack_fx() -> void:
	_fx_root = Node3D.new()
	_fx_root.name = "AttackFx"
	add_child(_fx_root)
	for i in PROJ_POOL:
		_proj_nodes.append(_make_fx_quad(1.4, true))
	for i in SPARK_POOL:
		_spark_nodes.append(_make_fx_quad(0.6, true))
	for i in RING_POOL:
		_ring_nodes.append(_make_fx_quad(1.0, true, true))
	# Ground rings lie flat: no billboard, so the -90 deg pitch sticks.
	for i in DISC_POOL:
		var disc := _make_fx_quad(1.0, false, true)
		disc.rotation = Vector3(-PI / 2, 0, 0)
		_disc_nodes.append(disc)
	# Beams are ribbons placed with an explicit basis (see _spawn_beam). The web
	# draws them as thin solid strips (`beams.spawn(...,width,.05)` @430519) with
	# a half-length white core, so they get their own soft-edged strip texture.
	for i in BEAM_POOL:
		_beam_nodes.append(_make_fx_quad(1.0, false, false, true))


## Drain PbRun's capped cosmetic queue. Damage already happened in the sim
## (PbRun._fire -> PbDamage.strike); everything below is presentation only.
func _sync_fx_events() -> void:
	var events: Array = PbJson.as_array(_run.get("fxEvents", []))
	if events.is_empty():
		return
	_run["fxEvents"] = []
	var budget := 8
	for raw in events:
		if budget <= 0:
			break
		budget -= 1
		_spawn_fx_event(PbJson.as_dict(raw))


func _spawn_fx_event(ev: Dictionary) -> void:
	if _fx_root == null:
		return
	var color := PbTheme.type_color(str(ev.get("type", "normal")))
	if str(ev.get("kind", "hit")) == "cast":
		_fx_aura(ev, color)
		return
	match str(FX_FORM.get(str(ev.get("arch", "")), "projectile")):
		"none":
			return
		"melee":
			_fx_melee(ev, color)
		"dash":
			_fx_dash(ev, color)
		"nova":
			_fx_nova(ev, color)
		"sky":
			_fx_sky(ev, color)
		"beam":
			_fx_beam(ev, color)
		"cone":
			_fx_cone(ev, color)
		"orbit":
			_fx_orbit(ev, color)
		"link":
			_fx_link(ev, color)
		"zone":
			_fx_zone(ev, color)
		"aura":
			_fx_aura(ev, color)
		"boom":
			_fx_boom(ev, color)
		_:
			_fx_projectile(ev, color)


## World-space endpoints of one cast: caster chest -> target body.
func _fx_points(ev: Dictionary) -> Array:
	var px := float(ev.get("x", 0.0))
	var pz := float(ev.get("z", 0.0))
	var tx := float(ev.get("tx", px))
	var tz := float(ev.get("tz", pz))
	return [
		Vector3(px, _ground_y(px, pz) + 1.2, pz),
		Vector3(tx, _ground_y(tx, tz) + 1.0, tz),
	]


func _reset_fx_node(node: MeshInstance3D, color: Color, alpha := 1.0) -> StandardMaterial3D:
	var old = node.get_meta("fx_tween", null) if node.has_meta("fx_tween") else null
	if old != null and old is Tween:
		(old as Tween).kill()
	node.visible = true
	var mat := node.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	return mat


func _take_proj(color: Color) -> MeshInstance3D:
	var node := _proj_nodes[_proj_cursor % _proj_nodes.size()]
	_proj_cursor += 1
	_reset_fx_node(node, color)
	node.scale = Vector3.ONE
	return node


func _take_spark(color: Color) -> MeshInstance3D:
	var node := _spark_nodes[_spark_cursor % _spark_nodes.size()]
	_spark_cursor += 1
	_reset_fx_node(node, color)
	return node


func _take_ring(color: Color) -> MeshInstance3D:
	var node := _ring_nodes[_ring_cursor % _ring_nodes.size()]
	_ring_cursor += 1
	_reset_fx_node(node, color, 0.9)
	return node


func _take_disc(color: Color) -> MeshInstance3D:
	var node := _disc_nodes[_disc_cursor % _disc_nodes.size()]
	_disc_cursor += 1
	_reset_fx_node(node, color, 0.85)
	return node


func _take_beam(color: Color) -> MeshInstance3D:
	var node := _beam_nodes[_beam_cursor % _beam_nodes.size()]
	_beam_cursor += 1
	_reset_fx_node(node, color)
	return node


# ---------------------------------------------------------------- forms
## `bolt/orb/homing/barrage/boomerang/wave/drain` all use the web's
## `draw + hit + trail` shape: a tinted projectile that flies to the target.
func _fx_projectile(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var dur := clampf(from.distance_to(to) / 16.0, 0.12, 0.34)
	_spawn_spark(from + Vector3(0.0, 0.1, 0.0), Vector3.ZERO, 0.14, 1.6, color)
	var node := _take_proj(color)
	node.position = from
	node.scale = Vector3.ONE * 0.75
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "position", to, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(node, "scale", Vector3.ONE * 1.3, dur)
	tw.tween_callback(_impact_and_hide.bind(node, to, ev, color, false))


## `strike()` in the web: `uh()` @429777 lays two sine-offset chains of beam
## segments from the caster to the target (vine-whip calls it with a mirrored,
## shorter second arc), then a twinkle and a ring of particles at the target.
func _fx_melee(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var d := to - from
	if d.length() < 0.05:
		_fx_impact(to, ev, color, false)
		return
	var side := Vector3(-d.z, 0.0, d.x).normalized()
	for arc in [1.0, -0.6]:
		var prev := from
		for i in range(1, 9):
			var t := float(i) / 8.0
			var off := sin(t * PI) * float(arc)
			var p: Vector3 = from.lerp(to, t) + side * off \
				+ Vector3(0.0, sin(t * PI) * 0.25, 0.0)
			_spawn_beam(prev, p, color, 0.34 * (1.0 - t * 0.35), 0.15)
			prev = p
	_spawn_spark(to + Vector3(0.0, 0.2, 0.0), Vector3.ZERO, 0.16, 2.4,
		color.lightened(0.55))
	var tw := create_tween()
	tw.tween_interval(0.14)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `dash()` in the web (@446737 quick-attack): five short pale streaks straddling
## the charge line, then a twinkle flare at the target.
func _fx_dash(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var dir := to - from
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	var tint := color.lightened(0.55)
	for i in 5:
		var a: Vector3 = from + flat * randf_range(-0.4, 2.0) \
			+ side * randf_range(-0.9, 0.9) + Vector3(0.0, randf_range(0.2, 1.4), 0.0)
		_spawn_beam(a, a + flat * 1.0, tint, 0.18, 0.16)
	_spawn_spark(to + Vector3(0.0, 0.4, 0.0), Vector3.ZERO, 0.18, 3.0,
		color.lightened(0.8))
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `nova()` in the web: an expanding ring + dust around the caster.
func _fx_nova(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	_spawn_disc(_ground(from.x, from.z) + Vector3(0.0, 0.06, 0.0), color, 1.4, 0.4)
	_spawn_ring(from + Vector3(0.0, 0.4, 0.0), color, 1.4)
	for i in 10:
		var ang := float(i) / 10.0 * TAU
		var dir := Vector3(cos(ang), randf_range(0.1, 0.5), sin(ang))
		_spawn_spark(from + Vector3(0.0, 0.3, 0.0), dir * 1.6, 0.22, 1.0, color)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `sky + warn` in the web: telegraph disc, then something falls from above.
func _fx_sky(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var to: Vector3 = pts[1]
	_spawn_disc(_ground(to.x, to.z) + Vector3(0.0, 0.06, 0.0), color, 1.0, 0.34)
	var node := _take_proj(color)
	node.position = _ground(to.x, to.z) + Vector3(0.0, 14.0, 0.0)
	node.scale = Vector3.ONE * 0.9
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "position", to, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact_and_hide.bind(node, to, ev, color, true))


## `beam()` in the web (`fh()` @430519): one full-length coloured strip plus a
## half-length core mixed 50 % toward white, so the beam reads even when its
## element colour matches the terrain.
func _fx_beam(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	_spawn_beam(from + Vector3(0.0, 0.1, 0.0), to, color, 0.95, 0.2)
	_spawn_beam(from + Vector3(0.0, 0.1, 0.0), from.lerp(to, 0.55),
		color.lerp(Color.WHITE, 0.5), 0.42, 0.18)
	_spawn_ring(from + Vector3(0.0, 0.3, 0.0), color, 0.9)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `cone()` in the web: a spread of particles from the caster towards the target.
func _fx_cone(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	for i in 12:
		var spread := randf_range(-0.55, 0.55)
		var d := (dir + side * spread).normalized()
		var dist := from.distance_to(to) * randf_range(0.55, 0.95)
		_spawn_spark(from + Vector3(0.0, 0.3, 0.0), d * dist,
			randf_range(0.16, 0.3), randf_range(0.8, 1.3), color)
	var tw := create_tween()
	tw.tween_interval(0.14)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `orbit()` in the web: shapes circling the caster once.
func _fx_orbit(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	for i in 4:
		var ang := float(i) / 4.0 * TAU
		_spawn_spark(from + Vector3(cos(ang) * 1.6, 0.9, sin(ang) * 1.6),
			Vector3(0.0, 0.2, 0.0), 0.26, 1.2, color)
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `link()` in the web: zigzag segments between caster and target.
func _fx_link(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var prev := from
	for i in range(1, 5):
		var t := float(i) / 4.0
		var p: Vector3 = from.lerp(to, t) + Vector3(
			randf_range(-0.7, 0.7), randf_range(-0.4, 0.6), randf_range(-0.7, 0.7))
		_spawn_beam(prev, p, color, 0.28, 0.12)
		prev = p
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(func() -> void: _fx_impact(to, ev, color, false))


## `cast()` / `aura()` in the web: a ring on the caster (buffs, weather, charge).
func _fx_aura(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	_spawn_ring(from + Vector3(0.0, 0.6, 0.0), color, 1.1)
	_spawn_disc(_ground(from.x, from.z) + Vector3(0.0, 0.06, 0.0), color, 1.0, 0.45)
	for i in 6:
		var ang := float(i) / 6.0 * TAU
		_spawn_spark(from + Vector3(cos(ang) * 1.0, 0.2, sin(ang) * 1.0),
			Vector3(0.0, 1.2, 0.0), 0.45, 0.9, color)


## `zone()` in the web: a ground patch where the move lands.
func _fx_zone(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var to: Vector3 = pts[1]
	var g := _ground(to.x, to.z)
	_spawn_disc(g + Vector3(0.0, 0.06, 0.0), color, 1.5, 0.5)
	_spawn_ring(g + Vector3(0.0, 0.1, 0.0), color, 0.8)


## `boom + draw + trail` in the web: a lobbed projectile that explodes on arrival.
func _fx_boom(ev: Dictionary, color: Color) -> void:
	var pts := _fx_points(ev)
	var from: Vector3 = pts[0]
	var to: Vector3 = pts[1]
	var dur := clampf(from.distance_to(to) / 18.0, 0.18, 0.42)
	var mid: Vector3 = (from + to) * 0.5 + Vector3(0.0, 1.8, 0.0)
	var node := _take_proj(color)
	node.position = from
	node.scale = Vector3.ONE * 0.7
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "position", mid, dur * 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", to, dur * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(node, "scale", Vector3.ONE * 1.25, dur)
	tw.tween_callback(_impact_and_hide.bind(node, to, ev, color, true))


# ------------------------------------------------------------- primitives
func _impact_and_hide(node: MeshInstance3D, at: Vector3, ev: Dictionary,
		color: Color, strong: bool) -> void:
	node.visible = false
	_fx_impact(at, ev, color, strong)


func _fx_impact(at: Vector3, ev: Dictionary, color: Color, strong: bool) -> void:
	var count := 14 if strong else 10
	for i in count:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.15, 1.2),
			randf_range(-1.0, 1.0)).normalized()
		_spawn_spark(at + Vector3(0.0, 0.25, 0.0), dir * randf_range(0.9, 2.2),
			randf_range(0.26, 0.46), 1.0, color)
	_spawn_spark(at, Vector3.UP * 0.35, 0.24, 2.8 if strong else 2.2, color.lightened(0.55))
	_spawn_ring(Vector3(at.x, at.y + 0.2, at.z), color, 1.0)
	_spawn_disc(_ground(at.x, at.z) + Vector3(0.0, 0.06, 0.0), color, 1.0, 0.34)
	if _fx == null:
		return
	var dmg := float(ev.get("dmg", 0.0))
	if dmg <= 0.0:
		return
	var crit := bool(ev.get("crit", false))
	_fx.spawn_floater(UI.fmt_num(dmg),
		Color(1.0, 0.85, 0.3) if crit else Color(1.0, 0.97, 0.9),
		_world_screen_point(Vector3(at.x, at.y + 1.0, at.z)))


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, _ground_y(x, z), z)


func _spawn_ring(at: Vector3, color: Color, size_mul := 1.0) -> void:
	var node := _take_ring(color)
	node.position = at
	node.scale = Vector3.ONE * 0.6 * size_mul
	var mat := node.material_override as StandardMaterial3D
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "scale", Vector3.ONE * 3.6 * size_mul, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if mat != null:
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(func() -> void: node.visible = false)


## Flat ring that expands across the ground (impact/nova/telegraph).
func _spawn_disc(at: Vector3, color: Color, size_mul: float, life: float) -> void:
	var node := _take_disc(color)
	node.position = at
	node.scale = Vector3.ONE * 0.5 * size_mul
	var mat := node.material_override as StandardMaterial3D
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "scale", Vector3.ONE * 3.0 * size_mul, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if mat != null:
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(func() -> void: node.visible = false)


## Additive ribbon stretched between two world points, facing the camera.
func _spawn_beam(a: Vector3, b: Vector3, color: Color, width: float, life: float) -> void:
	var node := _take_beam(color)
	var d := b - a
	var length := d.length()
	if length < 0.001:
		node.visible = false
		return
	var fwd := d / length
	var cam := Vector3.UP
	if _camera != null and _camera.is_inside_tree():
		cam = _camera.global_position - (a + b) * 0.5
	var up := cam.cross(fwd)
	if up.length() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var right := fwd.cross(up).normalized()
	node.transform = Transform3D(Basis(fwd, up, right), (a + b) * 0.5)
	node.scale = Vector3(length, width, 1.0)
	var mat := node.material_override as StandardMaterial3D
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	if mat != null:
		tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.parallel().tween_property(node, "scale:y", width * 0.3, life)
	tw.tween_callback(func() -> void: node.visible = false)


func _spawn_spark(at: Vector3, offset: Vector3, life: float, size_mul: float,
		color: Color) -> void:
	var node := _take_spark(color)
	node.position = at
	node.scale = Vector3.ONE * size_mul * 0.5
	var mat := node.material_override as StandardMaterial3D
	var tw := node.create_tween()
	node.set_meta("fx_tween", tw)
	tw.tween_property(node, "position", at + offset, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "scale", Vector3.ONE * size_mul * 0.1, life)
	if mat != null:
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(func() -> void: node.visible = false)


func _process(delta: float) -> void:
	if _run.is_empty():
		return
	_sync_mouse_capture()
	if _hud != null:
		# The radar rotates with the camera, like the web minimap (bundle @2160976).
		_hud.cam_yaw = _cam_yaw
	_time += delta
	var dt := minf(delta, 1.0 / 15.0)
	# The level-up window is state-driven, not a self-closing popup: once the run
	# leaves "modal" (card picked / skipped / banished) the scrim must leave with
	# it. Leaving it visible kept a mouse_filter STOP Control over the whole run
	# and kept the stale .card.offer row clickable -- the "next level-up won't
	# respond" report. Always tear it down, then rebuild from current offers.
	if str(_run.get("state", "play")) != "modal":
		_close_modal()
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
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	if not _py_ready:
		# First playable frame after the terrain exists: start standing on the height field.
		_player_py = _ground_y(px, pz)
		_player_vy = 0.0
		_grounded = true
		_py_ready = true
	_slide_cd = maxf(0.0, _slide_cd - dt)
	_slam_cd = maxf(0.0, _slam_cd - dt)
	var dir := _input_vector()
	# Gravity runs every frame, airborne or not (bundle @870247 `vel.y -= db*e`, db = 30).
	_player_vy -= GRAVITY * dt
	# While diving the web pins `vel.y = Math.min(vel.y, -34)` every frame (@870600).
	if _diving:
		_player_vy = minf(_player_vy, -DIVE_FALL_SPEED)
	var blocked := false
	var speed := BASE_SPEED * float(PbJson.as_dict(player.get("stats", {})).get("moveSpeed", 1.0)) \
		* float(player.get("hazardSlow", 1.0))
	var wx := 0.0
	var wz := 0.0
	var moving := false
	if _slide_t > 0.0:
		# Slide: the web skips its acceleration branch and decays the captured
		# velocity by exp(-2.2*dt) each frame (@868273), so input is ignored.
		_slide_t = maxf(0.0, _slide_t - dt)
		_slide_speed *= exp(-SLIDE_DECAY * dt)
		speed = _slide_speed
		wx = _slide_dir.x
		wz = _slide_dir.y
		moving = true
	elif dir != Vector2.ZERO:
		# Camera-relative WASD, matching the web: forward = away from the camera,
		# right = camera right (bundle @866266).
		wx = sin(_cam_yaw) * dir.y + cos(_cam_yaw) * dir.x
		wz = cos(_cam_yaw) * dir.y - sin(_cam_yaw) * dir.x
		moving = true
		if _diving:
			# `vel.x *= .35; vel.z *= .35` at dive start (@868067).
			speed *= DIVE_HORIZONTAL
	if moving:
		var dx := wx * speed * dt
		var dz := wz * speed * dt
		# Prop colliders + the web's step/slope probe (`ie`, @871154): a move axis is refused
		# when the surface `radius*0.8` ahead is more than 0.6 above the feet. Resolve each
		# axis separately so a diagonal move slides along the free one.
		if _terrain == null:
			player["x"] = px + dx
			player["z"] = pz + dz
		else:
			var cx := px
			var cz := pz
			if not _step_blocked(cx + dx, cz, dx, 0.0) \
					and not _terrain.hit_prop(cx + dx, cz, _player_py, PLAYER_RADIUS):
				player["x"] = cx + dx
			else:
				blocked = true
				_slide_dir.x = 0.0
			cx = float(player.get("x", 0.0))
			if not _step_blocked(cx, cz + dz, 0.0, dz) \
					and not _terrain.hit_prop(cx, cz + dz, _player_py, PLAYER_RADIUS):
				player["z"] = cz + dz
			else:
				blocked = true
				_slide_dir.y = 0.0
		# PMD sheets store 8 rows clockwise from "down/front": row 0 faces +z
		# (towards the start camera), row 2 faces +x, row 4 faces -z, row 6 -x.
		player["facing"] = posmod(roundi(atan2(wx, wz) / (PI / 4.0)), 8)
	# A slide cancelled on both axes (wall/steep slope) ends instead of idling.
	if _slide_t > 0.0 and _slide_dir == Vector2.ZERO:
		_slide_t = 0.0
	# Fighting/bug/ghost types climb a blocked step by lifting off (bundle @871154).
	if blocked:
		var types := PbJson.as_array(player.get("types", []))
		for t in CLIMB_TYPES:
			if types.has(t):
				_player_vy = maxf(_player_vy, 7.5)
				break
	var lim := _terrain.walk_lim() if _terrain != null else ARENA_SIZE * 0.5 - 2.0
	player["x"] = clampf(float(player.get("x", 0.0)), -lim, lim)
	player["z"] = clampf(float(player.get("z", 0.0)), -lim, lim)
	# Vertical integration + ground contact (@873494): land when the feet reach the surface,
	# snap down small drops while grounded, and only leave the ground when clearly airborne.
	_player_py += _player_vy * dt
	# `apex` is the highest point of the current airtime; the slam fall uses it.
	_apex = _player_py if _grounded else maxf(_apex, _player_py)
	var floor_y := _ground_y(float(player.get("x", 0.0)), float(player.get("z", 0.0)))
	if _player_py <= floor_y:
		_player_py = floor_y
		if _player_vy < 0.0:
			_player_vy = 0.0
		if _diving:
			_settle_dive(floor_y)
		_grounded = true
		_jumps_left = _extra_jumps(player)
	elif _grounded and _player_vy <= 0.0 and _player_py - floor_y < GROUND_SNAP:
		_player_py = floor_y
		_player_vy = 0.0
	elif _player_py > floor_y + 0.25:
		_grounded = false
	elif _player_vy <= 0.0:
		_player_py = floor_y
		_grounded = true


## Shift landing from a dive: `slam(groundY, apex-groundY)` (@855540), with the
## 2 s `mb` cooldown suppressing damage but still playing the land feedback.
func _settle_dive(floor_y: float) -> void:
	_diving = false
	var fall := maxf(0.0, _apex - floor_y)
	var o := clampf(fall / 8.0, 0.0, 1.0)
	if _slam_cd > 0.0:
		Audio.sfx("hit")
		return
	_slam_cd = SLAM_CD
	var player: Dictionary = _run["player"]
	PbRun.player_slam(_run, float(player.get("x", 0.0)), float(player.get("z", 0.0)), fall)
	Audio.sfx("hit")
	_trauma = minf(1.0, _trauma + 0.14 + 0.26 * o)


## Shift (@867905): airborne = dive, grounded = 0.55 s slide at 1.9x.
func _try_dash() -> void:
	if not _py_ready:
		return
	var player: Dictionary = _run["player"]
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	# Dive needs the feet more than 1.2 above the surface; input is not required.
	if not _grounded and not _diving and _player_py - _ground_y(px, pz) > DIVE_MIN_HEIGHT:
		_diving = true
		_player_vy = -DIVE_FALL_SPEED
		Audio.sfx("hit")
		return
	# Slide needs movement input (`x>0`) and `slideCd<=0` (@868273).
	if _grounded and _slide_cd <= 0.0:
		var dir := _input_vector()
		if dir == Vector2.ZERO:
			return
		var stats := PbJson.as_dict(player.get("stats", {}))
		var speed := BASE_SPEED * float(stats.get("moveSpeed", 1.0)) \
			* float(player.get("hazardSlow", 1.0))
		_slide_dir = Vector2(sin(_cam_yaw) * dir.y + cos(_cam_yaw) * dir.x,
			cos(_cam_yaw) * dir.y - sin(_cam_yaw) * dir.x).normalized()
		_slide_speed = speed * SLIDE_MUL
		_slide_t = SLIDE_TIME
		_slide_cd = SLIDE_CD


func _input_vector() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO


## The web's `ie(x,z,dx,dz)`: refuse an axis when the surface under the target position, or
## `radius*0.8` further along that axis, sits more than 0.6 above the actor's feet.
func _step_blocked(x: float, z: float, dx: float, dz: float) -> bool:
	if _terrain == null:
		return false
	var ceiling := _player_py + STEP_LIMIT
	if _terrain.height(x, z) > ceiling:
		return true
	var probe_x := x + signf(dx) * PROBE_DIST
	var probe_z := z + signf(dz) * PROBE_DIST
	return _terrain.height(probe_x, probe_z) > ceiling


func _extra_jumps(player: Dictionary) -> int:
	var stats := PbJson.as_dict(player.get("stats", {}))
	return maxi(0, int(floorf(PbJson.as_float(stats.get("extraJumps", 0.0), 0.0))))


## Space: `vel.y = 11*sqrt(jumpHeight)`, then `extraJumps` mid-air jumps at 0.92x (@870202).
func _try_jump() -> void:
	if not _py_ready:
		return
	var player: Dictionary = _run["player"]
	var stats := PbJson.as_dict(player.get("stats", {}))
	var jump_h := maxf(0.05, PbJson.as_float(stats.get("jumpHeight", 1.0), 1.0))
	var speed := JUMP_SPEED * sqrt(jump_h)
	if _grounded:
		_player_vy = speed
		_grounded = false
		_jumps_left = _extra_jumps(player)
	elif _jumps_left > 0:
		_jumps_left -= 1
		_player_vy = speed * 0.92
	else:
		return


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
		KEY_SPACE:
			# re keymap: jump = Space (bundle @870202 `n.hit('Space')`).
			if not modal and not _paused and not over:
				_try_jump()
		KEY_SHIFT, KEY_CTRL:
			# re keymap: dash = ShiftLeft (`ga.dash` @7387; ShiftRight/ControlLeft
			# accepted at @867905). Ground = slide, air = dive, no stamina.
			if not modal and not _paused and not over:
				_try_dash()
		KEY_E:
			# re keymap: capture throw = KeyE (kS.tryThrow/throwBall @1082671).
			# Interactables share the key: portal > guardian altar > Meowth shop,
			# matching the web's `nearest` priority (@1310201).
			if not modal and not _paused and not over:
				if PbRun.portal_near(_run):
					_enter_portal()
				elif PbRun.altar_near(_run):
					_wake_guardian()
				elif PbRun.meowth_near(_run):
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
			_hud.show_banner(App.ui("Fase {n}", {"n": n}), "穿过传送门进入下一阶段", "#ff5a5f")
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
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var py := _player_py if _py_ready else _ground_y(px, pz)
	return _world_screen_point(Vector3(px, py + 1.2, pz))


func _world_screen_point(pos: Vector3) -> Vector2:
	var viewport := get_viewport().get_visible_rect().size
	if _camera == null or not _camera.is_inside_tree():
		return viewport * Vector2(0.5, 0.55)
	var p := _camera.unproject_position(pos)
	return Vector2(clampf(p.x, 40.0, viewport.x - 40.0), clampf(p.y, 60.0, viewport.y - 60.0))


func _render(dt: float) -> void:
	var player: Dictionary = _run.get("player", {})
	var px := float(player.get("x", 0.0))
	var pz := float(player.get("z", 0.0))
	var py := _player_py if _py_ready else _ground_y(px, pz)
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
	# orbiting the player on the mouse-driven yaw. The web lerps its camera target
	# towards the player at rate 10 (@1561868 `camTarget.y = nl(..., r.y, 10, e)`),
	# which keeps jumps readable instead of snapping the boom every frame.
	if not _cam_follow_ready:
		_cam_follow_y = py
		_cam_follow_ready = true
	else:
		_cam_follow_y += (py - _cam_follow_y) * (1.0 - exp(-10.0 * maxf(dt, 0.0001)))
	var cos_pitch := cos(pitch)
	# Keep the boom above the height field even at the -0.25 pitch clamp.
	var cam_y := maxf(_cam_follow_y + sin(pitch) * dist, _cam_follow_y + 0.4)
	_camera.position = Vector3(
		px + sin(_cam_yaw) * cos_pitch * dist,
		cam_y,
		pz + cos(_cam_yaw) * cos_pitch * dist) + shake_offset
	_camera.look_at(Vector3(px + shake_offset.x * 0.3, _cam_follow_y + 1.0,
		pz + shake_offset.z * 0.3), Vector3.UP)

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

	# Altar (@1303414) and portal (@1529103): the altar glows until the guardian
	# is awake (web dims it on use); the portal only exists after the kill.
	var altar_here := PbRun.altar_present(_run)
	_altar_node.visible = altar_here
	if altar_here:
		var ax := float(_run.get("altarX", 0.0))
		var az := float(_run.get("altarZ", 0.0))
		_altar_node.position = Vector3(ax, _ground_y(ax, az), az)
		var awake := PbRun.altar_used(_run)
		_altar_light.visible = not awake
		if not awake:
			_altar_light.light_energy = 1.5 + sin(_time * 2.4) * 0.35
	var portal_here := PbRun.portal_open(_run)
	_portal_node.visible = portal_here
	if portal_here:
		var ox := float(_run.get("portalX", 0.0))
		var oz := float(_run.get("portalZ", 0.0))
		_portal_node.position = Vector3(ox, _ground_y(ox, oz), oz)
		_portal_light.light_energy = 1.2 + sin(_time * 3.0) * 0.3

	# Meowth NPC + `[E]` prompt. The prompt hides while a modal/shop is open.
	var meowth_here := PbRun.meowth_present(_run)
	_meowth_node.visible = meowth_here
	if meowth_here:
		var mx := float(_run.get("meowthX", 0.0))
		var mz := float(_run.get("meowthZ", 0.0))
		_meowth_node.position = Vector3(mx, _ground_y(mx, mz) + _meowth_lift
			+ sin(_time * 2.0) * 0.08, mz)
	var play_state := str(_run.get("state", "play")) == "play"
	var prompt_text := ""
	if portal_here and PbRun.portal_near(_run):
		prompt_text = "[E] " + App.ui(PbRun.portal_prompt(_run))
	elif altar_here and PbRun.altar_near(_run):
		prompt_text = "[E] " + App.ui(PbRun.altar_prompt(_run))
	elif meowth_here and PbRun.meowth_near(_run):
		prompt_text = "[E] " + App.ui("Tienda de Meowth")
	var prompt_on := prompt_text != "" and not _shop_open \
		and not _paused and play_state and not _modal_scrim.visible \
		and not _settle_scrim.visible
	_prompt.visible = prompt_on
	if prompt_on:
		_prompt.text = prompt_text
	_sync_fx_events()


# ------------------------------------------------------------------ modals
## Tear the level-up window down and forget its cached token, so the next
## open_offers() always rebuilds a fresh .card.offer row from the current
## `offers` array (never a stale, unclickable one).
func _close_modal() -> void:
	if _modal_state == "" and not _modal_scrim.visible:
		return
	_modal_scrim.visible = false
	_modal_state = ""
	_banish_mode = false
	_banish_pick = -1
	for c in _modal_cards.get_children():
		c.queue_free()
	for c in _modal_actions.get_children():
		c.queue_free()
	for c in _modal_mini.get_children():
		c.queue_free()


## showLevelUp() parity (bundle @2173200): h1 + .cards of .card.offer + the
## reroll/skip/banish actions + buildMini current-move row.
func _update_modal() -> void:
	if str(_run.get("state", "play")) != "modal":
		_close_modal()
		return
	# Counters are part of the token: reroll/skip/banish rebuild the row.
	var token := "offers:%d:%d:%d:%d" % [
		int(_run.get("pendingLevels", 0)), int(_run.get("rerolls", 0)),
		int(_run.get("skips", 0)), int(_run.get("banishes", 0))]
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
	panel.add_theme_stylebox_override("panel", s)
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
