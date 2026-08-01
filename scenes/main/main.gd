extends Node2D
## Orchestrates the run: builds the arena/fortress/players in code, owns the
## state machine (menu → waves/intermissions → results), and exposes the
## actions the shop can buy.
##
## Multiplayer model: the HOST (peer 1) simulates everything — enemies, waves,
## damage, economy. Clients simulate only their own tank's movement (broadcast
## to everyone at 20 Hz) and render the rest from host snapshots (~12 Hz,
## unreliable) plus reliable one-shot events (spawns, deaths, shots, shop and
## level-up flow). All net RPCs live on this node ("/root/Main") and on the
## autoloads, so node paths always match across peers.

enum State { MENU, WAVE, INTERMISSION, GAME_OVER, VICTORY }

const WALL_SLOTS := 8
const GAP_SLOTS: Array = [2, 5]
const INTERMISSION_TIME := 30.0
const PULL_TIME := 1.5  # length of the end-of-group resource sweep before the shop
const PICKUP_MERGE_RADIUS := 46.0  # gold dropped this close to a coin merges into it
const FINAL_WAVE := WaveData.FINAL_WAVE
const TURRET_OFFSET := Vector2(46, 0)  # "just ahead" = toward the enemy side
const SNAPSHOT_INTERVAL := 0.08

# Landscape layout, derived from the viewport: enemies stream in from the
# RIGHT, the fortress wall is a vertical line at ~21% width, core at far left.
var arena_w: float
var arena_h: float
var wall_x: float
var core_pos: Vector2

var state: State = State.MENU
var wave_index: int = -1
var intermission_left: float = 0.0
var tower_kits: Array = []  # tower type keys bought in the shop, deployed with E

var player: Player          # THIS peer's tank
var players: Dictionary = {}  # peer_id -> Player (all tanks, every peer)
var core: FortressCore
var walls: Array = []
var wave_manager: WaveManager
var hud: Hud
var menu: Menu
var pause_menu: PauseMenu
var entity_layer: Node2D

# Networked entity registries (host: authoritative nodes; client: puppets).
var _enemies: Dictionary = {}
var _turrets: Dictionary = {}
var _pickups: Dictionary = {}
var _next_net_id: int = 1
var _snap_accum: float = 0.0

# Group level-up coordination (host).
var _lv_active := false
var _lv_done: Dictionary = {}

# MP smoke test bookkeeping.
var _smoke_mp := ""
var _smoke_snaps := 0

func _ready() -> void:
	Game.reset()
	Net.game = self
	arena_w = get_viewport_rect().size.x
	arena_h = get_viewport_rect().size.y
	wall_x = arena_w * 0.215
	core_pos = Vector2(arena_w * 0.08, arena_h / 2.0)
	_build_camera()
	_build_background()
	_build_bounds()

	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	add_child(entity_layer)
	Fx.world = entity_layer

	_build_fortress()
	# players are created in begin_run once tank classes are chosen

	wave_manager = WaveManager.new()
	wave_manager.arena = entity_layer
	wave_manager.main = self
	wave_manager.wall_line_x = wall_x
	wave_manager.gap_ys = _gap_positions()
	wave_manager.core = core
	wave_manager.spawn_edge_x = arena_w
	wave_manager.spawn_y_min = 40.0
	wave_manager.spawn_y_max = arena_h - 40.0
	add_child(wave_manager)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	menu = Menu.new()
	menu.main = self
	add_child(menu)

	pause_menu = PauseMenu.new()
	pause_menu.main = self
	add_child(pause_menu)

	Net.game_starting.connect(_on_net_game_starting)

	get_tree().paused = true

	# Headless smoke testing: `godot --headless --quit-after N -- --smoke`
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		start_solo.call_deferred("assault")
		_smoke_extras.call_deferred()
	elif "--mp-host" in args:
		_smoke_mp = "host"
		_mp_smoke_host.call_deferred()
	elif "--mp-join" in args:
		_smoke_mp = "join"
		_mp_smoke_join.call_deferred()

