class_name Hud
extends CanvasLayer
## All screen-space UI: HUD bars/labels, wave messages, shop, menu and results
## overlays. Runs in ALWAYS process mode so menus work while the tree is paused.

const BAR_W := 200.0

# Readout anchors as fractions of the (canvas) viewport, so each label/bar centers
# inside its frame plate. The frame's left column is thick (BUILD sidebar), so the
# bottom-centre plate sits under the play window rather than at screen centre.
# Nudge these if a readout doesn't sit dead-centre in its plate.
const MONEY_CENTER := Vector2(0.096, 0.057)   # top-left plate
const KILLS_CENTER := Vector2(0.905, 0.057)   # top-right plate
const HULL_CENTER_X := 0.501                    # bottom-centre (screen centre)
const CORE_CENTER_X := 0.839                    # bottom-right plate
const BOTTOM_BAR_CY := 0.950                    # vertical centre of the bottom bars
const BUILD_ORIGIN := Vector2(0.037, 0.392)     # first build button's top-left
const BUILD_SPACING := 68.0                      # vertical gap between build buttons (px)
const LOGO_CENTER := Vector2(0.100, 0.229)      # emblem in the top-left column plate
const LOGO_W := 122.0                            # emblem width (px), height by aspect

# Bar fill colours convey meaning in place of text captions.
const HP_COLOR := Color(0.88, 0.30, 0.28)       # red   — health
const SHIELD_COLOR := Color(0.35, 0.62, 1.0)    # blue  — shield
const CORE_COLOR := Color(0.35, 0.85, 0.45)     # green — core

var main  # main.gd (untyped: it has no class_name)
var _w: float
var _h: float

var shop: ShopPanel
var _money_label: Label
var _wave_label: Label
var _kills_label: Label
var _message_label: Label
var _player_fill: ColorRect
var _player_value: Label
var _player_bar_bg: ColorRect
var _shield_bar_bg: ColorRect
var _shield_fill: ColorRect
var _core_fill: ColorRect
var _core_value: Label
var _core_bar_bg: ColorRect
var _results_overlay: Control
var _results_title: Label
var _results_stats: Label
var _results_hint: Label
var _levelup_overlay: Control
var _levelup_sub: Label
var _levelup_buttons: Array = []
var _levelup_ids: Array = []
var _tower_btns: Array = []   # [{btn, cost, key}] for the live build sidebar
var _btn_tex: Texture2D       # button template for the build buttons
var _logo: TextureRect        # Steel Tide emblem in the top-left column plate
var _build_hint: Label
var _stats_panel: PanelContainer
var _stats_labels: Dictionary = {}
var _stats_visible := false

# --- F9 placement mode: drag HUD readouts to reposition, values printed/copied ---
var _debug_place := false
var _draggables: Array = []      # [{name, primary, group, axes}]
var _drag_group: Array = []      # nodes currently being dragged together
var _drag_last := Vector2.ZERO
var _debug_panel: Label = null

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
	_build_logo()
	_setup_draggables()
	Game.money_changed.connect(_on_money_changed)
	_on_money_changed(Game.money)

