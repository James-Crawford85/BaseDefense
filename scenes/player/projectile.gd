class_name Projectile
extends Area2D
## Straight-line bullet. Player/tower shots hit enemies (optionally with an
## AoE explosion); enemy shots hit players, walls, and structures, and fly
## through anything that can't take damage.

var _velocity := Vector2.ZERO
var _damage := 0.0
var _travel_left := 0.0
var _color := Color.WHITE
var _enemy_shot := false
var _aoe := 0.0
## Tracer-only mode for multiplayer clients: flies and expires, never collides
## (all damage happens on the host).
var visual := false

func setup(direction: Vector2, damage: float, max_travel: float, color: Color,
		enemy_shot: bool = false, aoe_radius: float = 0.0, speed: float = 600.0) -> void:
	_velocity = direction.normalized() * speed
	_damage = damage
	_travel_left = max_travel
	_color = color
	_enemy_shot = enemy_shot
	_aoe = aoe_radius

func _ready() -> void:
	if not visual:
		collision_layer = 1 << 3
		if _enemy_shot:
			collision_mask = (1 << 0) | (1 << 1) | (1 << 4) | (1 << 6)  # walls, player, structures, gates
		else:
			collision_mask = 1 << 2
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		shape.shape = circle
		add_child(shape)
		body_entered.connect(_on_body_entered)
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(8):
		var a := TAU * i / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 5.0)
	poly.polygon = pts
	poly.color = _color
	add_child(poly)

func _physics_process(delta: float) -> void:
	var step := _velocity * delta
	position += step
	_travel_left -= step.length()
	if _travel_left <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _enemy_shot:
		if body is Enemy:
			return
		if body.has_method("take_damage"):
			body.take_damage(_damage)
			queue_free()
		# Bodies without take_damage (arena bounds) are flown through.
	else:
		if body is Enemy:
			if _aoe > 0.0:
				_explode()
			else:
				body.take_damage(_damage)
			queue_free()

func _explode() -> void:
	var center := global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Enemy
		if n != null and n.global_position.distance_to(center) <= _aoe:
			n.take_damage(_damage)
	Fx.boom(center, _aoe, _color)