func _exit_tree() -> void:
	if Net.game == self:
		Net.game = null

## Spawns one of every tower and enemy type so a headless run exercises all
## combat code paths (ranged enemies, AoE, flame cones), not just wave 1.
func _smoke_extras() -> void:
	var i := 0
	for key in TowerData.TYPES:
		place_turret_at(key, Vector2(wall_x + 150.0, 70.0 + 115.0 * i), player)
		i += 1
	var j := 0
	for key in EnemyData.TYPES:
		var e := Enemy.new()
		e.setup(key, wall_x, _gap_positions(), core)
		e.position = Vector2(arena_w + 50.0, 40.0 + 70.0 * j)
		entity_layer.add_child(e)
		host_register_enemy(e)
		j += 1

func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(arena_w / 2.0, arena_h / 2.0)
	add_child(cam)
	cam.make_current()
	Fx.camera = cam

func _build_background() -> void:
	# Plain terrain art (no fortification baked in) covers the viewport — the
	# fortress itself is drawn by WallSegment/FortressCore. The sand art is
	# portrait, so it's rotated 90° to map naturally onto the landscape arena.
	var sprite := Sprite2D.new()
	var tex: Texture2D = load("res://assets/Desert_sand.jpeg")
	sprite.texture = tex
	sprite.rotation = PI / 2.0
	sprite.position = Vector2(arena_w / 2.0, arena_h / 2.0)
	sprite.scale = Vector2(arena_h / tex.get_width(), arena_w / tex.get_height())
	sprite.z_index = -10
	add_child(sprite)
	# Darkened courtyard so inside-the-walls still reads against open ground.
	_add_bg_rect(Rect2(0, 0, wall_x - 18, arena_h), Color(0.12, 0.1, 0.08, 0.3))
	# Faint red tint marking the enemy spawn strip.
	_add_bg_rect(Rect2(arena_w - 40, 0, 40, arena_h), Color(0.3, 0.1, 0.1, 0.25))

func _add_bg_rect(rect: Rect2, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.end,
		rect.position + Vector2(0, rect.size.y),
	])
	poly.color = color
	poly.z_index = -10
	add_child(poly)

func _build_bounds() -> void:
	# Top/bottom extend 400 past the right edge so off-screen enemies stay in lane.
	_add_static_box(Rect2(-40, -40, arena_w + 440, 40), 1 << 0)
	_add_static_box(Rect2(-40, arena_h, arena_w + 440, 40), 1 << 0)
	_add_static_box(Rect2(-40, -40, 40, arena_h + 80), 1 << 0)
	# Right strip only blocks players, so enemies can drive in from off-screen.
	_add_static_box(Rect2(arena_w - 20, -40, 30, arena_h + 80), 1 << 5)

func _add_static_box(rect: Rect2, layer: int) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = rect.size
	shape.shape = rs
	body.add_child(shape)
	add_child(body)

const WALL_MARGIN := 10.0

func _build_fortress() -> void:
	var slot_h := (arena_h - WALL_MARGIN * 2.0) / WALL_SLOTS
	for i in range(WALL_SLOTS):
		if i in GAP_SLOTS:
			continue
		var wall := WallSegment.new()
		wall.seg_size = Vector2(36.0, slot_h - 4.0)
		wall.position = Vector2(wall_x, WALL_MARGIN + slot_h * (i + 0.5))
		entity_layer.add_child(wall)
		walls.append(wall)
	core = FortressCore.new()
	core.position = core_pos
	entity_layer.add_child(core)
	core.core_destroyed.connect(_on_core_destroyed)

func _gap_positions() -> Array:
	var slot_h := (arena_h - WALL_MARGIN * 2.0) / WALL_SLOTS
	var arr: Array = []
	for i in GAP_SLOTS:
		arr.append(WALL_MARGIN + slot_h * (i + 0.5))
	return arr

