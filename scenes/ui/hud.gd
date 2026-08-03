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
var _shield_bar_bg: ColorRect
var _shield_fill: ColorRect
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
var _tower_btns: Array = []   # [{btn, cost, key}] for the live build sidebar
var _build_hint: Label
var _stats_panel: PanelContainer
var _stats_labels: Dictionary = {}
var _stats_visible := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var vs := get_viewport().get_visible_rect().size
	_w = vs.x
	_h = vs.y
	_build_frame()
	_build_hud()
	_build_towerbar()
	_build_stats_panel()
	_build_shop()
	_build_results()
	_build_levelup()
	Game.money_changed.connect(_on_money_changed)
	_on_money_changed(Game.money)

## The metal HUD frame with its playfield window keyed out. Sits behind every
## other HUD element (added first) so text/bars/buttons render on its borders.
func _build_frame() -> void:
	if not ResourceLoader.exists("res://assets/ui/ingame_frame.png"):
		return
	var f := TextureRect.new()
	f.texture = load("res://assets/ui/ingame_frame.png")
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(f)

func _build_hud() -> void:
	_money_label = _label(self, "$0", Vector2(16, 8), 22, Color(1.0, 0.9, 0.4))
	_wave_label = _label(self, "Wave –", Vector2(_w / 2.0 - 150, 10), 20)
	_wave_label.size = Vector2(300, 30)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label = _label(self, "Kills: 0", Vector2(_w - 100, 12), 16)
	_label(self, "[Tab] Stats", Vector2(_w - 100, 34), 12, Color(0.6, 0.64, 0.7))

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
	# Shield sub-bar, just above the HP bar (hidden when the tank has no shield).
	_shield_bar_bg = ColorRect.new()
	_shield_bar_bg.color = Color(0, 0, 0, 0.55)
	_shield_bar_bg.position = Vector2(16, _h - 35)
	_shield_bar_bg.size = Vector2(BAR_W, 5)
	_shield_bar_bg.visible = false
	add_child(_shield_bar_bg)
	_shield_fill = ColorRect.new()
	_shield_fill.color = Color(0.4, 0.8, 1.0)
	_shield_fill.position = Vector2(1, 1)
	_shield_fill.size = Vector2(0, 3)
	_shield_bar_bg.add_child(_shield_fill)
	var cbar := _build_bar(Vector2(_w - BAR_W - 16, _h - 28), "CORE", Color(0.3, 0.85, 0.8))
	_core_fill = cbar.fill
	_core_value = cbar.value

	_build_hint = _label(self, "", Vector2(0, _h - 48), 15, Color(0.6, 0.95, 1.0))
	_build_hint.size = Vector2(_w, 20)
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hint.visible = false

## Live RTS build sidebar down the left edge: click a tower, then click the
## field to place it. Buttons dim when you can't afford them (see _process).
func _build_towerbar() -> void:
	var header := _label(self, "BUILD", Vector2(10, _h * 0.30 - 22), 13, Color(0.7, 0.8, 0.9))
	header.set_meta("towerbar", true)
	var keys: Array = TowerData.TYPES.keys()
	for i in range(keys.size()):
		var key: String = keys[i]
		var t: Dictionary = TowerData.TYPES[key]
		var b := Button.new()
		b.text = "%s\n$%d" % [t.label, int(t.cost)]
		b.position = Vector2(10, _h * 0.30 + i * 60)
		b.custom_minimum_size = Vector2(118, 52)
		b.size = Vector2(118, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		_style_tower_btn(b, t.color)
		b.pressed.connect(func(): main.begin_placement(key))
		add_child(b)
		_tower_btns.append({"btn": b, "cost": int(t.cost), "header": header})

func _style_tower_btn(b: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.11, 0.14, 0.92)
	normal.border_color = accent
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(4)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.15, 0.18, 0.22, 0.95)
	hover.set_border_width_all(2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.08, 0.09, 0.1, 0.7)
	disabled.border_color = Color(0.3, 0.32, 0.36)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover.duplicate())
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", accent.lightened(0.4))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.5))

