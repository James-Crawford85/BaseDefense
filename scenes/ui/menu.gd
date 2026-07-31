class_name Menu
extends CanvasLayer
## Pre-game menu flow: title → (solo | host | join) → squad lobby → run.
## Everything is code-built like the rest of the UI, with a shared StyleBoxFlat
## theme for a cleaner look than raw default controls. Runs while the tree is
## paused; main.begin_run takes over when the (solo or networked) lobby starts.

const CLASS_ORDER: Array = ["assault", "heavy", "scout"]
const ACCENT := Color(1.0, 0.78, 0.3)
const PANEL_BG := Color(0.09, 0.11, 0.14, 0.97)
const TEXT_DIM := Color(0.62, 0.66, 0.72)

var main  # main.gd

var _w: float
var _h: float
var _title_screen: Control
var _lobby_screen: Control
var _join_screen: Control
var _error_label: Label
var _steam_label: Label

# Lobby widgets
var _lobby_title: Label
var _lobby_context: Label
var _class_panels: Array = []
var _roster_box: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _solo := false
var _sel_class := "assault"

# Join widgets
var _list_box: VBoxContainer
var _join_status: Label
var _ip_edit: LineEdit

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	var vs := get_viewport().get_visible_rect().size
	_w = vs.x
	_h = vs.y
	_build_title()
	_build_lobby()
	_build_join()
	Net.lobby_updated.connect(_on_lobby_updated)
	Net.lobby_list_ready.connect(_on_lobby_list)
	Net.session_error.connect(_on_session_error)
	Net.game_starting.connect(func(): close())
	if Net.active() and Net.return_to_lobby:
		Net.return_to_lobby = false
		_solo = false
		_show(_lobby_screen)
		_refresh_lobby()
	else:
		_show(_title_screen)

func close() -> void:
	_title_screen.visible = false
	_lobby_screen.visible = false
	_join_screen.visible = false

func _show(screen: Control) -> void:
	close()
	screen.visible = true

# --- Shared building blocks ---

func _screen() -> Control:
	var root := ColorRect.new()
	root.color = Color(0.03, 0.045, 0.06, 0.88)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	return root

func _btn(parent: Node, text: String, size: Vector2, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.16, 0.2)
	normal.border_color = ACCENT if accent else Color(0.28, 0.33, 0.4)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.22, 0.28)
	hover.border_color = ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.1, 0.12, 0.15)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.1, 0.11, 0.13)
	disabled.border_color = Color(0.2, 0.22, 0.26)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover.duplicate())
	if accent:
		b.add_theme_color_override("font_color", ACCENT)
		b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.43, 0.48))
	parent.add_child(b)
	return b

func _panel_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT if selected else Color(0.24, 0.28, 0.34)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb

func _label(parent: Node, text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _centered(parent: Control, text: String, y: float, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := _label(parent, text, font_size, color)
	l.position = Vector2(0, y)
	l.size = Vector2(_w, font_size * 2.2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# --- Title screen ---

func _build_title() -> void:
	_title_screen = _screen()
	_centered(_title_screen, "BASE DEFENSE", _h * 0.10, 52)
	_centered(_title_screen, "— hold the line through 100 waves —", _h * 0.235, 16, TEXT_DIM)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.position = Vector2(_w / 2.0 - 140, _h * 0.34)
	_title_screen.add_child(col)
	var size := Vector2(280, 44)
	_btn(col, "PLAY SOLO", size, true).pressed.connect(_on_solo_pressed)
	_btn(col, "HOST ONLINE GAME", size).pressed.connect(_on_host_pressed)
	_btn(col, "JOIN GAME", size).pressed.connect(_on_join_pressed)
	_btn(col, "QUIT", size).pressed.connect(func(): get_tree().quit())

	_error_label = _centered(_title_screen, "", _h * 0.80, 15, Color(0.95, 0.45, 0.4))
	_steam_label = _centered(_title_screen, "", _h * 0.90, 13, TEXT_DIM)
	if Net.steam_ok:
		_steam_label.text = "Steam: online as %s — lobbies enabled" % Net.steam_name
	else:
		_steam_label.text = "Steam not detected — hosting/joining runs over LAN (direct IP)"

func _on_solo_pressed() -> void:
	_solo = true
	_show(_lobby_screen)
	_refresh_lobby()

func _on_host_pressed() -> void:
	_error_label.text = ""
	_solo = false
	Net.host_game()
	_show(_lobby_screen)
	_refresh_lobby()

func _on_join_pressed() -> void:
	_error_label.text = ""
	_solo = false
	_show(_join_screen)
	_join_status.text = "Pick a lobby to join." if Net.steam_ok else "Steam offline — join by IP below."
	if Net.steam_ok:
		_join_status.text = "Searching for lobbies..."
		Net.refresh_lobby_list()

# --- Lobby screen (also used for solo mission prep) ---

func _build_lobby() -> void:
	_lobby_screen = _screen()
	_lobby_title = _centered(_lobby_screen, "MISSION PREP", _h * 0.045, 34)
	_lobby_context = _centered(_lobby_screen, "", _h * 0.125, 14, TEXT_DIM)

	# Class panels
	var panel_w := 176.0
	var gap := 10.0
	var x0 := (_w - (panel_w * 3 + gap * 2)) / 2.0
	for i in range(CLASS_ORDER.size()):
		var data: Dictionary = TankData.CLASSES[CLASS_ORDER[i]]
		var panel := PanelContainer.new()
		panel.position = Vector2(x0 + i * (panel_w + gap), _h * 0.175)
		panel.custom_minimum_size = Vector2(panel_w, 205)
		panel.add_theme_stylebox_override("panel", _panel_style(i == 0))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		panel.add_child(vb)
		var name_l := _label(vb, data.label, 18, data.color.lightened(0.4))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var stats_l := _label(vb, "HP %d · Speed %d · Armor %d\nDamage x%.2f · Slots %d\nStarts: %s" % [
			int(data.hp), int(data.speed), int(data.armor), data.damage_mult,
			data.slots.size(), WeaponData.WEAPONS[data.start_weapon].label], 12)
		stats_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var blurb_l := _label(vb, data.blurb, 11, TEXT_DIM)
		blurb_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb_l.custom_minimum_size = Vector2(panel_w - 24, 0)
		panel.gui_input.connect(_on_class_panel_input.bind(i))
		_lobby_screen.add_child(panel)
		_class_panels.append(panel)

	# Roster
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	_roster_box.position = Vector2(_w / 2.0 - 220, _h * 0.60)
	_roster_box.custom_minimum_size = Vector2(440, 0)
	_lobby_screen.add_child(_roster_box)

	# Bottom buttons
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.position = Vector2(_w / 2.0 - 290, _h * 0.86)
	_lobby_screen.add_child(row)
	_ready_btn = _btn(row, "READY UP", Vector2(180, 42))
	_ready_btn.pressed.connect(_on_ready_pressed)
	_start_btn = _btn(row, "ROLL OUT", Vector2(200, 42), true)
	_start_btn.pressed.connect(_on_start_pressed)
	_btn(row, "LEAVE", Vector2(180, 42)).pressed.connect(_on_leave_pressed)

func _on_class_panel_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		_select_class(CLASS_ORDER[idx])

func _select_class(key: String) -> void:
	_sel_class = key
	if Net.active():
		Net.set_my_tank(key)
	_refresh_lobby()

func _my_class() -> String:
	if Net.active() and Net.roster.has(Net.my_id()):
		return Net.roster[Net.my_id()].tank
	return _sel_class

func _refresh_lobby() -> void:
	if not _lobby_screen.visible:
		return
	var mine := _my_class()
	for i in range(_class_panels.size()):
		_class_panels[i].add_theme_stylebox_override("panel", _panel_style(CLASS_ORDER[i] == mine))

	for c in _roster_box.get_children():
		c.queue_free()

	if _solo or not Net.active():
		_lobby_title.text = "MISSION PREP"
		_lobby_context.text = "Pick your tank and roll out. WASD to drive · Space to boost · E deploys tower kits."
		_ready_btn.visible = false
		_start_btn.disabled = false
		_start_btn.text = "ROLL OUT"
		return

	_lobby_title.text = "SQUAD LOBBY"
	if Net.transport == "steam":
		_lobby_context.text = "Steam lobby is live — friends can find it under JOIN GAME."
	else:
		_lobby_context.text = "LAN lobby — friends connect to %s under JOIN GAME." % Net.local_ip()
	_ready_btn.visible = true
	var me: Dictionary = Net.roster.get(Net.my_id(), {})
	_ready_btn.text = "UNREADY" if me.get("ready", false) else "READY UP"

	var ids: Array = Net.roster.keys()
	ids.sort()
	for pid in ids:
		var entry: Dictionary = Net.roster[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := _label(row, String(entry.name) + (" (host)" if pid == 1 else ""), 15)
		name_l.custom_minimum_size = Vector2(220, 0)
		var cls: Dictionary = TankData.CLASSES[entry.tank]
		var cls_l := _label(row, cls.label, 15, cls.color.lightened(0.4))
		cls_l.custom_minimum_size = Vector2(120, 0)
		_label(row, "READY" if entry.ready else "...", 15,
			Color(0.4, 0.9, 0.5) if entry.ready else TEXT_DIM)
		_roster_box.add_child(row)

	if Net.hosting():
		_start_btn.disabled = not Net.all_ready()
		_start_btn.text = "ROLL OUT" if Net.all_ready() else "WAITING FOR READY..."
	else:
		_start_btn.disabled = true
		_start_btn.text = "HOST STARTS THE RUN"

func _on_ready_pressed() -> void:
	var me: Dictionary = Net.roster.get(Net.my_id(), {})
	Net.set_my_ready(not me.get("ready", false))

func _on_start_pressed() -> void:
	if _solo or not Net.active():
		main.start_solo(_sel_class)
	elif Net.hosting():
		Net.request_start()

func _on_leave_pressed() -> void:
	if Net.active():
		Net.leave()
	_show(_title_screen)

# --- Join screen ---

func _build_join() -> void:
	_join_screen = _screen()
	_centered(_join_screen, "JOIN GAME", _h * 0.05, 34)
	_join_status = _centered(_join_screen, "", _h * 0.14, 14, TEXT_DIM)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	_list_box.position = Vector2(_w / 2.0 - 260, _h * 0.22)
	_list_box.custom_minimum_size = Vector2(520, 0)
	_join_screen.add_child(_list_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.position = Vector2(_w / 2.0 - 260, _h * 0.66)
	_join_screen.add_child(row)
	var refresh := _btn(row, "REFRESH LOBBIES", Vector2(180, 40))
	refresh.pressed.connect(func():
		_join_status.text = "Searching for lobbies..."
		Net.refresh_lobby_list())
	refresh.disabled = not Net.steam_ok

	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 10)
	lan_row.position = Vector2(_w / 2.0 - 260, _h * 0.75)
	_join_screen.add_child(lan_row)
	_label(lan_row, "Direct IP:", 15, TEXT_DIM)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(220, 38)
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(0.07, 0.09, 0.12)
	le_style.border_color = Color(0.3, 0.35, 0.42)
	le_style.set_border_width_all(1)
	le_style.set_corner_radius_all(6)
	le_style.set_content_margin_all(8)
	_ip_edit.add_theme_stylebox_override("normal", le_style)
	lan_row.add_child(_ip_edit)
	_btn(lan_row, "CONNECT", Vector2(130, 38), true).pressed.connect(func():
		_join_status.text = "Connecting to %s..." % _ip_edit.text
		Net.join_enet(_ip_edit.text.strip_edges()))

	var back := _btn(_join_screen, "BACK", Vector2(140, 38))
	back.position = Vector2(_w / 2.0 - 260, _h * 0.86)
	back.pressed.connect(func(): _show(_title_screen))

func _on_lobby_list(lobbies: Array) -> void:
	for c in _list_box.get_children():
		c.queue_free()
	if lobbies.is_empty():
		_join_status.text = "No lobbies found — host one, or join by IP." if Net.steam_ok \
			else "Steam offline — join by IP below."
		return
	_join_status.text = "%d lobby(ies) found:" % lobbies.size()
	for lb in lobbies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := _label(row, String(lb.name) if String(lb.name) != "" else "Unnamed squad", 15)
		name_l.custom_minimum_size = Vector2(300, 0)
		_label(row, "%d / %d" % [int(lb.players), int(lb.cap)], 15, TEXT_DIM)
		var jb := _btn(row, "JOIN", Vector2(90, 34), true)
		jb.pressed.connect(func():
			_join_status.text = "Joining %s..." % String(lb.name)
			Net.join_steam_lobby(int(lb.id)))
		_list_box.add_child(row)

# --- Net signal handlers ---

func _on_lobby_updated() -> void:
	# A client lands in the lobby once the host's roster arrives.
	if _join_screen.visible and Net.mode == Net.Mode.CLIENT and Net.roster.has(Net.my_id()):
		_solo = false
		_show(_lobby_screen)
	_refresh_lobby()

func _on_session_error(message: String) -> void:
	if main.state == main.State.MENU:
		_show(_title_screen)
		_error_label.text = message
