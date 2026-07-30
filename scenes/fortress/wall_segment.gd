class_name WallSegment
extends StaticBody2D
## One segment of the fortress wall. Darkens as it takes damage; when destroyed
## it becomes a passable ruin (node kept alive so the shop can rebuild it).

var seg_size := Vector2(96, 40)  # set by main before add_child to fit the wall slots

var max_hp: float = 120.0
var hp: float = 120.0
var destroyed: bool = false

var _poly: Polygon2D
var _bar: HealthBar
var _shape: CollisionShape2D

func _ready() -> void:
	add_to_group("walls")
	collision_layer = 1 << 0
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = seg_size
	_shape.shape = rect
	add_child(_shape)
	_poly = Polygon2D.new()
	var h := seg_size / 2.0
	_poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	add_child(_poly)
	_bar = HealthBar.new()
	_bar.width = seg_size.x - 12.0
	_bar.position = Vector2(0, -seg_size.y / 2.0 - 10.0)
	add_child(_bar)
	_update_visual()

func take_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	Fx.flash(self)
	_update_visual()
	if hp <= 0.0:
		_destroy()

func _update_visual() -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	if destroyed:
		_poly.color = Color(0.2, 0.16, 0.14, 0.35)
	else:
		_poly.color = Color(0.5, 0.5, 0.56).lerp(Color(0.32, 0.24, 0.2), 1.0 - frac)
	_bar.set_health(hp, max_hp)

func _destroy() -> void:
	destroyed = true
	hp = 0.0
	_shape.set_deferred("disabled", true)
	_bar.visible = false
	_update_visual()
	Fx.shake(8.0)
	Fx.float_text(global_position, "WALL BREACHED!", Color(1, 0.4, 0.3))

func rebuild() -> void:
	destroyed = false
	hp = max_hp
	_shape.set_deferred("disabled", false)
	_bar.visible = true
	_update_visual()

func repair_full() -> void:
	if destroyed:
		return
	hp = max_hp
	_update_visual()

func reinforce(mult: float) -> void:
	max_hp *= mult
	hp *= mult
	_update_visual()
