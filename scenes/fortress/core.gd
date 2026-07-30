class_name FortressCore
extends StaticBody2D
## The heart of the base. If it dies, the run is over.

signal core_destroyed

const SIZE := 80.0

var max_hp: float = 300.0
var hp: float = 300.0

var _poly: Polygon2D
var _bar: HealthBar
var _dead: bool = false

func _ready() -> void:
	add_to_group("structures")
	collision_layer = 1 << 4
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * SIZE
	shape.shape = rect
	add_child(shape)
	_poly = Polygon2D.new()
	var h := SIZE / 2.0
	# Diamond so the core reads differently from the square walls.
	_poly.polygon = PackedVector2Array([Vector2(0, -h), Vector2(h, 0), Vector2(0, h), Vector2(-h, 0)])
	_poly.color = Color(0.3, 0.85, 0.8)
	add_child(_poly)
	_bar = HealthBar.new()
	_bar.width = SIZE
	_bar.position = Vector2(0, -h - 12.0)
	add_child(_bar)

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	Fx.flash(self)
	Fx.shake(3.0)
	Sfx.play("core_hit")
	_bar.set_health(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		_dead = true
		_poly.color = Color(0.2, 0.25, 0.25)
		core_destroyed.emit()
