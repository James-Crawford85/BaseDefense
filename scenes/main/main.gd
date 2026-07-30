extends Node2D
## Orchestrates the run: builds the arena/fortress/player in code, owns the
## state machine (menu → waves/intermissions → results), and exposes the
## actions the shop can buy.

enum State { MENU, WAVE, INTERMISSION, GAME_OVER, VICTORY }

const WALL_SLOTS := 8
const GAP_SLOTS: Array = [2, 5]
const INTERMISSION_TIME := 25.0
const FINAL_WAVE := 10
const TURRET_OFFSET := Vector2(0, -46)

# Layout is derived from the viewport (which matches the background art):
# grass field on top, battlement walkway at ~78% height, courtyard below it.
var arena_w: float
var arena_h: float
var wall_y: float
var core_pos: Vector2

var state: State = State.MENU
var wave_index: int = -1
var intermission_left: float = 0.0

var player: Player
var core: FortressCore
var walls: Array = []
var wave_manager: WaveManager
var hud: Hud
var entity_layer: Node2D

func _ready() -> void:
	Game.reset()
	arena_w = get_viewport_rect().size.x
	arena_h = get_viewport_rect().size.y
	wall_y = arena_h * 0.785
	core_pos = Vector2(arena_w / 2.0, arena_h * 0.92)
	_build_camera()
	_build_background()
	_build_bounds()

	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	add_child(entity_layer)
	Fx.world = entity_layer

	_build_fortress()
	# player is created in begin_run once a tank class is chosen

	wave_manager = WaveManager.new()
	wave_manager.arena = entity_layer
	wave_manager.wall_line_y = wall_y
	wave_manager.gap_xs = _gap_positions()
	wave_manager.core = core
	wave_manager.spawn_x_min = 40.0
	wave_manager.spawn_x_max = arena_w - 40.0
	add_child(wave_manager)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	get_tree().paused = true

	# Headless smoke testing: `godot --headless --quit-after N -- --smoke`
	if "--smoke" in OS.get_cmdline_user_args():
		begin_run.call_deferred()
		_smoke_extras.call_deferred()

## Spawns one of every tower and enemy type so a headless run exercises all
## combat code paths (ranged enemies, AoE, flame cones), not just wave 1.
func _smoke_extras() -> void:
	var i := 0
	for key in TowerData.TYPES:
		place_turret_at(key, Vector2(90.0 + 130.0 * i, wall_y - 160.0))
		i += 1
	var j := 0
	for key in EnemyData.TYPES:
		var e := Enemy.new()
		e.setup(key, wall_y, _gap_positions(), core)
		e.position = Vector2(60.0 + 76.0 * j, -50.0)
		entity_layer.add_child(e)
		j += 1

func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(arena_w / 2.0, arena_h / 2.0)
	add_child(cam)
	cam.make_current()
	Fx.camera = cam

func _build_background() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/background.png")
	sprite.centered = false
	sprite.z_index = -10
	add_child(sprite)
	# Faint red tint marking the enemy spawn strip.
	_add_bg_rect(Rect2(0, 0, arena_w, 40), Color(0.3, 0.1, 0.1, 0.25))

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
	_add_static_box(Rect2(-40, -400, 40, arena_h + 800), 1 << 0)
	_add_static_box(Rect2(arena_w, -400, 40, arena_h + 800), 1 << 0)
	_add_static_box(Rect2(-40, arena_h, arena_w + 80, 40), 1 << 0)
	# Top strip only blocks players, so enemies can walk in from above the screen.
	_add_static_box(Rect2(-40, -10, arena_w + 80, 30), 1 << 5)

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
	var slot_width := (arena_w - WALL_MARGIN * 2.0) / WALL_SLOTS
	for i in range(WALL_SLOTS):
		if i in GAP_SLOTS:
			continue
		var wall := WallSegment.new()
		wall.seg_size = Vector2(slot_width - 4.0, 36.0)
		wall.position = Vector2(WALL_MARGIN + slot_width * (i + 0.5), wall_y)
		entity_layer.add_child(wall)
		walls.append(wall)
	core = FortressCore.new()
	core.position = core_pos
	entity_layer.add_child(core)
	core.core_destroyed.connect(_on_core_destroyed)

func _gap_positions() -> Array:
	var slot_width := (arena_w - WALL_MARGIN * 2.0) / WALL_SLOTS
	var arr: Array = []
	for i in GAP_SLOTS:
		arr.append(WALL_MARGIN + slot_width * (i + 0.5))
	return arr

func _process(delta: float) -> void:
	if state == State.INTERMISSION:
		intermission_left -= delta
		hud.set_countdown(intermission_left)
		if intermission_left <= 0.0:
			_start_wave(wave_index + 1)

# --- Run flow ---

func begin_run(tank_class: String = "assault") -> void:
	player = Player.new()
	player.setup(tank_class)
	player.position = Vector2(arena_w / 2.0, arena_h * 0.85)
	entity_layer.add_child(player)
	player.died.connect(_on_player_died)
	get_tree().paused = false
	hud.hide_menu()
	_start_wave(0)

func _start_wave(index: int) -> void:
	wave_index = index
	state = State.WAVE
	hud.close_shop()
	hud.set_wave_label(index + 1, FINAL_WAVE)
	hud.show_message("WAVE %d INCOMING" % (index + 1), 1.8)
	get_tree().create_timer(2.0).timeout.connect(func():
		if state == State.WAVE:
			wave_manager.start_wave(index))

func request_start_wave() -> void:
	if state == State.INTERMISSION:
		_start_wave(wave_index + 1)

func _on_wave_cleared(index: int) -> void:
	Game.waves_survived = index + 1
	var bonus := WaveData.wave_clear_bonus(index)
	Game.add_money(bonus)
	Fx.float_text(Vector2(arena_w / 2.0 - 40, arena_h * 0.4), "Wave clear +$%d" % bonus, Color(1, 0.9, 0.4))
	# Vacuum leftover drops to the player so nothing is stranded up-field.
	for p in get_tree().get_nodes_in_group("pickups"):
		p.vacuum = true
	if index + 1 >= FINAL_WAVE:
		_end_run(true)
	else:
		state = State.INTERMISSION
		intermission_left = INTERMISSION_TIME
		hud.open_shop()

func _on_player_died() -> void:
	_end_run(false)

func _on_core_destroyed() -> void:
	_end_run(false)

func _end_run(victory: bool) -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return
	state = State.VICTORY if victory else State.GAME_OVER
	wave_manager.stop()
	hud.show_results(victory)
	get_tree().paused = true

func restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

# --- Shop actions ---

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

func turret_spot() -> Vector2:
	return player.global_position + TURRET_OFFSET

func can_place_turret() -> bool:
	var pos := turret_spot()
	return pos.y < wall_y - 60.0 and pos.y > 70.0 and pos.x > 40.0 and pos.x < arena_w - 40.0

func place_turret(type_key: String) -> void:
	place_turret_at(type_key, turret_spot())

func place_turret_at(type_key: String, pos: Vector2) -> void:
	var t := Turret.new()
	t.setup(type_key)
	t.position = pos
	entity_layer.add_child(t)
	Fx.float_text(pos, "%s tower online" % TowerData.TYPES[type_key].label, Color(0.5, 0.9, 1.0))
