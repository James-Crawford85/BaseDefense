class_name Enemy
extends CharacterBody2D
## One script for all enemy types — differences come from EnemyData's stat
## triangle. Melee types march left down their lane (gap-seekers aim for wall
## gaps) and attack whatever damageable thing they bump into. Ranged types stop
## at attack_range and shell the nearest target (wall, tower, core, or player).
## Vehicle art (assets/enemy_*.png) faces up inside _visual, which is rotated
## so it faces the direction of travel (left). Ranged types swivel the whole
## vehicle to track their victim while parked.

const FACE_LEFT := -PI / 2.0  # up-facing art rotated to the travel direction
const VEHICLE_LENGTH := 1.45  # sprite length relative to body_size (collision box)

const VEHICLE_TEXTURES: Dictionary = {
	"light_tank": preload("res://assets/enemy_grunt.png"),
	"buggy": preload("res://assets/enemy_runner.png"),
	"bike": preload("res://assets/enemy_stinger.png"),
	"apc": preload("res://assets/enemy_brute.png"),
	"siege": preload("res://assets/enemy_ogre.png"),
	"artillery": preload("res://assets/enemy_spitter.png"),
}

var stats: Dictionary
var hp: float
var max_hp: float
var type_key: String
var boss := false
var net_id: int = 0
## Client-side mirror in multiplayer: no simulation, position/rotation/hp come
## from host snapshots (see main.gd). Stays in the "enemies" group so local
## weapon mounts and turret heads can visually track it.
var puppet := false

var _net_pos := Vector2.ZERO
var _net_rot := FACE_LEFT

var _wall_line_x: float
var _gap_ys: Array = []
var _core: Node2D
var _march_y: float = 0.0
var _attack_target: Node2D = null
var _cooldown_left: float = 0.0
var _lost_contact: float = 0.0
var _bar: HealthBar
var _visual: Node2D

func setup(type: String, wall_line_x: float, gap_ys: Array, core: Node2D, wave: int = 1, is_boss: bool = false) -> void:
	type_key = type
	boss = is_boss
	stats = EnemyData.wave_scaled(type, wave, is_boss)
	hp = stats.hp
	max_hp = stats.hp
	_wall_line_x = wall_line_x
	_gap_ys = gap_ys
	_core = core

func _ready() -> void:
	add_to_group("enemies")
	if puppet:
		_net_pos = position
		set_physics_process(false)
		_visual = Node2D.new()
		_visual.rotation = FACE_LEFT
		add_child(_visual)
		_build_vehicle()
		_bar = HealthBar.new()
		_bar.width = stats.body_size
		_bar.position = Vector2(0, -stats.body_size / 2.0 - 8.0)
		add_child(_bar)
		return
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)  # incl. gates
	# Every enemy holds the row it spawned in. Gap-seekers only peel off toward an
	# actual opening once a wall or gate is breached (see _effective_lane_y).
	_march_y = position.y

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * stats.body_size
	shape.shape = rect
	add_child(shape)

	_visual = Node2D.new()
	_visual.rotation = FACE_LEFT
	add_child(_visual)
	_build_vehicle()

	_bar = HealthBar.new()
	_bar.width = stats.body_size
	_bar.position = Vector2(0, -stats.body_size / 2.0 - 8.0)
	add_child(_bar)

func _build_vehicle() -> void:
	var tex: Texture2D = VEHICLE_TEXTURES[stats.vehicle]
	var spr := Sprite2D.new()
	spr.texture = tex
	var k: float = stats.body_size * VEHICLE_LENGTH / maxf(tex.get_width(), tex.get_height())
	spr.scale = Vector2(k, k)
	_visual.add_child(spr)

func _process(delta: float) -> void:
	if not puppet:
		return
	position = position.lerp(_net_pos, minf(1.0, 12.0 * delta))
	_visual.rotation = lerp_angle(_visual.rotation, _net_rot, 12.0 * delta)

func visual_rotation() -> float:
	return _visual.rotation if _visual != null else FACE_LEFT

## Snapshot update for puppets (client side).
func net_update(pos: Vector2, rot: float, new_hp: float) -> void:
	_net_pos = pos
	_net_rot = rot
	if new_hp < hp:
		Fx.flash(self)
	hp = new_hp
	if _bar != null:
		_bar.set_health(hp, max_hp)

## Death fanfare for puppets — drops/scoring already happened on the host.
func puppet_die() -> void:
	Sfx.play("explode_big" if stats.body_size >= 34.0 else "explode_small")
	queue_free()

