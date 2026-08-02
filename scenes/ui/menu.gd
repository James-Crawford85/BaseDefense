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
const TITLE_GOLD := Color(0.98, 0.72, 0.22)
const BTN_TITLE := Color(0.98, 0.92, 0.82)

const BG_PATH := "res://assets/ui/menu_background.jpg"
const BUTTON_PATH := "res://assets/ui/button_hud.png"
const LOGO_PATH := "res://assets/ui/logo.png"

var main  # main.gd

var _bg_tex: Texture2D
var _btn_tex: Texture2D
var _logo_tex: Texture2D
var _tank_tex: Dictionary = {}  # class key -> portrait Texture2D

var _w: float
var _h: float
var _title_screen: Control
var _lobby_screen: Control
var _join_screen: Control
var _settings_screen: Control
var _error_label: Label
var _steam_label: Label
var _update_btn: Button
var _version_label: Label
var _updating := false

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
	_load_art()
	_build_title()
	_build_lobby()
	_build_join()
	_build_settings()
	Audio.play_menu_music()
	Net.lobby_updated.connect(_on_lobby_updated)
	Net.lobby_list_ready.connect(_on_lobby_list)
	Net.session_error.connect(_on_session_error)
	Net.game_starting.connect(func(): close())
	Updater.update_available.connect(_on_update_available)
	Updater.download_progress.connect(_on_update_progress)
	Updater.update_failed.connect(_on_update_failed)
	# Skip the network check in headless smoke/automation.
	if DisplayServer.get_name() != "headless":
		Updater.check_for_updates()
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
	if _settings_screen != null:
		_settings_screen.visible = false

func _show(screen: Control) -> void:
	close()
	screen.visible = true

# --- Shared building blocks ---

## Loads the menu art once. Guarded with ResourceLoader.exists so headless smoke
## runs (where imports may be absent) fall back to flat styling instead of erroring.
func _load_art() -> void:
	if ResourceLoader.exists(BG_PATH):
		_bg_tex = load(BG_PATH)
	if ResourceLoader.exists(BUTTON_PATH):
		_btn_tex = load(BUTTON_PATH)
	if ResourceLoader.exists(LOGO_PATH):
		_logo_tex = load(LOGO_PATH)
	for key in CLASS_ORDER:
		var path := "res://assets/ui/tank_%s.jpg" % key
		if ResourceLoader.exists(path):
			_tank_tex[key] = load(path)

## A full-screen backdrop: battlefield art (cover-fit), a global scrim for text
## legibility, and a left-edge gradient so the button stack always reads clearly.
## `scrim` darkens the whole screen — low for the art-forward title, higher for
## the content-heavy lobby/join screens.
func _screen(scrim := 0.35) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	# Solid base shows through when the art hasn't imported (headless/fallback).
	var base := ColorRect.new()
	base.color = Color(0.03, 0.045, 0.06, 1.0)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(base)
	if _bg_tex != null:
		var bg := TextureRect.new()
		bg.texture = _bg_tex
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
	var global_scrim := ColorRect.new()
	global_scrim.color = Color(0.02, 0.03, 0.05, scrim)
	global_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	global_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(global_scrim)
	var left := TextureRect.new()
	left.texture = _left_fade()
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	# Bottom vignette so the secondary buttons and status strip read cleanly over
	# the background's baked-in instrument panel.
	var bottom := TextureRect.new()
	bottom.texture = _bottom_fade()
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	add_child(root)
	return root

