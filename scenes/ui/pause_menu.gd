class_name PauseMenu
extends CanvasLayer
## In-game ESC menu. Solo: pauses the tree while open. Multiplayer: never pauses
## (the sim keeps running for everyone) — it's just an overlay for this player.
## Offers Resume, Settings (the same SettingsPanel as the main menu), Main Menu,
## and Exit. Created by main.gd; self-manages the ESC toggle.

const ACCENT := Color(1.0, 0.78, 0.3)

var main  # main.gd

var _root: Control
var _main_panel: Control
var _settings_screen: Control
var _open := false

var _w: float
var _h: float

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # must run (and take input) while paused
	layer = 20  # above the HUD and the main menu
	var vs := get_viewport().get_visible_rect().size
	_w = vs.x
	_h = vs.y
	_build()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		# ESC backs out of the settings sub-screen first, otherwise resumes.
		if _settings_screen.visible:
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif _can_pause():
		open()
		get_viewport().set_input_as_handled()

## Only during actual gameplay — not the pre-game menu or the results screen.
func _can_pause() -> bool:
	return main != null and (main.state == main.State.WAVE or main.state == main.State.INTERMISSION)

func open() -> void:
	_open = true
	visible = true
	_show_main()
	if not Net.active():
		get_tree().paused = true  # solo pauses; MP keeps simulating

func close() -> void:
	_open = false
	visible = false
	if not Net.active():
		get_tree().paused = false

func _show_main() -> void:
	_main_panel.visible = true
	_settings_screen.visible = false

func _show_settings() -> void:
	_main_panel.visible = false
	_settings_screen.visible = true

# --- Build ---

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the menu
	_root.add_child(dim)
	_build_main()
	_build_settings()

func _build_main() -> void:
	_main_panel = Control.new()
	_main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_main_panel)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, _h * 0.2)
	title.size = Vector2(_w, 60)
	_main_panel.add_child(title)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(_w / 2.0 - 150, _h * 0.35)
	_main_panel.add_child(col)
	var size := Vector2(300, 46)
	_btn(col, "RESUME", size, true).pressed.connect(close)
	_btn(col, "SETTINGS", size).pressed.connect(_show_settings)
	_btn(col, "MAIN MENU", size).pressed.connect(_on_main_menu)
	_btn(col, "EXIT GAME", size).pressed.connect(func(): get_tree().quit())

func _build_settings() -> void:
	_settings_screen = Control.new()
	_settings_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_screen.visible = false
	_root.add_child(_settings_screen)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, _h * 0.08)
	title.size = Vector2(_w, 50)
	_settings_screen.add_child(title)

	var panel := SettingsPanel.new()
	panel.position = Vector2(_w / 2.0 - 310, _h * 0.22)
	_settings_screen.add_child(panel)

	var back := _btn(_settings_screen, "BACK", Vector2(160, 42), true)
	back.position = Vector2(_w / 2.0 - 80, _h * 0.86)
	back.pressed.connect(_show_main)

func _on_main_menu() -> void:
	close()  # unpauses in solo
	if Net.active():
		Net.leave()
	get_tree().paused = false
	get_tree().reload_current_scene()

# --- Shared flat button (matches the menu look) ---

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
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover.duplicate())
	if accent:
		b.add_theme_color_override("font_color", ACCENT)
		b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
	parent.add_child(b)
	return b
