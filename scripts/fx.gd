extends Node
## Autoload: cheap juice helpers — screen shake, hit flash, floating text.
## main.gd registers `camera` and `world` each time the scene (re)loads.
## In multiplayer the host broadcasts shake/boom/float_text so clients see the
## same juice; local calls on clients stay local (their own UI feedback).

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
	if Net.hosting():
		rpc(&"_net_shake", strength)
	_shake_local(strength)

func flash(item: CanvasItem) -> void:
	if not is_instance_valid(item):
		return
	item.modulate = Color(3, 3, 3)
	var t := item.create_tween()
	t.tween_property(item, "modulate", Color.WHITE, 0.15)

func boom(pos: Vector2, radius: float, color: Color) -> void:
	if Net.hosting():
		rpc(&"_net_boom", pos, radius, color)
	_boom_local(pos, radius, color)

func float_text(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	if Net.hosting():
		rpc(&"_net_float_text", pos, text, color)
	_float_text_local(pos, text, color)

@rpc("authority", "reliable")
func _net_shake(strength: float) -> void:
	_shake_local(strength)

@rpc("authority", "reliable")
func _net_boom(pos: Vector2, radius: float, color: Color) -> void:
	_boom_local(pos, radius, color)

@rpc("authority", "reliable")
func _net_float_text(pos: Vector2, text: String, color: Color) -> void:
	_float_text_local(pos, text, color)

func _shake_local(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)

func _boom_local(pos: Vector2, radius: float, color: Color) -> void:
	if world == null or not is_instance_valid(world):
		return
	var n := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	n.polygon = pts
	n.color = Color(color.r, color.g, color.b, 0.45)
	n.position = pos
	n.scale = Vector2(0.4, 0.4)
	n.z_index = 50
	world.add_child(n)
	_shake_local(3.0)
	var t := n.create_tween()
	t.set_parallel(true)
	t.tween_property(n, "scale", Vector2.ONE, 0.22)
	t.tween_property(n, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(n.queue_free)

func _float_text_local(pos: Vector2, text: String, color: Color) -> void:
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
