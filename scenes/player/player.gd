class_name Player
extends CharacterBody2D
## The player tank. Class chassis (TankData) sets base stats and weapon slot
## layout; WeaponMount children do all the shooting. The hull rotates toward
## the movement direction — since side mounts cover hull-relative 180° arcs,
## driving direction IS weapon aiming. Still co-op-ready: one self-contained
## scene per player.

signal died

var class_key := "assault"

var max_hp := 100.0
var hp := 100.0
var move_speed := 240.0
var damage_mult := 1.0
var fire_rate_mult := 1.0
var range_mult := 1.0
var armor := 0.0
var regen := 0.0
var pickup_radius := 90.0

var mounts: Array = []

var _invuln: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_time: float = 0.0

func setup(key: String) -> void:
	class_key = key

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 4) | (1 << 5)
	var data: Dictionary = TankData.CLASSES[class_key]
	max_hp = data.hp
	hp = max_hp
	move_speed = data.speed
	damage_mult = data.damage_mult
	fire_rate_mult = data.fire_rate_mult
	range_mult = data.range_mult
	armor = data.armor
	regen = data.regen
	pickup_radius = data.pickup_radius

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	add_child(shape)
	_build_hull(data.color)

	for slot in data.slots:
		var mount := WeaponMount.new()
		mount.tank = self
		mount.position = slot.pos
		mount.arc_center = slot.center
		mount.arc_half = slot.half
		add_child(mount)
		mounts.append(mount)
	mounts[0].set_weapon(data.start_weapon, 1)

func _build_hull(color: Color) -> void:
	for tx in [-17.0, 10.0]:
		var tread := Polygon2D.new()
		tread.polygon = PackedVector2Array([
			Vector2(tx, -20), Vector2(tx + 7, -20), Vector2(tx + 7, 20), Vector2(tx, 20)])
		tread.color = Color(0.14, 0.15, 0.16)
		add_child(tread)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([
		Vector2(-8, -22), Vector2(8, -22), Vector2(12, -14), Vector2(12, 18),
		Vector2(6, 22), Vector2(-6, 22), Vector2(-12, 18), Vector2(-12, -14)])
	hull.color = color
	add_child(hull)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([
		Vector2(-6, -20), Vector2(6, -20), Vector2(6, -16), Vector2(-6, -16)])
	stripe.color = color.lightened(0.35)
	add_child(stripe)

func _physics_process(delta: float) -> void:
	_invuln -= delta
	_dash_cooldown -= delta
	_dash_time -= delta
	if regen > 0.0 and hp > 0.0:
		hp = minf(hp + regen * delta, max_hp)

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0 and input_dir != Vector2.ZERO:
		_dash_time = 0.15
		_dash_cooldown = 1.0
		_invuln = maxf(_invuln, 0.25)
		Sfx.play("dash")
	var speed := move_speed * (2.4 if _dash_time > 0.0 else 1.0)
	velocity = input_dir * speed
	move_and_slide()
	if input_dir != Vector2.ZERO:
		rotation = lerp_angle(rotation, input_dir.angle() + PI / 2.0, 8.0 * delta)

# --- Weapon slot management (shop hooks) ---

func has_empty_slot() -> bool:
	for m in mounts:
		if m.weapon_key == "":
			return true
	return false

func lowest_mount_with(key: String) -> WeaponMount:
	var best: WeaponMount = null
	for m in mounts:
		if m.weapon_key == key and (best == null or m.level < best.level):
			best = m
	return best

## Duplicate purchases upgrade the owned copy; otherwise fill an empty slot.
func buy_weapon(key: String) -> void:
	var owned := lowest_mount_with(key)
	if owned != null and owned.level < WeaponData.MAX_LEVEL:
		owned.set_weapon(key, owned.level + 1)
		Fx.float_text(global_position, "%s → Lv %d" % [WeaponData.WEAPONS[key].label, owned.level], Color(0.5, 0.9, 1.0))
		return
	for m in mounts:
		if m.weapon_key == "":
			m.set_weapon(key, 1)
			Fx.float_text(global_position, "%s mounted" % WeaponData.WEAPONS[key].label, Color(0.5, 0.9, 1.0))
			return

func apply_stat(id: String) -> void:
	match id:
		"max_hp":
			max_hp += 15.0
			hp = minf(hp + 15.0, max_hp)
		"damage":
			damage_mult *= 1.08
		"fire_rate":
			fire_rate_mult *= 1.08
		"speed":
			move_speed *= 1.06
		"range":
			range_mult *= 1.08
		"regen":
			regen += 0.6
		"armor":
			armor += 1.0

func take_damage(amount: float) -> void:
	if _invuln > 0.0 or hp <= 0.0:
		return
	hp -= maxf(1.0, amount - armor)
	_invuln = 0.6
	Fx.flash(self)
	Fx.shake(4.0)
	Sfx.play("player_hit")
	if hp <= 0.0:
		hp = 0.0
		hide()
		set_physics_process(false)
		collision_layer = 0
		died.emit()