func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _attack_target != null and not is_instance_valid(_attack_target):
		_attack_target = null

	# Ranged: hold position and shoot as soon as anything is in range.
	if stats.attack_range > 0.0:
		var victim := _nearest_victim()
		if victim != null:
			velocity = Vector2.ZERO
			# Whole vehicle swivels toward the victim while parked (the art has
			# no separate turret piece yet). Up-facing art: rotation = angle + PI/2.
			var aim := (victim.global_position - global_position).angle() + PI / 2.0
			_visual.rotation = lerp_angle(_visual.rotation, aim, 6.0 * delta)
			if _cooldown_left <= 0.0:
				_fire_at(victim)
				_cooldown_left = stats.attack_cooldown
			return
		_visual.rotation = lerp_angle(_visual.rotation, FACE_LEFT, 4.0 * delta)

	velocity = (_current_goal() - global_position).normalized() * stats.speed
	move_and_slide()

	var touched: Node2D = null
	for i in range(get_slide_collision_count()):
		var collider := get_slide_collision(i).get_collider() as Node2D
		if collider == null or collider is Enemy:
			continue
		if collider.has_method("take_damage"):
			touched = collider
			break

	if touched != null:
		_attack_target = touched
		_lost_contact = 0.0
		if _cooldown_left <= 0.0:
			_attack_target.take_damage(stats.damage)
			_cooldown_left = stats.attack_cooldown
	elif _attack_target != null:
		_lost_contact += delta
		if _lost_contact > 1.0:
			_attack_target = null

func _current_goal() -> Vector2:
	if _attack_target != null and is_instance_valid(_attack_target):
		return _attack_target.global_position
	# March straight left down the lane until fully past the wall band, then
	# head for the core. Gap-seekers steer toward the nearest breach instead.
	if global_position.x > _wall_line_x - 70.0:
		return Vector2(_wall_line_x - 80.0, _effective_lane_y())
	if _core != null and is_instance_valid(_core):
		return _core.global_position
	return global_position + Vector2.LEFT * 100.0

## The row (y) an enemy drives toward. Normally its spawn row; a gap-seeker peels
## off to the nearest open breach (destroyed wall/gate) once one exists.
func _effective_lane_y() -> float:
	if stats.seeks_gaps:
		var by := _nearest_breach_y()
		if not is_nan(by):
			return by
	return _march_y

func _has_open_breach() -> bool:
	for grp in ["walls", "gates"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is WallSegment and (n as WallSegment).destroyed:
				return true
	return false

## Row (y) of the destroyed wall/gate nearest this enemy's row, or NAN if none.
func _nearest_breach_y() -> float:
	var best_y := NAN
	var best_d := INF
	for grp in ["walls", "gates"]:
		for n in get_tree().get_nodes_in_group(grp):
			var seg := n as WallSegment
			if seg == null or not seg.destroyed:
				continue
			var d := absf(seg.global_position.y - position.y)
			if d < best_d:
				best_d = d
				best_y = seg.global_position.y
	return best_y

func _nearest_victim() -> Node2D:
	var best: Node2D = null
	var best_d: float = stats.attack_range * stats.attack_range
	# A gap-seeker only ignores fortifications once a breach exists — then it rushes
	# the opening instead of stopping to shoot walls/gates. Until then it engages
	# the wall or gate in its own row like any other enemy.
	var breaching: bool = stats.seeks_gaps and _has_open_breach()
	for group in ["players", "walls", "structures", "gates"]:
		if breaching and (group == "walls" or group == "gates"):
			continue
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node2D
			if node == null:
				continue
			if node is Player and node.hp <= 0.0:
				continue
			if node is WallSegment and node.destroyed:  # covers gates (Gate extends WallSegment)
				continue
			var d := node.global_position.distance_squared_to(global_position)
			if d < best_d:
				best_d = d
				best = node
	return best

func _fire_at(victim: Node2D) -> void:
	var dir := victim.global_position - global_position
	var p := Projectile.new()
	p.setup(dir, stats.damage,
		stats.attack_range + 140.0, stats.color, true, 0.0, 260.0)
	p.position = global_position
	get_parent().add_child(p)
	Sfx.play("shot_artillery")
	if Net.game != null:
		Net.game.broadcast_shot(global_position, dir, 260.0,
			stats.attack_range + 140.0, stats.color, "shot_artillery")

func take_damage(amount: float) -> void:
	if puppet or hp <= 0.0:
		return
	hp -= amount
	Fx.flash(self)
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		die()

func die() -> void:
	Game.register_kill()
	Sfx.play("explode_big" if stats.body_size >= 34.0 else "explode_small")
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.kill_heal > 0.0:
			p.heal(p.kill_heal)
	if Net.game != null:
		Net.game.spawn_pickup("gold", stats.money,
			global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10)))
		Net.game.spawn_pickup("xp", maxi(1, int(round(stats.money * 0.8))),
			global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10)))
		Net.game.host_enemy_died(self)
	queue_free()
