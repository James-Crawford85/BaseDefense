class_name Turret
extends StaticBody2D
## Player-purchased tower placed OUTSIDE the walls. Type comes from TowerData:
## bullet towers fire single-target shots, cannon fires slow AoE shells,
## flame ticks cone damage on everything in front of it.

static var damage_mult: float = 1.0

const SHOT_SFX := {"gatling": "shot_mg", "standard": "shot_auto", "cannon": "shot_cannon"}

var type_key := "standard"
var stats: Dictionary
var max_hp: float
var hp: float
# Engineering bonuses from the deploying player, locked in at placement.
var eng_damage: float = 1.0
var eng_hp: float = 1.0
var net_id: int = 0
## Client-side mirror in multiplayer: tracks targets visually but never fires
## or takes damage — shots/HP come from the host.
var puppet := false

var _cooldown: float = 0.0
var _bar: HealthBar
var _cone: Polygon2D
var _head: Sprite2D

func setup(key: String) -> void:
	type_key = key
	stats = TowerData.TYPES[key]

func _ready() -> void:
	if stats.is_empty():
		stats = TowerData.TYPES[type_key]
	max_hp = stats.hp * eng_hp
	hp = max_hp
	add_to_group("structures")
	collision_layer = 1 << 4
	collision_mask = 0

	var s: float = stats.body_size / 2.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * stats.body_size
	shape.shape = rect
	add_child(shape)

	# Static base plate + turret head that rotates to track targets. The head
	# art faces UP with the barrels extending past the ring, so its rotation
	# pivot is the ring center (w/2 from the sides, w/2 up from the bottom),
	# not the image center — offset shifts that point onto the node origin.
	var base := Sprite2D.new()
	base.texture = load("res://assets/Turret_Base.png")
	base.scale = Vector2.ONE * (stats.body_size * 1.6 / base.texture.get_width())
	add_child(base)

	_head = Sprite2D.new()
	_head.texture = load(stats.sprite)
	var tw := float(_head.texture.get_width())
	var th := float(_head.texture.get_height())
	_head.centered = false
	_head.offset = Vector2(-tw / 2.0, -(th - tw / 2.0))
	_head.scale = Vector2.ONE * (stats.body_size * 1.35 / tw)
	add_child(_head)

	if stats.behavior == "flame":
		_cone = Polygon2D.new()
		var pts := PackedVector2Array([Vector2.ZERO])
		var half := deg_to_rad(stats.cone_degrees) / 2.0
		for i in range(7):
			var a := -half + (half * 2.0) * i / 6.0
			pts.append(Vector2(cos(a), sin(a)) * stats.range)
		_cone.polygon = pts
		_cone.color = Color(1.0, 0.55, 0.2, 0.25)
		_cone.visible = false
		add_child(_cone)
		move_child(_cone, _head.get_index())  # cone renders under the head

	_bar = HealthBar.new()
	_bar.width = stats.body_size + 6.0
	_bar.position = Vector2(0, s + 12.0)  # below the base; barrels occupy the top
	add_child(_bar)

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	var target := Targeting.nearest_enemy(get_tree(), global_position, stats.range)
	if target != null:
		# Head art faces up (-y), so aiming right (angle 0) needs +90°.
		var aim := (target.global_position - global_position).angle() + PI / 2.0
		_head.rotation = lerp_angle(_head.rotation, aim, 10.0 * delta)
	if stats.behavior == "flame":
		_flame_tick(target)
	else:
		_shoot_tick(target)

func _shoot_tick(target: Node2D) -> void:
	if _cooldown > 0.0 or target == null or puppet:
		return
	var aoe: float = stats.get("aoe_radius", 0.0)
	var dir := (target.global_position - global_position).normalized()
	var speed := 420.0 if aoe > 0.0 else 600.0
	var p := Projectile.new()
	p.setup(dir, stats.damage * damage_mult * eng_damage,
		stats.range + 80.0, stats.color.lightened(0.35), false, aoe, speed)
	p.position = global_position + dir * stats.body_size * 0.5
	get_parent().add_child(p)
	_cooldown = 1.0 / stats.fire_rate
	var sfx: String = SHOT_SFX.get(type_key, "shot_auto")
	Sfx.play(sfx)
	if Net.game != null:
		Net.game.broadcast_shot(p.position, dir, speed, stats.range + 80.0,
			stats.color.lightened(0.35), sfx)

func _flame_tick(target: Node2D) -> void:
	if target == null:
		_cone.visible = false
		return
	var dir := (target.global_position - global_position).normalized()
	_cone.rotation = dir.angle()
	_cone.visible = true
	if _cooldown > 0.0 or puppet:
		return
	_cooldown = 1.0 / stats.fire_rate
	Sfx.play("flame")
	if Net.hosting():
		Net.game.rpc(&"cl_sfx", "flame")
	var half := deg_to_rad(stats.cone_degrees) / 2.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Enemy
		if n == null:
			continue
		var off := n.global_position - global_position
		if off.length() <= stats.range and absf(dir.angle_to(off)) <= half:
			n.take_damage(stats.damage * damage_mult * eng_damage)

func take_damage(amount: float) -> void:
	if puppet:
		return
	hp -= amount
	Fx.flash(self)
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		Fx.float_text(global_position, "%s tower destroyed!" % stats.label, Color(1, 0.4, 0.3))
		death_fx()
		if Net.game != null:
			Net.game.host_turret_died(self)
		queue_free()

func death_fx() -> void:
	Fx.shake(5.0)
	Sfx.play("explode_small")

## Snapshot HP mirror for puppets.
func net_hp(new_hp: float) -> void:
	if new_hp < hp:
		Fx.flash(self)
	hp = new_hp
	_bar.set_health(hp, max_hp)