func _process(delta: float) -> void:
	if state == State.INTERMISSION:
		if Net.is_authority():
			intermission_left -= delta
			if intermission_left <= 0.0:
				_start_wave(wave_index + 1)
		else:
			intermission_left -= delta  # local tick between snapshot corrections
		hud.set_countdown(intermission_left)
	# Real-time tower deployment: E drops the next bought kit at your position.
	if state == State.WAVE or state == State.INTERMISSION:
		if player != null and is_instance_valid(player) and player.hp > 0.0 \
				and Input.is_action_just_pressed("interact") and not tower_kits.is_empty():
			if Net.active() and not Net.is_authority():
				rpc_id(1, &"srv_deploy")
			else:
				_try_deploy(player)
	# Group level-up: host pauses everyone and waits for all picks (HUD overlay
	# opens from Game.pending_picks on each peer).
	if Net.hosting() and (state == State.WAVE or state == State.INTERMISSION):
		if Game.pending_picks > 0 and not _lv_active:
			_lv_active = true
			_lv_done = {}
			rpc(&"cl_levelup", Game.pending_picks)
			get_tree().paused = true

func _physics_process(delta: float) -> void:
	if Net.hosting() and (state == State.WAVE or state == State.INTERMISSION):
		_snap_accum += delta
		if _snap_accum >= SNAPSHOT_INTERVAL:
			_snap_accum = 0.0
			_broadcast_snapshot()

func _try_deploy(who: Player) -> void:
	if tower_kits.is_empty() or who == null or not is_instance_valid(who):
		return
	var pos := who.global_position + TURRET_OFFSET
	if can_place_at(pos):
		place_turret_at(tower_kits.pop_front(), pos, who)
		Sfx.play("buy", 0.0)
	else:
		Sfx.play("deny", 0.0)
		Fx.float_text(who.global_position, "Can't deploy here!", Color(1, 0.5, 0.4))

# --- Run flow ---

func start_solo(tank_class: String) -> void:
	begin_run({1: tank_class})

func _on_net_game_starting() -> void:
	var classes: Dictionary = {}
	for pid in Net.roster:
		classes[pid] = Net.roster[pid].tank
	begin_run(classes)

## classes: peer_id -> tank class key. Every peer builds the same set of tanks;
## each simulates its own and puppets the rest.
func begin_run(classes: Dictionary) -> void:
	Audio.stop_music()  # menu theme ends when the fighting starts
	Game.reset()
	var pids := classes.keys()
	pids.sort()
	for i in range(pids.size()):
		var pid: int = pids[i]
		var p := Player.new()
		p.peer_id = pid
		p.name = "P%d" % pid
		p.setup(classes[pid])
		p.position = Vector2(arena_w * 0.14, arena_h * 0.5 + 64.0 * (i - (pids.size() - 1) / 2.0))
		p.rotation = PI / 2.0  # face the oncoming wave
		entity_layer.add_child(p)
		players[pid] = p
		p.died.connect(_on_player_died)
	player = players.get(Net.my_id())
	get_tree().paused = false
	menu.close()
	hud.set_wave_label(1, FINAL_WAVE)
	if Net.is_authority():
		_start_wave(0)

func _start_wave(index: int) -> void:
	wave_index = index
	state = State.WAVE
	if Net.hosting():
		rpc(&"cl_wave", index)
	_show_wave_start(index)
	get_tree().create_timer(2.0).timeout.connect(func():
		if state == State.WAVE:
			wave_manager.start_wave(index))

func _show_wave_start(index: int) -> void:
	hud.close_shop()
	hud.set_wave_label(index + 1, FINAL_WAVE)
	hud.show_message("WAVE %d INCOMING" % (index + 1), 1.8)
	Sfx.play("wave_start", 0.0)

func request_start_wave() -> void:
	if state == State.INTERMISSION and Net.is_authority():
		_start_wave(wave_index + 1)

