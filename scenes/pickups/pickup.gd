class_name Pickup
extends Node2D
## Gold coin or XP orb dropped by dying enemies. Scatters, then magnets to the
## player once they're within pickup radius (or from anywhere when `vacuum` is
## set at wave end). No physics body — plain distance checks.

var kind := "gold"  # "gold" | "xp"
var value := 1
var vacuum := false
var net_id: int = 0
## Client-side mirror: drifts toward snapshot positions, never collects
## (the host detects collection and broadcasts it).
var puppet := false

var _vel := Vector2.ZERO
var _net_pos := Vector2.ZERO

func _ready() -> void:
	add_to_group("pickups")
	z_index = 5
	if puppet:
		_net_pos = position
		set_physics_process(false)
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
		_collect(p)
		return
	var radius: float = 1e9 if vacuum else p.pickup_radius
	if d < radius:
		global_position = global_position.move_toward(
			p.global_position, (280.0 + (radius - d) * 3.0) * delta)

func _process(delta: float) -> void:
	if puppet:
		position = position.lerp(_net_pos, minf(1.0, 10.0 * delta))

func net_pos(pos: Vector2) -> void:
	_net_pos = pos

## Nearest living tank — in co-op the drop magnets to whoever is closest.
func _find_player() -> Player:
	var best: Player = null
	var best_d := 1e18
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.hp <= 0.0:
			continue
		var d := p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _collect(p: Player) -> void:
	if kind == "gold":
		Game.add_money(maxi(1, int(round(value * p.greed))))
		Sfx.play("pickup_gold")
	else:
		Game.add_xp(value)
		Sfx.play("pickup_xp")
	if Net.game != null:
		Net.game.host_pickup_taken(self)
	queue_free()
