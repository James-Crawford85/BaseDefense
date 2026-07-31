class_name Hud
extends CanvasLayer
## All screen-space UI: HUD bars/labels, wave messages, shop, menu and results
## overlays. Runs in ALWAYS process mode so menus work while the tree is paused.

const BAR_W := 200.0

var main  # main.gd (untyped: it has no class_name)
var _w: float
var _h: float
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
var _results_overlay: Control
var _results_title: Label
var _results_stats: Label
var _results_hint: Label
var _levelup_overlay: Control
var _levelup_sub: Label
var _levelup_buttons: Array = []
var _levelup_ids: Array = []
var _kits_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var vs := get_viewport().get_visible_rect().size
	_w = vs.x
	_h = vs.y
	_build_hud()
	_build_shop()
	_build_results()
	_build_levelup()
	Game.money_changed.connect(_on_money_changed)
	_on_money_changed(Game.money)

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

	_kits_label = _label(self, "", Vector2(0, _h - 26), 14, Color(0.5, 0.9, 1.0))
	_kits_label.size = Vector2(_w, 20)
	_kits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kits_label.visible = false

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

func _build_results() -> void:
	_results_overlay = _overlay()
	_results_title = _centered_label(_results_overlay, "", _h * 0.2, 42)
	_results_stats = _centered_label(_results_overlay, "", _h * 0.32, 22, Color(0.85, 0.85, 0.9))
	_results_stats.size.y = 120
	_results_hint = _centered_label(_results_overlay, "", _h * 0.55, 20, Color(1.0, 0.9, 0.4))

## Level-ups pause the game and demand a pick before play resumes (in co-op,
## every banked pick is resolved here one at a time before unpausing).
func _build_levelup() -> void:
	_levelup_overlay = _overlay()
	_centered_label(_levelup_overlay, "LEVEL UP!", _h * 0.18, 40, Color(0.5, 0.95, 0.55))
	_levelup_sub = _centered_label(_levelup_overlay, "Choose an upgrade to continue", _h * 0.30, 18, Color(0.85, 0.85, 0.9))
	var btn_w := 240.0
	var gap := 12.0
	var x0 := (_w - (btn_w * 3 + gap * 2)) / 2.0
	for i in range(3):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(x0 + i * (btn_w + gap), _h * 0.42)
		b.custom_minimum_size = Vector2(btn_w, 96)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_levelup_pick.bind(i))
		_levelup_overlay.add_child(b)
		_levelup_buttons.append(b)

func _open_levelup() -> void:
	_levelup_ids = CardPool.draw_stat_picks(3)
	_levelup_sub.text = "Choose an upgrade to continue"
	for i in range(3):
		var s: Dictionary = CardPool.STATS[_levelup_ids[i]]
		_levelup_buttons[i].text = "%s\n%s" % [s.label, s.desc]
		_levelup_buttons[i].visible = true
	_levelup_overlay.visible = true
	get_tree().paused = true

func _on_levelup_pick(i: int) -> void:
	if Game.pending_picks <= 0:
		return
	Sfx.play("buy", 0.0)
	main.levelup_pick(_levelup_ids[i])
	Game.pending_picks -= 1
	if Game.pending_picks > 0:
		_open_levelup()  # next banked level, fresh options
		return
	if Net.active():
		# Everyone picks; the host resumes play once the whole squad is done.
		_levelup_sub.text = "Waiting for the rest of the squad..."
		for b in _levelup_buttons:
			b.visible = false
		main.levelup_done()
		return
	_levelup_overlay.visible = false
	if main.state == main.State.WAVE or main.state == main.State.INTERMISSION:
		get_tree().paused = false

## All peers finished their picks (multiplayer resume).
func levelup_all_done() -> void:
	_levelup_overlay.visible = false

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

	var kits: Array = main.tower_kits
	_kits_label.visible = not kits.is_empty()
	if not kits.is_empty():
		var extra := "" if kits.size() == 1 else " (+%d more queued)" % (kits.size() - 1)
		_kits_label.text = "[E] Deploy %s Tower%s" % [TowerData.TYPES[kits[0]].label, extra]

	# Level-ups interrupt play: pause and force the pick before continuing.
	if main.state == main.State.WAVE or main.state == main.State.INTERMISSION:
		if Game.pending_picks > 0 and not _levelup_overlay.visible:
			_open_levelup()
	elif _levelup_overlay.visible:
		_levelup_overlay.visible = false  # run ended mid-pick

	match main.state:
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
	_results_stats.text = "Waves survived: %d / %d\nKills: %d\nTotal earned: $%d" % [
		Game.waves_survived, main.FINAL_WAVE, Game.kills, Game.total_earned]
	if Net.active() and not Net.hosting():
		_results_hint.text = "Waiting for the host to return to the lobby..."
	elif Net.active():
		_results_hint.text = "Press Enter / Start to bring the squad back to the lobby"
	else:
		_results_hint.text = "Press Enter / Start to play again"
	_results_overlay.visible = true
