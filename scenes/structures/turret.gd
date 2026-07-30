class_name Turret
extends StaticBody2D
## Player-purchased auto-turret placed OUTSIDE the walls. High DPS for the money,
## but enemies will attack it — the risk/reward heart of the outer-structures idea.

static var damage_mult: float = 1.0

var max_hp: float = 80.0
var hp: float = 80.0
var base_damage: float = 10.0
var fire_rate: float = 2.5
var fire_range: float = 350.0

var _cooldown: float = 0.0
var _bar: HealthBar

func _ready() -> void:
	add_to_group("structures")
	collision_layer = 1 << 4
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * 36.0
	shape.shape = rect
	add_child(shape)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([Vector2(-18, -18), Vector2(18, -18), Vector2(18, 18), Vector2(-18, 18)])
	base.color = Color(0.3, 0.42, 0.6)
	add_child(base)
	var barrel := Polygon2D.new()
	barrel.polygon = PackedVector2Array([Vector2(0, -12), Vector2(10, 6), Vector2(-10, 6)])
	barrel.color = Color(0.75, 0.85, 1.0)
	add_child(barrel)
	_bar = HealthBar.new()
	_bar.width = 40.0
	_bar.position = Vector2(0, -30.0)
	add_child(_bar)

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var target := Targeting.nearest_enemy(get_tree(), global_position, fire_range)
		if target != null:
			var p := Projectile.new()
			p.setup(target.global_position - global_position, base_damage * damage_mult, fire_range + 80.0, Color(1.0, 0.75, 0.35))
			p.position = global_position
			get_parent().add_child(p)
			_cooldown = 1.0 / fire_rate

func take_damage(amount: float) -> void:
	hp -= amount
	Fx.flash(self)
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		Fx.float_text(global_position, "Turret destroyed!", Color(1, 0.4, 0.3))
		Fx.shake(5.0)
		queue_free()
