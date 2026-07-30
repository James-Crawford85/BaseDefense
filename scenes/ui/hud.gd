class_name Hud
extends CanvasLayer
## All screen-space UI: HUD bars/labels, wave messages, shop, menu and results
## overlays. Runs in ALWAYS process mode so menus work while the tree is paused.

const BAR_W := 200.0
const CLASS_ORDER: Array = ["assault", "heavy", "scout"]

var main  # main.gd (untyped: it has no class_name)
var _w: float
var _h: float
var _selected_idx := 0
var _class_panels: Array = []
var _xp_fill: ColorRect
var _level_label: Label
var _xp_bar_w: float

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
	var vs := get_viewport().get_visible_rect().size
	_w = vs.x
	_h = vs.y
	_build_hud()
	_build_shop()
	_build_menu()
	_build_results()
	Game.money_changed.connect(_on_money_changed)
	_on_money_changed(Game.money)
	_menu_overlay.visible = true

func _build_hud() -> void:
	_money_label = _label(self, "$0", Vector2(16, 8), 22, Color(1.0, 0.9, 0.4))
	_wave_label = _label(self, "Wave –", Vector2(_w / 2.0 - 150, 10), 20)
	_wave_label.size = Vector2(300, 30)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label = _label(self, "Kills: 0", Vector2(_w - 100, 12), 16)

	_level_label = _label(self, "Lv 1", Vector2(16, 36), 13, Color(0.5, 0.95, 0.55))
	var xpbg := ColorRect.new()
	xpbg.color = Color(0, 0, 0, 0.5)
	xpbg.position = Vector2(58, 40)
	xpbg.size = Vector2(_w - 74, 8)
	add_child(xpbg)
	_xp_bar_w = _w - 76
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(0.5, 0.9, 0.4)
	_xp_fill.position = Vector2(1, 1)
	_xp_fill.size = Vector2(0, 6)
	xpbg.add_child(_xp_fill)

	_message_label = _label(self, "", Vector2(0, _h * 0.22), 36)
	_message_label.size = Vector2(_w, 60)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.visible = false

	var pbar := _build_bar(Vector2(16, _h - 28), "YOU", Color(0.35, 0.75, 0.95))
	_player_fill = pbar.fill
	_player_value = pbar.value
	var cbar := _build_bar(Vector2(_w - BAR_W - 16, _h - 28), "CORE", Color(0.3, 0.85, 0.8))
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
	var cap := _label(self, caption, pos + Vector2(0, -20), 13)
	cap.add_theme_color_override("font_color", fill_color)
	# Value text centered inside the bar (no room beside it in portrait layout).
	var value := Label.new()
	value.size = Vector2(BAR_W, 18)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	bg.add_child(value)
	return {"fill": fill, "value": value}

func _build_shop() -> void:
	shop = ShopPanel.new()
	shop.main = main
	add_child(shop)

func _build_menu() -> void:
	_menu_overlay = _overlay()
	_centered_label(_menu_overlay, "BASE DEFENSE", _h * 0.07, 44)
	_centered_label(_menu_overlay, "Choose your tank", _h * 0.145, 20, Color(0.85, 0.85, 0.9))
	var panel_w := 172.0
	var gap := 8.0
	var x0 := (_w - (panel_w * 3 + gap * 2)) / 2.0
	for i in range(CLASS_ORDER.size()):
		var data: Dictionary = TankData.CLASSES[CLASS_ORDER[i]]
		var panel := PanelContainer.new()
		panel.position = Vector2(x0 + i * (panel_w + gap), _h * 0.21)
		panel.custom_minimum_size = Vector2(panel_w, 220)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		panel.add_child(vb)
		var name_l := Label.new()
		name_l.text = data.label
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 19)
		name_l.add_theme_color_override("font_color", data.color.lightened(0.4))
		vb.add_child(name_l)
		var stats_l := Label.new()
		stats_l.text = "HP %d\nSpeed %d\nArmor %d\nDamage x%.2f\nSlots: %d\nStarts: %s" % [
			int(data.hp), int(data.speed), int(data.armor), data.damage_mult,
			data.slots.size(), WeaponData.WEAPONS[data.start_weapon].label]
		stats_l.add_theme_font_size_override("font_size", 13)
		vb.add_child(stats_l)
		var blurb_l := Label.new()
		blurb_l.text = data.blurb
		blurb_l.add_theme_font_size_override("font_size", 11)
		blurb_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		blurb_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb_l.custom_minimum_size = Vector2(panel_w - 16, 0)
		vb.add_child(blurb_l)
		panel.gui_input.connect(_on_class_panel_input.bind(i))
		_menu_overlay.add_child(panel)
		_class_panels.append(panel)
	_select_class(0)
	_centered_label(_menu_overlay, "◄ ► to choose — Enter / Start to roll out", _h * 0.52, 20, Color(1.0, 0.9, 0.4))
	var controls := _centered_label(_menu_overlay,
		"WASD / left stick — drive (the hull turns toward your heading)\nSpace — boost · Main turret fires 360°, side mounts only cover\ntheir half — face the fight! Kills drop gold and XP orbs:\ndrive over them to collect. Spend both between waves.",
		_h * 0.6, 14, Color(0.7, 0.7, 0.75))
	controls.size.y = 140

func _on_class_panel_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		_select_class(idx)

func _select_class(i: int) -> void:
	_selected_idx = i
	for j in range(_class_panels.size()):
		_class_panels[j].modulate = Color(1, 1, 1) if j == i else Color(0.55, 0.55, 0.6, 0.85)

func selected_class() -> String:
	return CLASS_ORDER[_selected_idx]

func _build_results() -> void:
	_results_overlay = _overlay()
	_results_title = _centered_label(_results_overlay, "", _h * 0.2, 42)
	_results_stats = _centered_label(_results_overlay, "", _h * 0.32, 22, Color(0.85, 0.85, 0.9))
	_results_stats.size.y = 120
	_centered_label(_results_overlay, "Press Enter / Start to play again", _h * 0.55, 20, Color(1.0, 0.9, 0.4))

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
	l.size = Vector2(_w, font_size * 2.6)
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
	_level_label.text = "Lv %d" % Game.level
	_xp_fill.size.x = _xp_bar_w * clampf(float(Game.xp) / float(Game.xp_needed()), 0.0, 1.0)

	match main.state:
		main.State.MENU:
			if Input.is_action_just_pressed("ui_left"):
				_select_class((_selected_idx + CLASS_ORDER.size() - 1) % CLASS_ORDER.size())
			if Input.is_action_just_pressed("ui_right"):
				_select_class((_selected_idx + 1) % CLASS_ORDER.size())
			if Input.is_action_just_pressed("ui_accept"):
				main.begin_run(selected_class())
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
