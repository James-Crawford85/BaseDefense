class_name Enemy
extends CharacterBody2D
## One script for all enemy types — behavior differences come from EnemyData.
## Marches down its lane (runners aim for wall gaps), attacks whatever damageable
## thing it bumps into (wall, turret, core, player), then pushes on toward the core.

var stats: Dictionary
var hp: float
var max_hp: float
var type_key: String

var _wall_line_y: float
var _gap_xs: Array = []
var _core: Node2D
var _march_x: float = 0.0
var _attack_target: Node2D = null
var _cooldown_left: float = 0.0
var _lost_contact: float = 0.0
var _bar: HealthBar

func setup(type: String, wall_line_y: float, gap_xs: Array, core: Node2D) -> void:
	type_key = type
	stats = EnemyData.TYPES[type]
	hp = stats.hp
	max_hp = stats.hp
	_wall_line_y = wall_line_y
	_gap_xs = gap_xs
	_core = core

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4)
	_march_x = position.x
	if stats.seeks_gaps and not _gap_xs.is_empty():
		var nearest: float = _gap_xs[0]
		for gx in _gap_xs:
			if absf(gx - position.x) < absf(nearest - position.x):
				nearest = gx
		_march_x = nearest + randf_range(-20.0, 20.0)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * stats.body_size
	shape.shape = rect
	add_child(shape)

	var poly := Polygon2D.new()
	var s: float = stats.body_size / 2.0
	if stats.shape == "triangle":
		poly.polygon = PackedVector2Array([Vector2(0, s), Vector2(-s, -s), Vector2(s, -s)])
	else:
		poly.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	poly.color = stats.color
	add_child(poly)

	_bar = HealthBar.new()
	_bar.width = stats.body_size
	_bar.position = Vector2(0, -s - 8.0)
	add_child(_bar)

func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _attack_target != null and not is_instance_valid(_attack_target):
		_attack_target = null

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
	# March straight down the lane until fully past the wall band, then head for the core.
	if global_position.y < _wall_line_y + 70.0:
		return Vector2(_march_x, _wall_line_y + 80.0)
	if _core != null and is_instance_valid(_core):
		return _core.global_position
	return global_position + Vector2.DOWN * 100.0

func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	Fx.flash(self)
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		die()

func die() -> void:
	Game.register_kill(stats.money)
	Fx.float_text(global_position, "+$%d" % stats.money, Color(1.0, 0.9, 0.4))
	queue_free()
