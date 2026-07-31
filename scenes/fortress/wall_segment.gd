class_name WallSegment
extends StaticBody2D
## One segment of the fortress wall. Darkens as it takes damage; when destroyed
## it becomes a passable ruin (node kept alive so the shop can rebuild it).

var seg_size := Vector2(40, 96)  # set by main before add_child to fit the wall slots

var max_hp: float = 250.0
var hp: float = 250.0
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
	_poly.polygon = _crenellated_outline()
	add_child(_poly)
	_bar = HealthBar.new()
	_bar.width = seg_size.x - 6.0
	_bar.position = Vector2(0, -seg_size.y / 2.0 - 8.0)
	add_child(_bar)
	_update_visual()

## Rectangle with three merlon teeth on the RIGHT edge (facing the enemy
## approach), so segments read as fortification on their own now that the
## background art has none baked in.
func _crenellated_outline() -> PackedVector2Array:
	var hw := seg_size.x / 2.0
	var hh := seg_size.y / 2.0
	var th := 8.0  # tooth height
	var sh := seg_size.y / 5.0  # 5 sections: tooth, gap, tooth, gap, tooth
	var pts := PackedVector2Array()
	pts.append(Vector2(-hw, -hh))
	pts.append(Vector2(hw - th, -hh))
	for i in range(5):
		var y0 := -hh + i * sh
		var y1 := y0 + sh
		if i % 2 == 0:
			pts.append(Vector2(hw - th, y0))
			pts.append(Vector2(hw, y0))
			pts.append(Vector2(hw, y1))
			pts.append(Vector2(hw - th, y1))
	pts.append(Vector2(hw - th, hh))
	pts.append(Vector2(-hw, hh))
	return pts

func take_damage(amount: float) -> void:
	if destroyed or not Net.is_authority():
		return
	hp -= amount
	Fx.flash(self)
	Sfx.play("wall_hit")
	_update_visual()
	if hp <= 0.0:
		_destroy()

## Snapshot mirror on clients: handles damage, breach and rebuild transitions.
func net_apply(new_hp: float, new_max: float, new_destroyed: bool) -> void:
	max_hp = new_max
	if new_destroyed and not destroyed:
		hp = 0.0
		_destroy()
		return
	if not new_destroyed and destroyed:
		rebuild()
	if new_hp < hp:
		Fx.flash(self)
		Sfx.play("wall_hit")
	hp = new_hp
	_update_visual()

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
	Sfx.play("explode_small")
	Sfx.play("wall_breach", 0.0)

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