## Steel Tide emblem in the empty plate at the top of the left column.
func _build_logo() -> void:
	if not ResourceLoader.exists("res://assets/ui/logo.png"):
		return
	var tex: Texture2D = load("res://assets/ui/logo.png")
	_logo = TextureRect.new()
	_logo.texture = tex
	# expand_mode MUST precede size, or KEEP_SIZE clamps the control to native res.
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lh := LOGO_W * float(tex.get_height()) / float(tex.get_width())
	_logo.size = Vector2(LOGO_W, lh)
	_logo.position = Vector2(LOGO_CENTER.x * _w - LOGO_W / 2.0, LOGO_CENTER.y * _h - lh / 2.0)
	add_child(_logo)

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
	# Money — centred in the top-left plate, stays centred as the number grows.
	_money_label = _centered_box("$0", MONEY_CENTER, 180, 22, Color(1.0, 0.9, 0.4))
	# Wave — top-centre plate.
	_wave_label = _label(self, "Wave –", Vector2(_w / 2.0 - 150, 10), 20)
	_wave_label.size = Vector2(300, 30)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Kills — centred in the top-right plate.
	_kills_label = _centered_box("Kills: 0", KILLS_CENTER, 180, 16)

	_message_label = _label(self, "", Vector2(0, _h * 0.22), 36)
	_message_label.size = Vector2(_w, 60)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Fonts.apply(_message_label, Fonts.alert)  # Oxanium for major alerts
	_message_label.visible = false

	# Combined health/shield unit, centred in the bottom-centre plate: red HP bar
	# with a blue shield strip laid directly above it — colour conveys meaning, so
	# no text caption. Numbers stay centred inside each bar.
	var bar_y := BOTTOM_BAR_CY * _h - 9.0        # bar bg is 18px tall
	var mid_x := HULL_CENTER_X * _w - BAR_W / 2.0
	var pbar := _build_bar(Vector2(mid_x, bar_y), HP_COLOR)
	_player_fill = pbar.fill
	_player_value = pbar.value
	_player_bar_bg = pbar.bg
	# Shield sub-bar, just above the HP bar (hidden when the tank has no shield).
	_shield_bar_bg = ColorRect.new()
	_shield_bar_bg.color = Color(0, 0, 0, 0.55)
	_shield_bar_bg.position = Vector2(mid_x, bar_y - 7.0)
	_shield_bar_bg.size = Vector2(BAR_W, 5)
	_shield_bar_bg.visible = false
	add_child(_shield_bar_bg)
	_shield_fill = ColorRect.new()
	_shield_fill.color = SHIELD_COLOR
	_shield_fill.position = Vector2(1, 1)
	_shield_fill.size = Vector2(0, 3)
	_shield_bar_bg.add_child(_shield_fill)
	# Core — green bar centred in the bottom-right plate.
	var cbar := _build_bar(Vector2(CORE_CENTER_X * _w - BAR_W / 2.0, bar_y), CORE_COLOR)
	_core_fill = cbar.fill
	_core_value = cbar.value
	_core_bar_bg = cbar.bg

	# Placement hint sits above the bar group so it never overlaps the HULL caption.
	_build_hint = _label(self, "", Vector2(0, _h - 68), 15, Color(0.6, 0.95, 1.0))
	_build_hint.size = Vector2(_w, 20)
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hint.visible = false

## Live RTS build sidebar down the left edge: click a tower, then click the
## field to place it. Buttons dim when you can't afford them (see _process).
func _build_towerbar() -> void:
	if ResourceLoader.exists("res://assets/ui/InGameUI_Button_keyed.png"):
		_btn_tex = load("res://assets/ui/InGameUI_Button_keyed.png")
	var ox := BUILD_ORIGIN.x * _w
	var oy := BUILD_ORIGIN.y * _h
	var header := _label(self, "// BUILD", Vector2(ox + 2, oy - 26), 15, Color(0.72, 0.82, 0.92))
	Fonts.apply(header, Fonts.title)  # Oxanium section header
	header.set_meta("towerbar", true)
	var btn_size := Vector2(156, 62)
	var keys: Array = TowerData.TYPES.keys()
	for i in range(keys.size()):
		var key: String = keys[i]
		var t: Dictionary = TowerData.TYPES[key]
		var b := Button.new()
		b.position = Vector2(ox, oy + i * BUILD_SPACING)
		b.custom_minimum_size = btn_size
		b.size = btn_size
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = false
		_style_tower_btn(b)
		_tower_btn_content(b, t, btn_size)
		b.pressed.connect(func(): main.begin_placement(key))
		add_child(b)
		_tower_btns.append({"btn": b, "cost": int(t.cost), "header": header})

## Applies the button_hud.png template as a nine-patch (matching the menu's HUD
## buttons), with a flat fallback when the art hasn't imported (headless).
func _style_tower_btn(b: Button) -> void:
	if _btn_tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.1, 0.12, 0.16, 0.92)
		flat.border_color = Color(0.35, 0.4, 0.48)
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(5)
		b.add_theme_stylebox_override("normal", flat)
		b.add_theme_stylebox_override("hover", flat)
		b.add_theme_stylebox_override("pressed", flat)
		b.add_theme_stylebox_override("disabled", flat)
		return
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.82, 0.82, 0.88)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(1, 1, 1)))
	b.add_theme_stylebox_override("focus", _btn_style(Color(1, 1, 1)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.62, 0.62, 0.68)))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(0.82, 0.82, 0.88)))

