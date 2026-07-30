class_name Hud
extends CanvasLayer
## All screen-space UI: HUD bars/labels, wave messages, shop, menu and results
## overlays. Runs in ALWAYS process mode so menus work while the tree is paused.

const BAR_W := 220.0

var main  # main.gd (untyped: it has no class_name)

var shop: ShopPanel
var _money_label: Label
var _wave_label: Label
var _kills_label: Label
var _message_label: Label
var _player_fill: ColorRect
var _player_value: Label
var _core_fill: ColorRect
var _core_value: Label
var _menu_overlay: Control
var _results_overlay: Control
var _results_title: Label
var _results_stats: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_hud()
	_build_shop()
	_build_menu()
	_build_results()
	Game.money_changed.connect(_on_money_changed)
	_on_money_changed(Game.money)
	_menu_overlay.visible = true

func _build_hud() -> void:
	_money_label = _label(self, "$0", Vector2(20, 10), 22, Color(1.0, 0.9, 0.4))
	_wave_label = _label(self, "Wave –", Vector2(490, 10), 20)
	_wave_label.size = Vector2(300, 30)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label = _label(self, "Kills: 0", Vector2(1140, 12), 18)

	_message_label = _label(self, "", Vector2(0, 170), 40)
	_message_label.size = Vector2(1280, 60)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.visible = false

	var pbar := _build_bar(Vector2(20, 688), "YOU", Color(0.35, 0.75, 0.95))
	_player_fill = pbar.fill
	_player_value = pbar.value
	var cbar := _build_bar(Vector2(980, 688), "CORE", Color(0.3, 0.85, 0.8))
	_core_fill = cbar.fill
	_core_value = cbar.value

func _build_bar(pos: Vector2, caption: String, fill_color: Color) -> Dictionary:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = pos
	bg.size = Vector2(BAR_W, 18)
	add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 14)
	bg.add_child(fill)
	var cap := _label(self, caption, pos + Vector2(0, -22), 14)
	cap.add_theme_color_override("font_color", fill_color)
	var value := _label(self, "", pos + Vector2(BAR_W + 8, 0), 14)
	return {"fill": fill, "value": value}

func _build_shop() -> void:
	shop = ShopPanel.new()
	shop.main = main
	add_child(shop)

func _build_menu() -> void:
	_menu_overlay = _overlay()
	_centered_label(_menu_overlay, "BASE DEFENSE", 170, 64)
	_centered_label(_menu_overlay, "Hold the line for 10 waves.", 270, 22, Color(0.85, 0.85, 0.9))
	_centered_label(_menu_overlay, "Press Enter / Start to begin", 420, 26, Color(1.0, 0.9, 0.4))
	_centered_label(_menu_overlay,
		"WASD or left stick — move      Space — dash      You fire automatically at the nearest enemy\nBetween waves: spend money on yourself, the walls... or risky turrets outside the walls.",
		510, 16, Color(0.7, 0.7, 0.75))

func _build_results() -> void:
	_results_overlay = _overlay()
	_results_title = _centered_label(_results_overlay, "", 200, 56)
	_results_stats = _centered_label(_results_overlay, "", 320, 24, Color(0.85, 0.85, 0.9))
	_centered_label(_results_overlay, "Press Enter / Start to play again", 480, 22, Color(1.0, 0.9, 0.4))

func _overlay() -> Control:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0.78)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	add_child(rect)
	return rect

func _label(parent: Node, text: String, pos: Vector2, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _centered_label(parent: Control, text: String, y: float, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := _label(parent, text, Vector2(0, y), font_size, color)
	l.size = Vector2(1280, font_size * 2.6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _process(_delta: float) -> void:
	var p: Player = main.player
	if p != null and is_instance_valid(p):
		_player_fill.size.x = (BAR_W - 4) * clampf(p.hp / p.max_hp, 0.0, 1.0)
		_player_value.text = "%d / %d" % [ceili(p.hp), int(p.max_hp)]
	var c: FortressCore = main.core
	if c != null and is_instance_valid(c):
		_core_fill.size.x = (BAR_W - 4) * clampf(c.hp / c.max_hp, 0.0, 1.0)
		_core_value.text = "%d / %d" % [ceili(c.hp), int(c.max_hp)]
	_kills_label.text = "Kills: %d" % Game.kills

	match main.state:
		main.State.MENU:
			if Input.is_action_just_pressed("ui_accept"):
				main.begin_run()
		main.State.GAME_OVER, main.State.VICTORY:
			if Input.is_action_just_pressed("ui_accept"):
				main.restart_run()

func _on_money_changed(amount: int) -> void:
	_money_label.text = "$%d" % amount
	if shop.visible:
		shop.refresh()

func set_wave_label(current: int, total: int) -> void:
	_wave_label.text = "Wave %d / %d" % [current, total]

func show_message(text: String, duration: float) -> void:
	_message_label.text = text
	_message_label.visible = true
	_message_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_message_label, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): _message_label.visible = false)

func hide_menu() -> void:
	_menu_overlay.visible = false

func open_shop() -> void:
	shop.open()

func close_shop() -> void:
	shop.visible = false

func set_countdown(t: float) -> void:
	shop.set_countdown(t)

func show_results(victory: bool) -> void:
	close_shop()
	_results_title.text = "VICTORY!" if victory else "THE BASE HAS FALLEN"
	_results_title.add_theme_color_override("font_color",
		Color(0.4, 0.95, 0.5) if victory else Color(0.95, 0.35, 0.3))
	_results_stats.text = "Waves survived: %d / 10\nKills: %d\nTotal earned: $%d" % [
		Game.waves_survived, Game.kills, Game.total_earned]
	_results_overlay.visible = true
