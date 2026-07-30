class_name Pickup
extends Node2D
## Gold coin or XP orb dropped by dying enemies. Scatters, then magnets to the
## player once they're within pickup radius (or from anywhere when `vacuum` is
## set at wave end). No physics body — plain distance checks.

var kind := "gold"  # "gold" | "xp"
var value := 1
var vacuum := false

var _vel := Vector2.ZERO

func _ready() -> void:
	add_to_group("pickups")
	z_index = 5
	_vel = Vector2.from_angle(randf() * TAU) * randf_range(50.0, 130.0)
	var poly := Polygon2D.new()
	if kind == "gold":
		var pts := PackedVector2Array()
		for i in range(8):
			var a := TAU * i / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 5.0)
		poly.polygon = pts
		poly.color = Color(1.0, 0.85, 0.25)
	else:
		poly.polygon = PackedVector2Array([Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)])
		poly.color = Color(0.4, 0.95, 0.55)
	add_child(poly)

func _physics_process(delta: float) -> void:
	_vel = _vel.lerp(Vector2.ZERO, 6.0 * delta)
	position += _vel * delta
	var p := _find_player()
	if p == null:
		return
	var d := global_position.distance_to(p.global_position)
	if d < 20.0:
		_collect()
		return
	var radius: float = 1e9 if vacuum else p.pickup_radius
	if d < radius:
		global_position = global_position.move_toward(
			p.global_position, (280.0 + (radius - d) * 3.0) * delta)

func _find_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.hp > 0.0:
			return p
	return null

func _collect() -> void:
	if kind == "gold":
		Game.add_money(value)
		Sfx.play("pickup_gold")
	else:
		Game.add_xp(value)
		Sfx.play("pickup_xp")
	queue_free()