func _btn_style(mod: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _btn_tex   # InGameUI_Button_keyed.png (213x88, ~2.4:1 native)
	# Small margins preserve the rounded corners + border; the flat middle stretches.
	# Target size (156x62) is near the art's native aspect, so distortion is minimal.
	sb.set_texture_margin(SIDE_LEFT, 18)
	sb.set_texture_margin(SIDE_RIGHT, 18)
	sb.set_texture_margin(SIDE_TOP, 16)
	sb.set_texture_margin(SIDE_BOTTOM, 16)
	sb.modulate_color = mod
	return sb

## Turret icon + name + cost drawn as child controls (so we get an icon and two
## type sizes the plain Button.text can't manage). All IGNORE mouse so the button
## still receives the click.
func _tower_btn_content(b: Button, t: Dictionary, size: Vector2) -> void:
	var accent: Color = t.color.lightened(0.45)
	if t.has("sprite") and ResourceLoader.exists(String(t.sprite)):
		var icon := TextureRect.new()
		icon.texture = load(String(t.sprite))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(38, 38)
		icon.position = Vector2(14, size.y / 2.0 - 19)
		b.add_child(icon)
	var name_l := Label.new()
	name_l.text = String(t.label).to_upper()
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Fonts.apply(name_l, Fonts.body_semibold, 16)
	name_l.add_theme_color_override("font_color", accent)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name_l.add_theme_constant_override("outline_size", 4)
	name_l.position = Vector2(60, 11)
	b.add_child(name_l)
	var cost_l := Label.new()
	cost_l.text = "$%d" % int(t.cost)
	cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Fonts.apply(cost_l, Fonts.body, 14)
	cost_l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	cost_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cost_l.add_theme_constant_override("outline_size", 4)
	cost_l.position = Vector2(60, 32)
	b.add_child(cost_l)

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
	Fonts.apply(l, Fonts.title)  # Oxanium section header

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

## A meaning-by-colour bar (no text caption): dark track, coloured fill, and the
## current/max value centred inside it.
func _build_bar(pos: Vector2, fill_color: Color) -> Dictionary:
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
	# Value text centered inside the bar.
	var value := Label.new()
	value.size = Vector2(BAR_W, 18)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	bg.add_child(value)
	return {"fill": fill, "value": value, "bg": bg}

## A fixed-width label whose box is centred on `anchor` (fractions of the viewport),
## with the text centre-aligned so it stays put as the value grows.
func _centered_box(text: String, anchor: Vector2, box_w: float, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box_h := float(font_size) + 12.0
	l.size = Vector2(box_w, box_h)
	l.position = Vector2(anchor.x * _w - box_w / 2.0, anchor.y * _h - box_h / 2.0)
	add_child(l)
	return l

func _build_shop() -> void:
	shop = ShopPanel.new()
	shop.main = main
	add_child(shop)

func _build_results() -> void:
	_results_overlay = _overlay()
	_results_title = _centered_label(_results_overlay, "", _h * 0.2, 42)
	Fonts.apply(_results_title, Fonts.title_bold)  # Oxanium headline
	_results_stats = _centered_label(_results_overlay, "", _h * 0.32, 22, Color(0.85, 0.85, 0.9))
	_results_stats.size.y = 120
	_results_hint = _centered_label(_results_overlay, "", _h * 0.55, 20, Color(1.0, 0.9, 0.4))

## Level-ups pause the game and demand a pick before play resumes (in co-op,
## every banked pick is resolved here one at a time before unpausing).
func _build_levelup() -> void:
	_levelup_overlay = _overlay()
	Fonts.apply(_centered_label(_levelup_overlay, "LEVEL UP!", _h * 0.18, 40, Color(0.5, 0.95, 0.55)), Fonts.title_bold)
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_stats_visible = not _stats_visible
			get_viewport().set_input_as_handled()  # don't let Tab drive focus navigation
			return
		if event.keycode == KEY_F9:
			_toggle_debug_place()
			get_viewport().set_input_as_handled()
			return
	if _debug_place:
		_debug_input(event)

# --- F9 placement mode --------------------------------------------------------

## Register the HUD readouts as draggable handles. `axes` limits which values a
## handle reports (wave only moves horizontally). Bars drag their whole group.
func _setup_draggables() -> void:
	_draggables = [
		{"name": "MONEY_CENTER", "primary": _money_label, "group": [_money_label], "axes": "xy"},
		{"name": "KILLS_CENTER", "primary": _kills_label, "group": [_kills_label], "axes": "xy"},
		{"name": "WAVE (x)", "primary": _wave_label, "group": [_wave_label], "axes": "x"},
		{"name": "HULL_CENTER_X / BOTTOM_BAR_CY", "primary": _player_bar_bg,
			"group": [_player_bar_bg, _shield_bar_bg], "axes": "xy"},
		{"name": "CORE_CENTER_X / BOTTOM_BAR_CY", "primary": _core_bar_bg,
			"group": [_core_bar_bg], "axes": "xy"},
	]
	if _logo != null:
		_draggables.append({"name": "LOGO_CENTER", "primary": _logo, "group": [_logo], "axes": "xy"})
	# The whole BUILD block moves together; grab any button or the header. Reports
	# the first button's top-left (BUILD_ORIGIN) rather than a centre.
	if not _tower_btns.is_empty():
		var group: Array = [_tower_btns[0].header]
		for e in _tower_btns:
			group.append(e.btn)
		_draggables.append({"name": "BUILD_ORIGIN (top-left)", "primary": _tower_btns[0].btn,
			"group": group, "axes": "xy", "report": "origin"})

func _toggle_debug_place() -> void:
	_debug_place = not _debug_place
	_drag_group = []
	if _debug_panel == null:
		_debug_panel = Label.new()
		_debug_panel.add_theme_font_size_override("font_size", 15)
		_debug_panel.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		_debug_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		_debug_panel.add_theme_constant_override("outline_size", 5)
		_debug_panel.position = Vector2(_w * 0.28, _h * 0.40)
		add_child(_debug_panel)
	_debug_panel.visible = _debug_place

## Mouse position in the HUD's canvas space (same space the readout positions use).
func _hud_mouse() -> Vector2:
	return _wave_label.get_global_mouse_position()

func _hit_draggable(m: Vector2) -> Dictionary:
	# Grabbing any node in a group drags the whole group (e.g. any BUILD button).
	for d in _draggables:
		for n in d.group:
			if n is Control and (n as Control).get_global_rect().grow(8.0).has_point(m):
				return d
	return {}

func _debug_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit_draggable(_hud_mouse())
			if not hit.is_empty():
				_drag_group = hit.group
				_drag_last = _hud_mouse()
				get_viewport().set_input_as_handled()
		elif not _drag_group.is_empty():
			_drag_group = []
			var report := _placement_report()
			DisplayServer.clipboard_set(report)
			print("\n=== HUD PLACEMENT (copied to clipboard) ===\n", report)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not _drag_group.is_empty():
		var m := _hud_mouse()
		var delta := m - _drag_last
		_drag_last = m
		for n in _drag_group:
			n.position += delta
		get_viewport().set_input_as_handled()

## Current centre of a node as a viewport fraction (what the constants store).
func _center_frac(n: Control) -> Vector2:
	var c := n.position + n.size / 2.0
	return Vector2(c.x / _w, c.y / _h)

func _placement_report() -> String:
	var s := ""
	for d in _draggables:
		var f: Vector2
		if d.get("report", "") == "origin":
			f = Vector2(d.primary.position.x / _w, d.primary.position.y / _h)  # top-left
		else:
			f = _center_frac(d.primary)
		if String(d.axes) == "x":
			s += "%s = %.3f\n" % [d.name, f.x]
		else:
			s += "%s = (%.3f, %.3f)\n" % [d.name, f.x, f.y]
	return s

func _process(_delta: float) -> void:
	if _debug_place and _debug_panel != null:
		_debug_panel.text = "◈ PLACEMENT MODE — F9 to exit\nDrag a readout; on release its value is\nprinted and copied to the clipboard.\n\n" + _placement_report()

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

	# Live build sidebar: visible only during a run, buttons dim when unaffordable.
	var in_run: bool = main.state == main.State.WAVE or main.state == main.State.INTERMISSION
	for entry in _tower_btns:
		entry.btn.visible = in_run
		entry.header.visible = in_run
		var affordable: bool = Game.money >= int(entry.cost)
		entry.btn.disabled = not affordable
		# Dim the whole button (icon + text included) when unaffordable.
		entry.btn.modulate = Color(1, 1, 1, 1) if affordable else Color(0.5, 0.52, 0.58, 1)
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
