class_name HealthBar
extends Node2D
## Tiny world-space health bar. Hidden while at full HP unless show_when_full.

var width: float = 40.0
var height: float = 5.0
var show_when_full: bool = false

var _frac: float = 1.0

func set_health(hp: float, max_hp: float) -> void:
	_frac = clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	if _frac >= 1.0 and not show_when_full:
		return
	draw_rect(Rect2(-width / 2.0, -height / 2.0, width, height), Color(0, 0, 0, 0.6))
	var col := Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), _frac)
	draw_rect(Rect2(-width / 2.0, -height / 2.0, width * _frac, height), col)
