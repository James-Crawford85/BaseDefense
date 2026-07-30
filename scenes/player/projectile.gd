class_name Projectile
extends Area2D
## Straight-line bullet fired by the player or a turret. Dies on first enemy hit
## or after travelling max_travel pixels.

const SPEED := 600.0

var _velocity := Vector2.ZERO
var _damage := 0.0
var _travel_left := 0.0
var _color := Color.WHITE

func setup(direction: Vector2, damage: float, max_travel: float, color: Color) -> void:
	_velocity = direction.normalized() * SPEED
	_damage = damage
	_travel_left = max_travel
	_color = color

func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 << 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	add_child(shape)
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(8):
		var a := TAU * i / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 5.0)
	poly.polygon = pts
	poly.color = _color
	add_child(poly)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := _velocity * delta
	position += step
	_travel_left -= step.length()
	if _travel_left <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		body.take_damage(_damage)
		queue_free()