func _on_wave_cleared(index: int) -> void:
	Game.waves_survived = index + 1
	var bonus := WaveData.wave_clear_bonus(index)
	Game.add_money(bonus)
	Fx.float_text(Vector2(arena_w / 2.0 - 40, arena_h * 0.4), "Wave clear +$%d" % bonus, Color(1, 0.9, 0.4))
	var group_end := (index + 1) >= FINAL_WAVE or (index + 1) % WaveData.GROUP_SIZE == 0
	if not group_end:
		# Mid-group: bank XP so leveling is never lost, but LEAVE gold on the
		# ground -- players earn it by driving out into the field to grab it.
		for p in get_tree().get_nodes_in_group("pickups"):
			if p.kind == "xp":
				p.vacuum = true
		# Roll straight into the next wave (its 2 s warning is the breather).
		_start_wave(index + 1)
		return

	# End of a 10-wave group (or the final wave): physically sweep EVERYTHING
	# still on the field to the players, then open the shop / end once it lands.
	for p in get_tree().get_nodes_in_group("pickups"):
		p.vacuum = true
	if index + 1 >= FINAL_WAVE:
		get_tree().create_timer(PULL_TIME).timeout.connect(func(): _end_run(true))
	else:
		get_tree().create_timer(PULL_TIME).timeout.connect(_open_group_shop)

## Opens the intermission shop after the end-of-group resource sweep has played.
func _open_group_shop() -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return
	state = State.INTERMISSION
	intermission_left = INTERMISSION_TIME
	hud.open_shop()
	if Net.hosting():
		rpc(&"cl_shop_open", hud.shop.cards(), hud.shop.rerolls())

func _on_player_died() -> void:
	# Co-op rule: the run only ends when EVERY tank is down (or the core pops).
	for pid in players:
		var p: Player = players[pid]
		if is_instance_valid(p) and p.hp > 0.0:
			return
	_end_run(false)

func _on_core_destroyed() -> void:
	_end_run(false)

func _end_run(victory: bool) -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return
	if Net.hosting():
		rpc(&"cl_run_end", victory)
	_apply_run_end(victory)

func _apply_run_end(victory: bool) -> void:
	state = State.VICTORY if victory else State.GAME_OVER
	wave_manager.stop()
	Sfx.play("victory" if victory else "defeat", 0.0)
	hud.show_results(victory)
	get_tree().paused = true

func restart_run() -> void:
	if Net.active():
		if Net.hosting():
			Net.back_to_lobby()
			rpc(&"cl_restart")
			get_tree().paused = false
			get_tree().reload_current_scene()
		# clients wait for the host's cl_restart
		return
	get_tree().paused = false
	get_tree().reload_current_scene()

# --- Shop actions (executed on the simulation authority) ---

func repairable_walls() -> bool:
	for w in walls:
		if not w.destroyed and w.hp < w.max_hp:
			return true
	return false

func repair_walls() -> void:
	for w in walls:
		w.repair_full()

func reinforce_walls() -> void:
	for w in walls:
		w.reinforce(1.3)

func destroyed_wall_count() -> int:
	var n := 0
	for w in walls:
		if w.destroyed:
			n += 1
	return n

func rebuild_walls() -> void:
	for w in walls:
		if w.destroyed:
			w.rebuild()

func can_place_at(pos: Vector2) -> bool:
	return pos.x > wall_x + 60.0 and pos.x < arena_w - 60.0 and pos.y > 40.0 and pos.y < arena_h - 40.0

func can_place_turret() -> bool:
	return player != null and is_instance_valid(player) and can_place_at(player.global_position + TURRET_OFFSET)

func add_tower_kit(type_key: String) -> void:
	tower_kits.append(type_key)
	Fx.float_text(Vector2(arena_w / 2.0 - 60, arena_h * 0.5),
		"%s kit — press E to deploy" % TowerData.TYPES[type_key].label, Color(0.5, 0.9, 1.0))

