extends Node
## Autoload: cheap juice helpers — screen shake, hit flash, floating text.
## main.gd registers `camera` and `world` each time the scene (re)loads.

var camera: Camera2D
var world: Node2D
var _shake_strength: float = 0.0

func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if _shake_strength > 0.1:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_strength
		_shake_strength = lerpf(_shake_strength, 0.0, 8.0 * delta)
	else:
		_shake_strength = 0.0
		camera.offset = Vector2.ZERO

func shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)

func flash(item: CanvasItem) -> void:
	if not is_instance_valid(item):
		return
	item.modulate = Color(3, 3, 3)
	var t := item.create_tween()
	t.tween_property(item, "modulate", Color.WHITE, 0.15)

func float_text(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	if world == null or not is_instance_valid(world):
		return
	var label := Label.new()
	label.text = text
	label.position = pos + Vector2(-24, -26)
	label.z_index = 100
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	world.add_child(label)
	var t := label.create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position", label.position + Vector2(0, -40), 0.7)
	t.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.25)
	t.chain().tween_callback(label.queue_free)