## Toggled with Tab: a live readout of every current stat so players can make
## informed upgrade choices. Grouped Main / Sub like docs/stats.md.
func _build_stats_panel() -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.position = Vector2(_w - 314, 56)
	_stats_panel.custom_minimum_size = Vector2(298, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.93)
	sb.border_color = Color(0.3, 0.35, 0.42)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	_stats_panel.add_theme_stylebox_override("panel", sb)
	_stats_panel.visible = false
	add_child(_stats_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	_stats_panel.add_child(vb)

	_stats_header(vb, "MAIN")
	_stat_row(vb, "hp", "Max HP")
	_stat_row(vb, "damage", "Damage")
	_stat_row(vb, "firerate", "Fire Rate")
	_stat_row(vb, "range", "Range")
	_stat_row(vb, "speed", "Move Speed")
	_stat_row(vb, "armor", "Armor")
	_stats_header(vb, "SUB")
	_stat_row(vb, "crit", "Crit Chance")
	_stat_row(vb, "dodge", "Dodge")
	_stat_row(vb, "regen", "HP Regen")
	_stat_row(vb, "lifesteal", "Lifesteal")
	_stat_row(vb, "greed", "Greed")
	_stat_row(vb, "engineering", "Engineering")
	_stat_row(vb, "pickup", "Pickup Radius")
	_stat_row(vb, "turn", "Turn Rate")
	_stat_row(vb, "projspeed", "Projectile Speed")
	_stat_row(vb, "aoe", "AoE Radius")
	_stat_row(vb, "shield", "Shield")
	_stat_row(vb, "shieldrate", "Shield Recharge")
	_stat_row(vb, "shielddelay", "Shield Delay")

func _stats_header(parent: Node, text: String) -> void:
	var l := _label(parent, text, Vector2.ZERO, 12, Color(1.0, 0.82, 0.35))
	l.add_theme_constant_override("line_spacing", 2)

func _stat_row(parent: Node, id: String, name: String) -> void:
	var row := HBoxContainer.new()
	var n := Label.new()
	n.text = name
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := Label.new()
	v.text = "-"
	v.add_theme_font_size_override("font_size", 13)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	parent.add_child(row)
	_stats_labels[id] = v

func _refresh_stats(p: Player) -> void:
	_stats_labels["hp"].text = "%d / %d" % [ceili(p.hp), int(p.max_hp)]
	_stats_labels["damage"].text = "x%.2f" % p.damage_mult
	_stats_labels["firerate"].text = "x%.2f" % p.fire_rate_mult
	_stats_labels["range"].text = "x%.2f" % p.range_mult
	_stats_labels["speed"].text = "%d" % int(p.move_speed)
	_stats_labels["armor"].text = "%d" % int(p.armor)
	_stats_labels["crit"].text = "%d%%" % roundi(p.crit_chance * 100.0)
	_stats_labels["dodge"].text = "%d%%" % roundi(p.dodge * 100.0)
	_stats_labels["regen"].text = "%.1f/s" % p.regen
	_stats_labels["lifesteal"].text = "%.1f/kill" % p.kill_heal
	_stats_labels["greed"].text = "+%d%%" % roundi((p.greed - 1.0) * 100.0)
	_stats_labels["engineering"].text = "%d" % int(p.engineering)
	_stats_labels["pickup"].text = "%d" % int(p.pickup_radius)
	_stats_labels["turn"].text = "%.1f" % p.turn_speed
	_stats_labels["projspeed"].text = "x%.2f" % p.proj_speed_mult
	_stats_labels["aoe"].text = "x%.2f" % p.aoe_mult
	_stats_labels["shield"].text = ("%d / %d" % [int(p.shield), int(p.shield_max)]) if p.shield_max > 0.0 else "-"
	_stats_labels["shieldrate"].text = "%d%%/s" % roundi(p.shield_recharge_rate * 100.0)
	_stats_labels["shielddelay"].text = "%.1fs" % p.shield_recharge_delay

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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_stats_visible = not _stats_visible
		get_viewport().set_input_as_handled()  # don't let Tab drive focus navigation

func _process(_delta: float) -> void:
	var p: Player = main.player
	# Stats readout: visible while toggled on and we have a live tank to read.
	var show_stats: bool = _stats_visible and p != null and is_instance_valid(p) \
		and (main.state == main.State.WAVE or main.state == main.State.INTERMISSION)
	_stats_panel.visible = show_stats
	if show_stats:
		_refresh_stats(p)
	if p != null and is_instance_valid(p):
		_player_fill.size.x = (BAR_W - 4) * clampf(p.hp / p.max_hp, 0.0, 1.0)
		_player_value.text = "%d / %d" % [ceili(p.hp), int(p.max_hp)]
		_shield_bar_bg.visible = p.shield_max > 0.0
		if p.shield_max > 0.0:
			_shield_fill.size.x = (BAR_W - 2) * clampf(p.shield / p.shield_max, 0.0, 1.0)
	var c: FortressCore = main.core
	if c != null and is_instance_valid(c):
		_core_fill.size.x = (BAR_W - 4) * clampf(c.hp / c.max_hp, 0.0, 1.0)
		_core_value.text = "%d / %d" % [ceili(c.hp), int(c.max_hp)]
	_kills_label.text = "Kills: %d" % Game.kills
	_level_label.text = "Lv %d" % Game.level
	_xp_fill.size.x = _xp_bar_w * clampf(float(Game.xp) / float(Game.xp_needed()), 0.0, 1.0)

	# Live build sidebar: visible only during a run, buttons dim when unaffordable.
	var in_run: bool = main.state == main.State.WAVE or main.state == main.State.INTERMISSION
	for entry in _tower_btns:
		entry.btn.visible = in_run
		entry.header.visible = in_run
		entry.btn.disabled = Game.money < int(entry.cost)
	var placing: bool = main._placing_type != ""
	_build_hint.visible = placing
	if placing:
		_build_hint.text = "Left-click to build  ·  Right-click to cancel"

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
