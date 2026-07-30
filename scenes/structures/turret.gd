class_name Turret
extends StaticBody2D
## Player-purchased tower placed OUTSIDE the walls. Type comes from TowerData:
## bullet towers fire single-target shots, cannon fires slow AoE shells,
## flame ticks cone damage on everything in front of it.

static var damage_mult: float = 1.0

var type_key := "standard"
var stats: Dictionary
var max_hp: float
var hp: float

var _cooldown: float = 0.0
var _bar: HealthBar
var _cone: Polygon2D

func setup(key: String) -> void:
	type_key = key
	stats = TowerData.TYPES[key]

func _ready() -> void:
	if stats.is_empty():
		stats = TowerData.TYPES[type_key]
	max_hp = stats.hp
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

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	base.color = stats.color
	add_child(base)
	var barrel := Polygon2D.new()
	barrel.polygon = PackedVector2Array([Vector2(0, -s * 0.7), Vector2(s * 0.55, s * 0.35), Vector2(-s * 0.55, s * 0.35)])
	barrel.color = Color(0.9, 0.93, 1.0, 0.85)
	add_child(barrel)

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

	_bar = HealthBar.new()
	_bar.width = stats.body_size + 6.0
	_bar.position = Vector2(0, -s - 12.0)
	add_child(_bar)

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if stats.behavior == "flame":
		_flame_tick()
	else:
		_shoot_tick()

func _shoot_tick() -> void:
	if _cooldown > 0.0:
		return
	var target := Targeting.nearest_enemy(get_tree(), global_position, stats.range)
	if target == null:
		return
	var aoe: float = stats.get("aoe_radius", 0.0)
	var p := Projectile.new()
	p.setup(target.global_position - global_position, stats.damage * damage_mult,
		stats.range + 80.0, stats.color.lightened(0.35), false, aoe,
		420.0 if aoe > 0.0 else 600.0)
	p.position = global_position
	get_parent().add_child(p)
	_cooldown = 1.0 / stats.fire_rate

func _flame_tick() -> void:
	var target := Targeting.nearest_enemy(get_tree(), global_position, stats.range)
	if target == null:
		_cone.visible = false
		return
	var dir := (target.global_position - global_position).normalized()
	_cone.rotation = dir.angle()
	_cone.visible = true
	if _cooldown > 0.0:
		return
	_cooldown = 1.0 / stats.fire_rate
	var half := deg_to_rad(stats.cone_degrees) / 2.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Enemy
		if n == null:
			continue
		var off := n.global_position - global_position
		if off.length() <= stats.range and absf(dir.angle_to(off)) <= half:
			n.take_damage(stats.damage * damage_mult)

func take_damage(amount: float) -> void:
	hp -= amount
	Fx.flash(self)
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		Fx.float_text(global_position, "%s tower destroyed!" % stats.label, Color(1, 0.4, 0.3))
		Fx.shake(5.0)
		queue_free()
