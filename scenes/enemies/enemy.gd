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

var _wall_line_x: float
var _gap_ys: Array = []
var _core: Node2D
var _march_y: float = 0.0
var _attack_target: Node2D = null
var _cooldown_left: float = 0.0
var _lost_contact: float = 0.0
var _bar: HealthBar
var _visual: Node2D

func setup(type: String, wall_line_x: float, gap_ys: Array, core: Node2D, wave: int = 1) -> void:
	type_key = type
	stats = EnemyData.wave_scaled(type, wave)
	hp = stats.hp
	max_hp = stats.hp
	_wall_line_x = wall_line_x
	_gap_ys = gap_ys
	_core = core

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4)
	_march_y = position.y
	if stats.seeks_gaps and not _gap_ys.is_empty():
		var nearest: float = _gap_ys[0]
		for gy in _gap_ys:
			if absf(gy - position.y) < absf(nearest - position.y):
				nearest = gy
		_march_y = nearest + randf_range(-20.0, 20.0)

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
	# head for the core.
	if global_position.x > _wall_line_x - 70.0:
		return Vector2(_wall_line_x - 80.0, _march_y)
	if _core != null and is_instance_valid(_core):
		return _core.global_position
	return global_position + Vector2.LEFT * 100.0

func _nearest_victim() -> Node2D:
	var best: Node2D = null
	var best_d: float = stats.attack_range * stats.attack_range
	for group in ["players", "walls", "structures"]:
		# Gap-seekers never stop to shoot walls — they slip through and hunt
		# what's behind, which keeps the breach-rush pressure alive now that
		# every vehicle is armed.
		if group == "walls" and stats.seeks_gaps:
			continue
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node2D
			if node == null:
				continue
			if node is Player and node.hp <= 0.0:
				continue
			if node is WallSegment and node.destroyed:
				continue
			var d := node.global_position.distance_squared_to(global_position)
			if d < best_d:
				best_d = d
				best = node
	return best

func _fire_at(victim: Node2D) -> void:
	var p := Projectile.new()
	p.setup(victim.global_position - global_position, stats.damage,
		stats.attack_range + 140.0, stats.color, true, 0.0, 260.0)
	p.position = global_position
	get_parent().add_child(p)
	Sfx.play("shot_artillery")

func take_damage(amount: float) -> void:
	if hp <= 0.0:
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
	var gold := Pickup.new()
	gold.kind = "gold"
	gold.value = stats.money
	gold.position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	get_parent().add_child(gold)
	var orb := Pickup.new()
	orb.kind = "xp"
	orb.value = maxi(1, int(round(stats.money * 0.8)))
	orb.position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	get_parent().add_child(orb)
	queue_free()