## Deploy engineer bonuses come from whoever placed the tower.
func place_turret_at(type_key: String, pos: Vector2, owner_tank: Player = null) -> void:
	var t := Turret.new()
	t.setup(type_key)
	if owner_tank != null and is_instance_valid(owner_tank):
		t.eng_damage = 1.0 + 0.15 * owner_tank.engineering
		t.eng_hp = 1.0 + 0.2 * owner_tank.engineering
	t.position = pos
	t.net_id = _next_net_id
	_next_net_id += 1
	_turrets[t.net_id] = t
	entity_layer.add_child(t)
	if Net.hosting():
		rpc(&"cl_turret_spawn", t.net_id, type_key, pos, t.eng_damage, t.eng_hp)
	Fx.float_text(pos, "%s tower online" % TowerData.TYPES[type_key].label, Color(0.5, 0.9, 1.0))

## Shop purchase, executed by the authority for `buyer` (a peer id).
func execute_buy(buyer: int, index: int) -> void:
	var shop := hud.shop
	var cards: Array = shop.cards()
	if index < 0 or index >= cards.size():
		return
	var card: Dictionary = cards[index]
	if card.get("sold", false):
		return
	if not Game.spend(int(card.cost)):
		_sfx_for(buyer, "deny")
		return
	_sfx_for(buyer, "buy")
	var tank: Player = players.get(buyer)
	match card.kind:
		"weapon":
			if tank != null and is_instance_valid(tank):
				var idx: int = tank.buy_weapon(card.key)
				if idx >= 0 and Net.hosting():
					rpc(&"cl_weapon", buyer, idx, card.key, tank.mounts[idx].level)
		"stat":
			var count := int(card.get("count", 1))
			if tank != null and is_instance_valid(tank):
				tank.apply_stat(card.key, count)
			if Net.hosting():
				rpc(&"cl_stat", buyer, card.key, count)
		"tower":
			add_tower_kit(card.key)
		"reinforce":
			reinforce_walls()
		"rebuild":
			rebuild_walls()
		"overcharge":
			Turret.damage_mult *= 1.3
	card["sold"] = true
	shop.after_sale()
	if Net.hosting():
		rpc(&"cl_shop_state", shop.cards(), shop.rerolls())

## Play a UI sound for one specific peer (host locally, clients via rpc).
func _sfx_for(pid: int, sound: String) -> void:
	if pid == Net.my_id():
		Sfx.play(sound, 0.0)
	elif Net.hosting():
		rpc_id(pid, &"cl_sfx", sound)

## Level-up pick made in this peer's HUD.
func levelup_pick(stat_id: String) -> void:
	if not Net.active():
		player.apply_stat(stat_id)
		return
	if Net.hosting():
		player.apply_stat(stat_id)
		rpc(&"cl_stat", 1, stat_id, 1)
	else:
		rpc_id(1, &"srv_pick", stat_id)

## This peer finished all its banked picks.
func levelup_done() -> void:
	if not Net.active():
		return
	if Net.hosting():
		_lv_done[1] = true
		_check_levelup_done()
	else:
		rpc_id(1, &"srv_picks_done")

func _check_levelup_done() -> void:
	if not _lv_active:
		return
	for pid in Net.roster:
		if not _lv_done.get(pid, false):
			return
	_lv_active = false
	rpc(&"cl_resume")
	_apply_resume()

func _apply_resume() -> void:
	hud.levelup_all_done()
	if state == State.WAVE or state == State.INTERMISSION:
		get_tree().paused = false

# --- Host-side entity bookkeeping (called by the sim; no-ops offline where noted) ---

func host_register_enemy(e: Enemy) -> void:
	e.net_id = _next_net_id
	_next_net_id += 1
	_enemies[e.net_id] = e
	if Net.hosting():
		rpc(&"cl_enemy_spawn", e.net_id, e.type_key, wave_index + 1, e.stats.get("boss", false), e.position)

func host_enemy_died(e: Enemy) -> void:
	_enemies.erase(e.net_id)
	if Net.hosting():
		rpc(&"cl_enemy_died", e.net_id)

