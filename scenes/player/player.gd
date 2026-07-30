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
var _sprite: Sprite2D

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 4) | (1 << 5)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	# Top-down soldier art faces up at rotation 0; pivot sits on the body so
	# the rifle pokes ahead of the collision circle when rotated.
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/soldier.png")
	_sprite.scale = Vector2.ONE * 0.08
	_sprite.offset = Vector2(0, -140)
	add_child(_sprite)

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

	var aim := Targeting.nearest_enemy(get_tree(), global_position, fire_range)
	if _fire_cooldown <= 0.0 and aim != null:
		var p := Projectile.new()
		p.setup(aim.global_position - global_position, damage, fire_range + 80.0, Color(0.5, 0.9, 1.0))
		p.position = global_position
		get_parent().add_child(p)
		_fire_cooldown = 1.0 / fire_rate

	# Face the aim target while one is in range, otherwise the movement direction.
	var face_dir := Vector2.ZERO
	if aim != null:
		face_dir = aim.global_position - global_position
	elif input_dir != Vector2.ZERO:
		face_dir = input_dir
	if face_dir != Vector2.ZERO:
		_sprite.rotation = lerp_angle(_sprite.rotation, face_dir.angle() + PI / 2.0, 14.0 * delta)

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
