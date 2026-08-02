class_name SettingsPanel
extends PanelContainer
## Reusable settings UI (Audio / Video / Key Bindings tabs), embedded by both the
## main-menu settings screen and the in-game pause menu so the two always match.
## Reads and writes through the Audio autoload, which persists everything to
## user://settings.cfg.

const ACCENT := Color(1.0, 0.78, 0.3)
const PANEL_BG := Color(0.09, 0.11, 0.14, 0.97)
const TEXT_DIM := Color(0.62, 0.66, 0.72)

## Actions offered on the Key Bindings tab (label is what the player sees).
const BINDABLE: Array = [
	{"action": "move_up", "label": "Forward"},
	{"action": "move_down", "label": "Reverse"},
	{"action": "move_left", "label": "Turn Left"},
	{"action": "move_right", "label": "Turn Right"},
	{"action": "dash", "label": "Boost / Dash"},
]

var _rebinding := ""          # action currently awaiting a key press ("" = none)
var _rebind_btn: Button = null
var _keybind_btns: Dictionary = {}  # action -> Button (to refresh labels)

func _ready() -> void:
	custom_minimum_size = Vector2(620, 340)
	add_theme_stylebox_override("panel", _panel_style())
	var tabs := TabContainer.new()
	_style_tabs(tabs)
	tabs.add_child(_audio_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_keys_tab())
	add_child(tabs)

# --- Tabs ---

func _audio_tab() -> Control:
	var vb := _page("Audio", 16)
	_volume_row(vb, "MUSIC VOLUME", Audio.music_volume, func(v: float): Audio.set_music_volume(v))
	# A short blip while dragging Game Sounds so the level is audible.
	_volume_row(vb, "GAME SOUNDS", Audio.sfx_volume, func(v: float):
		Audio.set_sfx_volume(v)
		Sfx.play("buy", 0.0))
	return vb.get_parent()

func _video_tab() -> Control:
	var vb := _page("Video", 16)
	_toggle_row(vb, "DISPLAY MODE", ["WINDOWED", "FULLSCREEN"], (1 if Audio.fullscreen else 0),
		func(idx: int): Audio.set_fullscreen(idx == 1))
	return vb.get_parent()

func _keys_tab() -> Control:
	var vb := _page("Key Bindings", 8)
	_label(vb, "Click a binding, then press a key.  Esc cancels.", 13, TEXT_DIM)
	for b in BINDABLE:
		_keybind_row(vb, String(b.action), String(b.label))
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.custom_minimum_size = Vector2(180, 32)
	reset.focus_mode = Control.FOCUS_NONE
	_style_button(reset)
	reset.pressed.connect(func():
		Audio.reset_keybinds()
		_refresh_keys())
	vb.add_child(reset)
	return vb.get_parent()

## A named tab page (MarginContainer for padding) wrapping a VBox; returns the VBox.
func _page(tab_name: String, separation: int) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.name = tab_name
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", separation)
	mc.add_child(vb)
	return vb

# --- Key rebinding ---

func _keybind_row(parent: Node, action: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := _label(row, label, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = Audio.action_key_string(action)
	b.custom_minimum_size = Vector2(150, 32)
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b)
	b.pressed.connect(func(): _start_rebind(action, b))
	row.add_child(b)
	parent.add_child(row)
	_keybind_btns[action] = b

func _start_rebind(action: String, btn: Button) -> void:
	if _rebind_btn != null:  # cancel any in-progress rebind first
		_rebind_btn.text = Audio.action_key_string(_rebinding)
	_rebinding = action
	_rebind_btn = btn
	btn.text = "Press a key..."

func _input(event: InputEvent) -> void:
	if _rebinding == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()  # swallow it so it can't also fire in-game
		if event.keycode != KEY_ESCAPE:
			var kc: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			Audio.rebind_action(_rebinding, kc)
		_rebind_btn.text = Audio.action_key_string(_rebinding)
		_rebinding = ""
		_rebind_btn = null

func _refresh_keys() -> void:
	for action in _keybind_btns:
		_keybind_btns[action].text = Audio.action_key_string(action)

# --- Rows ---

## Label + 0-100% slider with a live value readout.
func _volume_row(parent: Node, label_text: String, initial: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := _label(top, label_text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _label(top, "%d%%" % int(round(initial * 100.0)), 16, ACCENT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(70, 0)
	row.add_child(top)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(560, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(slider)
	slider.value_changed.connect(func(v: float):
		val.text = "%d%%" % int(round(v * 100.0))
		on_change.call(v))
	row.add_child(slider)
	parent.add_child(row)

## Label + a button that cycles through `options`, reporting the chosen index.
func _toggle_row(parent: Node, label_text: String, options: Array, initial: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := _label(row, label_text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state := {"idx": initial}
	var btn := Button.new()
	btn.text = options[initial]
	btn.custom_minimum_size = Vector2(200, 40)
	btn.focus_mode = Control.FOCUS_ALL
	_style_button(btn)
	btn.pressed.connect(func():
		state.idx = (state.idx + 1) % options.size()
		btn.text = options[state.idx]
		on_change.call(state.idx))
	row.add_child(btn)
	parent.add_child(row)

# --- Styling ---

func _label(parent: Node, text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _style_tabs(tabs: TabContainer) -> void:
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	tabs.add_theme_stylebox_override("panel", empty)             # content area transparent
	tabs.add_theme_stylebox_override("tabbar_background", empty)
	tabs.add_theme_color_override("font_selected_color", ACCENT)
	tabs.add_theme_color_override("font_unselected_color", TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(0.24, 0.28, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	return sb

func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.07, 0.09, 0.12)
	track.set_corner_radius_all(4)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)

func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.16, 0.2)
	normal.border_color = ACCENT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.22, 0.28)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal.duplicate())
	b.add_theme_stylebox_override("focus", hover.duplicate())
	b.add_theme_color_override("font_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