func spawn_pickup(kind: String, value: int, pos: Vector2) -> void:
	# Gold now lingers on the ground for a whole 10-wave group, so merge coins
	# that land near each other into one growing pile rather than spawning a node
	# per kill -- keeps the pickup count (and the snapshot it streams) bounded.
	if kind == "gold":
		for id in _pickups:
			var ex: Pickup = _pickups[id]
			if is_instance_valid(ex) and ex.kind == "gold" and not ex.vacuum \
					and ex.position.distance_to(pos) < PICKUP_MERGE_RADIUS:
				ex.value += value
				return
	var pk := Pickup.new()
	pk.kind = kind
	pk.value = value
	pk.position = pos
	pk.net_id = _next_net_id
	_next_net_id += 1
	_pickups[pk.net_id] = pk
	entity_layer.add_child(pk)
	if Net.hosting():
		rpc(&"cl_pickup_spawn", pk.net_id, kind, pos)

func host_pickup_taken(pk: Pickup) -> void:
	_pickups.erase(pk.net_id)
	if Net.hosting():
		rpc(&"cl_pickup_taken", pk.net_id, pk.kind)

func host_turret_died(t: Turret) -> void:
	_turrets.erase(t.net_id)
	if Net.hosting():
		rpc(&"cl_turret_died", t.net_id)

## Fired by weapon mounts / turrets / enemies on the host so clients can render
## the tracer + hear the right sound. No-op offline.
func broadcast_shot(pos: Vector2, dir: Vector2, speed: float, travel: float, color: Color, sfx: String) -> void:
	if Net.hosting():
		rpc(&"cl_shot", pos, dir, speed, travel, color, sfx)

func host_peer_left(pid: int) -> void:
	var p: Player = players.get(pid)
	if p != null and is_instance_valid(p):
		p.queue_free()
	players.erase(pid)
	rpc(&"cl_player_left", pid)
	_lv_done[pid] = true
	_check_levelup_done()
	if state == State.WAVE or state == State.INTERMISSION:
		_on_player_died()  # re-check the all-dead condition

# --- Snapshots (host → clients, unreliable) ---

func _broadcast_snapshot() -> void:
	var e_data: Dictionary = {}
	for id in _enemies:
		var e: Enemy = _enemies[id]
		if is_instance_valid(e):
			e_data[id] = [e.position.x, e.position.y, e.visual_rotation(), e.hp]
	var t_data: Dictionary = {}
	for id in _turrets:
		var t: Turret = _turrets[id]
		if is_instance_valid(t):
			t_data[id] = t.hp
	var k_data: Dictionary = {}
	for id in _pickups:
		var pk: Pickup = _pickups[id]
		if is_instance_valid(pk):
			k_data[id] = [pk.position.x, pk.position.y]
	var p_data: Dictionary = {}
	for pid in players:
		var p: Player = players[pid]
		if is_instance_valid(p):
			p_data[pid] = [p.hp, p.max_hp]
	var w_data: Array = []
	for w in walls:
		w_data.append([w.hp, w.max_hp, w.destroyed])
	rpc(&"cl_snapshot", {
		"e": e_data, "t": t_data, "k": k_data, "p": p_data, "w": w_data,
		"c": core.hp,
		"g": [Game.money, Game.xp, Game.level, Game.kills],
		"s": [state, wave_index, intermission_left],
		"kits": tower_kits,
	})

@rpc("authority", "unreliable")
func cl_snapshot(snap: Dictionary) -> void:
	_smoke_snaps += 1
	var st := int(snap.s[0])
	if state != State.GAME_OVER and state != State.VICTORY:
		state = st as State
	wave_index = int(snap.s[1])
	intermission_left = float(snap.s[2])
	Game.net_apply(snap.g[0], snap.g[1], snap.g[2], snap.g[3])
	tower_kits = snap.kits
	for id in snap.e:
		var e: Enemy = _enemies.get(id)
		if e != null and is_instance_valid(e):
			var d: Array = snap.e[id]
			e.net_update(Vector2(d[0], d[1]), d[2], d[3])
	for id in snap.t:
		var t: Turret = _turrets.get(id)
		if t != null and is_instance_valid(t):
			t.net_hp(snap.t[id])
	for id in snap.k:
		var pk: Pickup = _pickups.get(id)
		if pk != null and is_instance_valid(pk):
			var kd: Array = snap.k[id]
			pk.net_pos(Vector2(kd[0], kd[1]))
	for pid in snap.p:
		var p: Player = players.get(pid)
		if p != null and is_instance_valid(p):
			var pd: Array = snap.p[pid]
			p.net_set_hp(pd[0], pd[1])
	for i in range(mini(walls.size(), snap.w.size())):
		var wd: Array = snap.w[i]
		walls[i].net_apply(wd[0], wd[1], wd[2])
	core.net_hp(snap.c)
	_mp_smoke_client_check()