## Horizontal dark-to-clear gradient used as a left-edge scrim under the menu.
func _left_fade() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55])
	grad.colors = PackedColorArray([Color(0.02, 0.03, 0.05, 0.85), Color(0.02, 0.03, 0.05, 0.0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 512
	gtex.height = 4
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)
	return gtex

## Vertical clear-to-dark gradient used to darken the bottom of the screen.
func _bottom_fade() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.62, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.03, 0.05, 0.0), Color(0.02, 0.03, 0.05, 0.82)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 4
	gtex.height = 512
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	return gtex

## A big HUD-frame button (uses the keyed button art as a nine-patch). `title`
## is the main label; `subtitle` an optional dim line under it; `compact` shrinks
## the frame margins and centers the title for the small Settings/Exit buttons.
func _hud_button(parent: Node, title: String, subtitle: String, size: Vector2, compact := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = false
	if _btn_tex != null:
		b.add_theme_stylebox_override("normal", _hud_style(compact, Color(0.86, 0.86, 0.9)))
		b.add_theme_stylebox_override("hover", _hud_style(compact, Color(1, 1, 1)))
		b.add_theme_stylebox_override("focus", _hud_style(compact, Color(1, 1, 1)))
		b.add_theme_stylebox_override("pressed", _hud_style(compact, Color(0.62, 0.62, 0.66)))
		b.add_theme_stylebox_override("disabled", _hud_style(compact, Color(0.45, 0.45, 0.5)))
	else:
		# Fallback: reuse the flat button look when art is unavailable.
		_apply_flat_style(b)
	# Title + optional subtitle drawn as child labels so we get two type sizes and
	# a left-aligned layout the plain Button.text can't manage. IGNORE so clicks
	# still hit the button.
	var t := Label.new()
	t.text = title
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("font_size", 22 if compact else 32)
	t.add_theme_color_override("font_color", BTN_TITLE)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	t.add_theme_constant_override("outline_size", 5)
	if compact:
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		t.position = Vector2(34, size.y * 0.20 if subtitle != "" else size.y * 0.30)
		t.size = Vector2(size.x - 60, 38)
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(t)
	if subtitle != "" and not compact:
		var s := Label.new()
		s.text = subtitle
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", TEXT_DIM)
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		s.add_theme_constant_override("outline_size", 4)
		s.position = Vector2(36, size.y * 0.56)
		s.size = Vector2(size.x - 60, 18)
		b.add_child(s)
	parent.add_child(b)
	return b

func _hud_style(compact: bool, mod: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _btn_tex
	var mx := 55 if compact else 80
	var my := 26 if compact else 42
	sb.set_texture_margin(SIDE_LEFT, mx)
	sb.set_texture_margin(SIDE_RIGHT, mx)
	sb.set_texture_margin(SIDE_TOP, my)
	sb.set_texture_margin(SIDE_BOTTOM, my)
	sb.modulate_color = mod
	return sb

func _btn(parent: Node, text: String, size: Vector2, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 17)
	_apply_flat_style(b, accent)
	parent.add_child(b)
	return b

## Flat StyleBoxFlat button look — used by the lobby/join controls and as the
## fallback for HUD buttons when the button art hasn't imported.
func _apply_flat_style(b: Button, accent := false) -> void:
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
	_title_screen = _screen(0.22)
	var lx := _w * 0.06

	# Logo emblem, top-center over the battlefield art. Falls back to gold text
	# if the art hasn't imported (headless/smoke).
	if _logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = _logo_tex
		# expand_mode MUST be set before size, or the default KEEP_SIZE clamps the
		# control up to the texture's native resolution.
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lw := 190.0
		var lh := lw * float(_logo_tex.get_height()) / float(_logo_tex.get_width())
		logo.size = Vector2(lw, lh)
		logo.position = Vector2(_w / 2.0 - lw / 2.0, _h * 0.01)
		_title_screen.add_child(logo)
	else:
		var title := _label(_title_screen, "STEEL TIDE", 62, TITLE_GOLD)
		title.position = Vector2(lx, _h * 0.09)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		title.add_theme_constant_override("outline_size", 8)

	# Primary command stack (left), styled like the mockup's big HUD buttons.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.position = Vector2(lx, _h * 0.30)
	_title_screen.add_child(col)
	var big := Vector2(468, 92)
	_hud_button(col, "SOLO", "SINGLE COMMANDER", big).pressed.connect(_on_solo_pressed)
	_hud_button(col, "HOST", "OPEN A SQUAD LOBBY", big).pressed.connect(_on_host_pressed)
	_hud_button(col, "JOIN", "FIND A SQUAD", big).pressed.connect(_on_join_pressed)

	# Secondary row (Settings placeholder + Exit) under the stack.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var small := Vector2(228, 66)
	_hud_button(row, "SETTINGS", "", small, true).pressed.connect(_on_settings_pressed)
	_hud_button(row, "EXIT", "", small, true).pressed.connect(func(): get_tree().quit())

	# Update notification — a top-center banner, hidden until check_for_updates
	# finds a newer release.
	_update_btn = _btn(_title_screen, "", Vector2(560, 40), true)
	_update_btn.position = Vector2(_w / 2.0 - 280, _h * 0.03)
	_update_btn.visible = false
	_update_btn.pressed.connect(_on_update_pressed)

	# Error strip, bottom-left.
	_error_label = _label(_title_screen, "", 15, Color(0.95, 0.45, 0.4))
	_error_label.position = Vector2(lx, _h - 78)
	_error_label.size = Vector2(_w * 0.55, 22)

	# Steam connection status now docks next to the "STEAMCOM:" readout baked
	# into the background art (top-left corner) instead of the old bottom strip.
	# Position is estimated from the art at 2752x1536 native res — nudge the
	# fractions below if it doesn't sit flush against "STEAMCOM:" at runtime.
	_steam_label = _label(_title_screen, "", 13, TEXT_DIM)
	_steam_label.position = Vector2(_w * 0.099, _h * 0.017)
	_steam_label.size = Vector2(_w * 0.3, 20)
	_steam_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_steam_label.add_theme_constant_override("outline_size", 3)
	_refresh_steam_label()

	_version_label = _label(_title_screen, "v" + Updater.current_version, 12, TEXT_DIM)
	_version_label.position = Vector2(_w - 70, _h - 26)

## Sets the ONLINE/OFFLINE readout next to "STEAMCOM:" in the art. Net.steam_ok
## is decided synchronously during the Net autoload's _ready() (well before this
## menu builds), so a one-shot read here is enough — there's no reconnect flow
## that would change it mid-session.
func _refresh_steam_label() -> void:
	if _steam_label == null:
		return
	if Net.steam_ok:
		_steam_label.text = "ONLINE — %s" % Net.steam_name
		_steam_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
	else:
		_steam_label.text = "OFFLINE — LAN only"
		_steam_label.add_theme_color_override("font_color", Color(0.95, 0.42, 0.38))

func _on_update_available(version: String, _notes: String) -> void:
	if _update_btn == null:
		return
	_update_btn.text = "⬆  Update available: v%s  —  click to install" % version
	_update_btn.visible = true
	# QA: `BaseDefense.exe -- --self-update` auto-applies without a click, so an
	# update can be verified end to end unattended. No-op without the flag.
	if "--self-update" in OS.get_cmdline_user_args():
		_on_update_pressed()

func _on_update_pressed() -> void:
	if _updating:
		return
	_updating = true
	_update_btn.disabled = true
	_update_btn.text = "Downloading update…"
	Updater.download_and_apply()

func _on_update_progress(fraction: float) -> void:
	if _update_btn != null and _updating:
		_update_btn.text = "Downloading update…  %d%%" % int(fraction * 100.0)

func _on_update_failed(message: String) -> void:
	_updating = false
	if _update_btn != null:
		_update_btn.disabled = false
		_update_btn.text = "⬆  Update failed — click to retry"
	if _error_label != null:
		_error_label.text = message

func _on_settings_pressed() -> void:
	_show(_settings_screen)

# --- Settings screen (Audio for now) ---

func _build_settings() -> void:
	_settings_screen = _screen(0.62)
	_centered(_settings_screen, "SETTINGS", _h * 0.07, 34)

	# Shared settings component (Audio + Video), also used by the pause menu.
	var panel := SettingsPanel.new()
	panel.position = Vector2(_w / 2.0 - 310, _h * 0.2)
	_settings_screen.add_child(panel)

	var back := _btn(_settings_screen, "BACK", Vector2(160, 42), true)
	back.position = Vector2(_w / 2.0 - 80, _h * 0.86)
	back.pressed.connect(func(): _show(_title_screen))

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
	_lobby_screen = _screen(0.62)
	_lobby_title = _centered(_lobby_screen, "MISSION PREP", _h * 0.045, 34)
	_lobby_context = _centered(_lobby_screen, "", _h * 0.125, 14, TEXT_DIM)

	# Class cards: a tank portrait shows the name only until hovered, when the
	# full stat sheet fades in (see _process for the fade).
	var panel_w := 210.0
	var panel_h := 250.0
	var gap := 16.0
	var x0 := (_w - (panel_w * 3 + gap * 2)) / 2.0
	for i in range(CLASS_ORDER.size()):
		var panel := _build_class_card(CLASS_ORDER[i], Vector2(panel_w, panel_h))
		panel.position = Vector2(x0 + i * (panel_w + gap), _h * 0.17)
		panel.gui_input.connect(_on_class_panel_input.bind(i))
		panel.mouse_entered.connect(func(): panel.set_meta("hover_target", 1.0))
		panel.mouse_exited.connect(func(): panel.set_meta("hover_target", 0.0))
		_lobby_screen.add_child(panel)
		_class_panels.append(panel)

	# Roster
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	_roster_box.position = Vector2(_w / 2.0 - 220, _h * 0.65)
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

## Builds one Mission Prep tank card: portrait background, always-visible name,
## and a stat sheet that starts hidden (modulate.a 0) and fades in on hover.
func _build_class_card(key: String, size: Vector2) -> Control:
	var data: Dictionary = TankData.CLASSES[key]
	var panel := Control.new()
	panel.custom_minimum_size = size
	panel.size = size
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Portrait background (cover-fit), or a flat tint if the art is missing.
	if _tank_tex.has(key):
		var bg := TextureRect.new()
		bg.texture = _tank_tex[key]
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(bg)
	else:
		var flat := ColorRect.new()
		flat.color = Color(0.1, 0.12, 0.15)
		flat.set_anchors_preset(Control.PRESET_FULL_RECT)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(flat)

	# Subtle base scrim so the name always reads over the portrait.
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.05, 0.22)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scrim)

	# Detail sheet: hidden until hover. A dark panel dims the portrait so the
	# stats stay legible, with the stats + blurb on top.
	var details := Control.new()
	details.set_anchors_preset(Control.PRESET_FULL_RECT)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.modulate = Color(1, 1, 1, 0)
	panel.add_child(details)
	var dbg := ColorRect.new()
	dbg.color = Color(0.03, 0.05, 0.07, 0.82)
	dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(dbg)
	var stats := Label.new()
	stats.text = "HP %d\nSpeed %d\nArmor %d\nDamage x%.2f\nSlots %d\nStarts: %s" % [
		int(data.hp), int(data.speed), int(data.armor), data.damage_mult,
		data.slots.size(), WeaponData.WEAPONS[data.start_weapon].label]
	stats.add_theme_font_size_override("font_size", 13)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.position = Vector2(8, 48)
	stats.size = Vector2(size.x - 16, 0)
	details.add_child(stats)
	var blurb := Label.new()
	blurb.text = data.blurb
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.add_theme_color_override("font_color", TEXT_DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blurb.position = Vector2(10, size.y - 76)
	blurb.size = Vector2(size.x - 20, 68)
	details.add_child(blurb)

	# Tank name — always visible, drawn above the detail sheet.
	var name_l := Label.new()
	name_l.text = data.label
	name_l.add_theme_font_size_override("font_size", 20)
	name_l.add_theme_color_override("font_color", data.color.lightened(0.4))
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_l.add_theme_constant_override("outline_size", 5)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.position = Vector2(0, 14)
	name_l.size = Vector2(size.x, 28)
	panel.add_child(name_l)

	# Selection border on top.
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override("panel", _class_border_style(false))
	panel.add_child(border)

	panel.set_meta("details", details)
	panel.set_meta("border", border)
	panel.set_meta("hover_target", 0.0)
	return panel

func _class_border_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)  # transparent — the portrait shows through
	sb.border_color = ACCENT if selected else Color(0.35, 0.4, 0.47, 0.8)
	sb.set_border_width_all(3 if selected else 1)
	return sb

## Drives the hover fade of the class cards' detail sheets. Runs while the tree
## is paused (menu is PROCESS_MODE_ALWAYS), so a manual lerp is used instead of a
## Tween, which would stall under pause.
func _process(delta: float) -> void:
	for panel in _class_panels:
		if not is_instance_valid(panel):
			continue
		var details = panel.get_meta("details", null)
		if details == null:
			continue
		var target: float = panel.get_meta("hover_target", 0.0)
		if details.modulate.a != target:
			details.modulate.a = move_toward(details.modulate.a, target, delta * 6.0)

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
		var border = _class_panels[i].get_meta("border", null)
		if border != null:
			border.add_theme_stylebox_override("panel", _class_border_style(CLASS_ORDER[i] == mine))

	for c in _roster_box.get_children():
		c.queue_free()

	if _solo or not Net.active():
		_lobby_title.text = "MISSION PREP"
		_lobby_context.text = "Pick your tank and roll out. WASD to drive · Space to boost · build turrets from the sidebar."
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
	_join_screen = _screen(0.62)
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
		name_l.custom_minimum_size = Vector2(260, 0)
		_label(row, "%d / %d" % [int(lb.players), int(lb.cap)], 15, TEXT_DIM)
		# Flag version mismatches up front so a doomed join isn't even offered.
		var ver := String(lb.get("version", ""))
		var mismatch: bool = ver != "" and ver != Net.game_version()
		var ver_l := _label(row, ("v%s" % ver) if ver != "" else "v?", 14,
			Color(0.95, 0.5, 0.45) if mismatch else TEXT_DIM)
		ver_l.custom_minimum_size = Vector2(90, 0)
		if mismatch:
			var note := _btn(row, "UPDATE NEEDED", Vector2(150, 34))
			note.disabled = true
		else:
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
