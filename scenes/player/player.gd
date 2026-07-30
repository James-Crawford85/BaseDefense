class_name Player
extends CharacterBody2D
## The hero: 8-direction movement, dash, auto-fires at the nearest enemy in range.
## Self-contained on purpose — co-op later just means instancing another one of
## these with a different input device.

signal died

var move_speed: float = 260.0
var max_hp: float = 100.0
var hp: float = 100.0
var damage: float = 10.0
var fire_rate: float = 2.0
var fire_range: float = 320.0

var _fire_cooldown: float = 0.0
var _invuln: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_time: float = 0.0

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 4) | (1 << 5)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	poly.polygon = pts
	poly.color = Color(0.35, 0.75, 0.95)
	add_child(poly)

func _physics_process(delta: float) -> void:
	_fire_cooldown -= delta
	_invuln -= delta
	_dash_cooldown -= delta
	_dash_time -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0 and input_dir != Vector2.ZERO:
		_dash_time = 0.15
		_dash_cooldown = 1.0
		_invuln = maxf(_invuln, 0.25)
	var speed := move_speed * (2.6 if _dash_time > 0.0 else 1.0)
	velocity = input_dir * speed
	move_and_slide()

	if _fire_cooldown <= 0.0:
		var target := Targeting.nearest_enemy(get_tree(), global_position, fire_range)
		if target != null:
			var p := Projectile.new()
			p.setup(target.global_position - global_position, damage, fire_range + 80.0, Color(0.5, 0.9, 1.0))
			p.position = global_position
			get_parent().add_child(p)
			_fire_cooldown = 1.0 / fire_rate

func take_damage(amount: float) -> void:
	if _invuln > 0.0 or hp <= 0.0:
		return
	hp -= amount
	_invuln = 0.6
	Fx.flash(self)
	Fx.shake(4.0)
	if hp <= 0.0:
		hp = 0.0
		hide()
		set_physics_process(false)
		collision_layer = 0
		died.emit()