# --- Client-bound events ---

@rpc("authority", "reliable")
func cl_enemy_spawn(id: int, type: String, wave: int, boss: bool, pos: Vector2) -> void:
	var e := Enemy.new()
	e.puppet = true
	e.setup(type, wall_x, _gap_positions(), core, wave, boss)
	e.position = pos
	e.net_id = id
	_enemies[id] = e
	entity_layer.add_child(e)

@rpc("authority", "reliable")
func cl_enemy_died(id: int) -> void:
	var e: Enemy = _enemies.get(id)
	_enemies.erase(id)
	if e != null and is_instance_valid(e):
		e.puppet_die()

@rpc("authority", "reliable")
func cl_pickup_spawn(id: int, kind: String, pos: Vector2) -> void:
	var pk := Pickup.new()
	pk.puppet = true
	pk.kind = kind
	pk.position = pos
	pk.net_id = id
	_pickups[id] = pk
	entity_layer.add_child(pk)

@rpc("authority", "reliable")
func cl_pickup_taken(id: int, kind: String) -> void:
	var pk: Pickup = _pickups.get(id)
	_pickups.erase(id)
	if pk != null and is_instance_valid(pk):
		pk.queue_free()
	Sfx.play("pickup_gold" if kind == "gold" else "pickup_xp")

@rpc("authority", "reliable")
func cl_turret_spawn(id: int, type: String, pos: Vector2, eng_damage: float, eng_hp: float) -> void:
	var t := Turret.new()
	t.puppet = true
	t.setup(type)
	t.eng_damage = eng_damage
	t.eng_hp = eng_hp
	t.position = pos
	t.net_id = id
	_turrets[id] = t
	entity_layer.add_child(t)

@rpc("authority", "reliable")
func cl_turret_died(id: int) -> void:
	var t: Turret = _turrets.get(id)
	_turrets.erase(id)
	if t != null and is_instance_valid(t):
		t.death_fx()
		t.queue_free()

@rpc("authority", "unreliable")
func cl_shot(pos: Vector2, dir: Vector2, speed: float, travel: float, color: Color, sfx: String) -> void:
	var p := Projectile.new()
	p.visual = true
	p.setup(dir, 0.0, travel, color, false, 0.0, speed)
	p.position = pos
	entity_layer.add_child(p)
	if sfx != "":
		Sfx.play(sfx)

@rpc("authority", "reliable")
func cl_sfx(sound: String) -> void:
	Sfx.play(sound)

@rpc("authority", "reliable")
func cl_wave(index: int) -> void:
	wave_index = index
	state = State.WAVE
	_show_wave_start(index)

@rpc("authority", "reliable")
func cl_shop_open(cards: Array, shop_rerolls: int) -> void:
	state = State.INTERMISSION
	intermission_left = INTERMISSION_TIME
	hud.shop.set_cards(cards, shop_rerolls)
	hud.open_shop()

@rpc("authority", "reliable")
func cl_shop_state(cards: Array, shop_rerolls: int) -> void:
	hud.shop.set_cards(cards, shop_rerolls)

@rpc("authority", "reliable")
func cl_weapon(pid: int, mount_idx: int, key: String, level: int) -> void:
	var p: Player = players.get(pid)
	if p != null and is_instance_valid(p) and mount_idx < p.mounts.size():
		p.mounts[mount_idx].set_weapon(key, level)

