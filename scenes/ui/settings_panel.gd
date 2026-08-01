class_name SettingsPanel
extends PanelContainer
## Reusable Audio + Video settings UI, embedded by both the main-menu settings
## screen and the in-game pause menu so the two always match. Reads and writes
## through the Audio autoload, which persists everything to user://settings.cfg.

const ACCENT := Color(1.0, 0.78, 0.3)
const PANEL_BG := Color(0.09, 0.11, 0.14, 0.97)
const TEXT_DIM := Color(0.62, 0.66, 0.72)

func _ready() -> void:
	custom_minimum_size = Vector2(620, 0)
	add_theme_stylebox_override("panel", _panel_style())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	add_child(vb)

	_heading(vb, "AUDIO")
	_volume_row(vb, "MUSIC VOLUME", Audio.music_volume, func(v: float): Audio.set_music_volume(v))
	# A short blip while dragging Game Sounds so the level is audible.
	_volume_row(vb, "GAME SOUNDS", Audio.sfx_volume, func(v: float):
		Audio.set_sfx_volume(v)
		Sfx.play("buy", 0.0))

	_heading(vb, "VIDEO")
	_toggle_row(vb, "DISPLAY MODE", ["WINDOWED", "FULLSCREEN"], (1 if Audio.fullscreen else 0),
		func(idx: int): Audio.set_fullscreen(idx == 1))

# --- Rows ---

## A section header with a thin accent underline.
func _heading(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", ACCENT)
	parent.add_child(l)

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

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(0.24, 0.28, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
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
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.22, 0.28)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal.duplicate())
	b.add_theme_stylebox_override("focus", hover.duplicate())
	b.add_theme_color_override("font_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
