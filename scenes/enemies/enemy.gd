class_name Enemy
extends CharacterBody2D
## One script for all enemy types — differences come from EnemyData's stat
## triangle. Melee types march down their lane (gap-seekers aim for wall gaps)
## and attack whatever damageable thing they bump into. Ranged types stop at
## attack_range and shell the nearest target (wall, tower, core, or player).
## Each type is drawn as a top-down vehicle silhouette (facing down/+y).

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
var _barrel: Node2D = null  # artillery only: pivots to track the current victim

func setup(type: String, wall_line_y: float, gap_xs: Array, core: Node2D, wave: int = 1) -> void:
	type_key = type
	stats = EnemyData.wave_scaled(type, wave)
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

	_build_vehicle()

	_bar = HealthBar.new()
	_bar.width = stats.body_size
	_bar.position = Vector2(0, -stats.body_size / 2.0 - 8.0)
	add_child(_bar)

# --- Vehicle drawing (all silhouettes face down; +y = forward) ---

func _add_poly(pts: PackedVector2Array, color: Color, parent: Node2D = self) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = color
	parent.add_child(p)
	return p

func _rect_pts(center: Vector2, size: Vector2) -> PackedVector2Array:
	var h := size / 2.0
	return PackedVector2Array([
		center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y),
		center + Vector2(h.x, h.y), center + Vector2(-h.x, h.y),
	])

func _octagon_pts(radius: float, center := Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(8):
		var a := TAU * (i + 0.5) / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

func _build_vehicle() -> void:
	var s: float = stats.body_size
	var hull: Color = stats.color
	var dark := Color(0.16, 0.16, 0.18)
	var accent: Color = hull.lightened(0.35)
	match stats.vehicle:
		"buggy":  # runner — light fast buggy on four exposed wheels
			for wx in [-0.4, 0.4]:
				for wy in [-0.33, 0.33]:
					_add_poly(_rect_pts(Vector2(wx, wy) * s, Vector2(0.2, 0.3) * s), dark)
			_add_poly(PackedVector2Array([
				Vector2(-0.32, -0.5) * s, Vector2(0.32, -0.5) * s,
				Vector2(0.15, 0.55) * s, Vector2(-0.15, 0.55) * s,
			]), hull)
			_add_poly(_rect_pts(Vector2(0, -0.05) * s, Vector2(0.22, 0.26) * s), accent)
		"bike":  # stinger — two inline wheels, slim body
			_add_poly(_rect_pts(Vector2(0, -0.5) * s, Vector2(0.14, 0.34) * s), dark)
			_add_poly(_rect_pts(Vector2(0, 0.5) * s, Vector2(0.14, 0.34) * s), dark)
			_add_poly(PackedVector2Array([
				Vector2(-0.16, -0.32) * s, Vector2(0.16, -0.32) * s, Vector2(0.22, 0.05) * s,
				Vector2(0.12, 0.4) * s, Vector2(-0.12, 0.4) * s, Vector2(-0.22, 0.05) * s,
			]), hull)
			_add_poly(_rect_pts(Vector2(0, -0.05) * s, Vector2(0.16, 0.2) * s), accent)
		"apc":  # brute — six-wheeled slab
			for wy in [-0.34, 0.0, 0.34]:
				_add_poly(_rect_pts(Vector2(-0.45, wy) * s, Vector2(0.18, 0.26) * s), dark)
				_add_poly(_rect_pts(Vector2(0.45, wy) * s, Vector2(0.18, 0.26) * s), dark)
			_add_poly(PackedVector2Array([
				Vector2(-0.32, -0.52) * s, Vector2(0.32, -0.52) * s, Vector2(0.45, -0.35) * s,
				Vector2(0.45, 0.35) * s, Vector2(0.32, 0.52) * s, Vector2(-0.32, 0.52) * s,
				Vector2(-0.45, 0.35) * s, Vector2(-0.45, -0.35) * s,
			]), hull)
			_add_poly(_octagon_pts(0.18 * s, Vector2(0, -0.05) * s), accent)
		"siege":  # ogre — dozer blade up front, fat short cannon
			_add_poly(_rect_pts(Vector2(-0.42, 0) * s, Vector2(0.26, 1.0) * s), dark)
			_add_poly(_rect_pts(Vector2(0.42, 0) * s, Vector2(0.26, 1.0) * s), dark)
			_add_poly(_rect_pts(Vector2.ZERO, Vector2(0.66, 0.85) * s), hull)
			_add_poly(PackedVector2Array([
				Vector2(-0.55, 0.42) * s, Vector2(0.55, 0.42) * s,
				Vector2(0.42, 0.62) * s, Vector2(-0.42, 0.62) * s,
			]), hull.darkened(0.3))
			_add_poly(_rect_pts(Vector2(0, 0.3) * s, Vector2(0.16, 0.5) * s), dark)
			_add_poly(_octagon_pts(0.3 * s), accent)
		"artillery":  # spitter — long howitzer barrel that tracks its target
			_add_poly(_rect_pts(Vector2(-0.4, 0) * s, Vector2(0.2, 0.9) * s), dark)
			_add_poly(_rect_pts(Vector2(0.4, 0) * s, Vector2(0.2, 0.9) * s), dark)
			_add_poly(_rect_pts(Vector2.ZERO, Vector2(0.6, 0.78) * s), hull)
			_barrel = Node2D.new()
			add_child(_barrel)
			_add_poly(_rect_pts(Vector2(0, 0.45) * s, Vector2(0.11, 0.9) * s), dark, _barrel)
			_add_poly(_rect_pts(Vector2(0, 0.85) * s, Vector2(0.18, 0.14) * s), dark, _barrel)
			_add_poly(_octagon_pts(0.24 * s), accent)
		_:  # grunt — classic light tank
			_add_poly(_rect_pts(Vector2(-0.42, 0) * s, Vector2(0.24, 1.0) * s), dark)
			_add_poly(_rect_pts(Vector2(0.42, 0) * s, Vector2(0.24, 1.0) * s), dark)
			_add_poly(_rect_pts(Vector2.ZERO, Vector2(0.7, 0.84) * s), hull)
			_add_poly(_rect_pts(Vector2(0, 0.34) * s, Vector2(0.6, 0.12) * s), accent)
			_add_poly(_rect_pts(Vector2(0, 0.34) * s, Vector2(0.1, 0.68) * s), dark)
			_add_poly(_octagon_pts(0.26 * s), accent)

func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _attack_target != null and not is_instance_valid(_attack_target):
		_attack_target = null

	# Ranged: hold position and shoot as soon as anything is in range.
	if stats.attack_range > 0.0:
		var victim := _nearest_victim()
		if victim != null:
			velocity = Vector2.ZERO
			if _barrel != null:
				var aim := (victim.global_position - global_position).angle() - PI / 2.0
				_barrel.rotation = lerp_angle(_barrel.rotation, aim, 10.0 * delta)
			if _cooldown_left <= 0.0:
				_fire_at(victim)
				_cooldown_left = stats.attack_cooldown
			return
		if _barrel != null:
			_barrel.rotation = lerp_angle(_barrel.rotation, 0.0, 6.0 * delta)

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

func _nearest_victim() -> Node2D:
	var best: Node2D = null
	var best_d: float = stats.attack_range * stats.attack_range
	for group in ["players", "walls", "structures"]:
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