@rpc("authority", "reliable")
func cl_stat(pid: int, key: String, count: int) -> void:
	var p: Player = players.get(pid)
	if p != null and is_instance_valid(p):
		p.apply_stat(key, count)

@rpc("authority", "reliable")
func cl_levelup(count: int) -> void:
	Game.pending_picks = count
	get_tree().paused = true

@rpc("authority", "reliable")
func cl_resume() -> void:
	_apply_resume()

@rpc("authority", "reliable")
func cl_run_end(victory: bool) -> void:
	_apply_run_end(victory)

@rpc("authority", "reliable")
func cl_restart() -> void:
	Net.back_to_lobby()
	get_tree().paused = false
	get_tree().reload_current_scene()

@rpc("authority", "reliable")
func cl_player_left(pid: int) -> void:
	var p: Player = players.get(pid)
	if p != null and is_instance_valid(p):
		p.queue_free()
	players.erase(pid)

# --- Player transforms (owner → everyone, unreliable) ---

@rpc("any_peer", "unreliable")
func net_player_pos(pos: Vector2, rot: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var p: Player = players.get(sender)
	if p != null and is_instance_valid(p):
		p.net_transform(pos, rot)

# --- Client requests (host validates) ---

@rpc("any_peer", "reliable")
func srv_deploy() -> void:
	if not Net.hosting():
		return
	_try_deploy(players.get(multiplayer.get_remote_sender_id()))

@rpc("any_peer", "reliable")
func srv_buy(index: int) -> void:
	if not Net.hosting() or state != State.INTERMISSION:
		return
	execute_buy(multiplayer.get_remote_sender_id(), index)

@rpc("any_peer", "reliable")
func srv_reroll() -> void:
	if not Net.hosting() or state != State.INTERMISSION:
		return
	hud.shop.do_reroll(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func srv_repair() -> void:
	if not Net.hosting() or state != State.INTERMISSION:
		return
	hud.shop.do_repair(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func srv_pick(stat_id: String) -> void:
	if not Net.hosting():
		return
	var sender := multiplayer.get_remote_sender_id()
	var p: Player = players.get(sender)
	if p != null and is_instance_valid(p) and CardPool.STATS.has(stat_id):
		p.apply_stat(stat_id)
		rpc(&"cl_stat", sender, stat_id, 1)

@rpc("any_peer", "reliable")
func srv_picks_done() -> void:
	if not Net.hosting():
		return
	_lv_done[multiplayer.get_remote_sender_id()] = true
	_check_levelup_done()

# --- Headless multiplayer smoke test (ENet on localhost) ---

func _mp_smoke_host() -> void:
	Net.host_game(true)
	Net.lobby_updated.connect(func():
		if Net.hosting() and not Net.started and Net.roster.size() >= 2:
			for pid in Net.roster:
				Net.roster[pid].ready = true
			Net.request_start())
	get_tree().create_timer(12.0).timeout.connect(func():
		var f := FileAccess.open("res://.mp_smoke_host.log", FileAccess.WRITE)
		f.store_string("started=%s state=%s enemies=%d players=%d" % [
			Net.started, state, _enemies.size(), players.size()])
		f.close())

func _mp_smoke_join() -> void:
	Net.join_enet("127.0.0.1")
	Net.lobby_updated.connect(func():
		if Net.mode == Net.Mode.CLIENT and Net.roster.has(Net.my_id()) \
				and not Net.roster[Net.my_id()].ready:
			Net.set_my_tank("scout")
			Net.set_my_ready(true))

func _mp_smoke_client_check() -> void:
	if _smoke_mp != "join" or _smoke_snaps < 10 or _enemies.is_empty():
		return
	if FileAccess.file_exists("res://.mp_smoke_client.log"):
		return
	var f := FileAccess.open("res://.mp_smoke_client.log", FileAccess.WRITE)
	f.store_string("snaps=%d enemies=%d players=%d state=%s money=%d" % [
		_smoke_snaps, _enemies.size(), players.size(), state, Game.money])
	f.close()
