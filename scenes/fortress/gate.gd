class_name Gate
extends WallSegment
## A gate fills a gap in the fortress wall: allied tanks drive straight through it,
## but it blocks enemies and can be shot down just like a wall — once destroyed the
## gap is open again. It sits on the "gates" collision layer, which the enemy mask
## includes and the player mask doesn't, so only enemies are stopped by it. Gates
## live in main's wall list, so they repair / reinforce / rebuild with the walls.

func _ready() -> void:
	super._ready()
	# WallSegment registers as a "wall" on the world layer (blocks everyone). Move
	# it to the gates layer/group so allies pass but enemies collide and attack it.
	remove_from_group("walls")
	add_to_group("gates")
	collision_layer = 1 << 6   # "gates"

## Distinct energy-barrier look so a gate reads differently from a solid wall:
## cyan while healthy, shifting to hot damage tones as it fails, faint when down.
func _update_visual() -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	if destroyed:
		_poly.color = Color(0.16, 0.26, 0.30, 0.22)
	else:
		_poly.color = Color(0.30, 0.72, 0.90, 0.60).lerp(Color(0.55, 0.30, 0.22, 0.78), 1.0 - frac)
	if _bar != null:
		_bar.set_health(hp, max_hp)
