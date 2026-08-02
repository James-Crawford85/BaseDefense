extends Node
## Autoload "Audio": owns the menu music player and the Music/SFX bus volumes,
## and persists both to user://settings.cfg so choices stick between sessions.
##
## Game sounds route through the SFX bus (see sfx.gd) and music through the Music
## bus, so the two sliders in Settings > Audio control them independently. The
## buses themselves come from default_bus_layout.tres (loaded before autoloads);
## _ensure_buses() recreates them defensively if that layout is ever missing.

const SETTINGS_PATH := "user://settings.cfg"
const MENU_MUSIC := "res://assets/music/MenuTheme.mp3"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

## Player-remappable actions (movement + boost). Rebinds persist and reapply at boot.
const KEYBINDS := ["move_up", "move_down", "move_left", "move_right", "dash"]

var _default_keys: Dictionary = {}  # action -> project-default physical keycode

const WINDOWED_SIZE := Vector2i(1280, 720)

var music_volume := 0.6   # 0..1 linear
var sfx_volume := 0.9
var fullscreen := true     # matches the project's default window mode

var _music: AudioStreamPlayer
var _menu_stream: AudioStream

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing while the tree is paused
	_ensure_buses()
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	if ResourceLoader.exists(MENU_MUSIC):
		_menu_stream = load(MENU_MUSIC)
		if _menu_stream is AudioStreamMP3:
			_menu_stream.loop = true  # menu theme should loop until a run starts
	_capture_default_keys()  # snapshot project defaults before saved binds override them
	_load_settings()
	_apply_volumes()
	_apply_window_mode()  # restore the saved fullscreen/windowed choice at boot

## Recreate the Music/SFX buses if the bus layout didn't provide them.
func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.get_bus_count()
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

# --- Music ---

func play_menu_music() -> void:
	if _menu_stream == null or _music == null:
		return
	if _music.stream == _menu_stream and _music.playing:
		return  # already going — don't restart on menu-to-menu navigation
	_music.stream = _menu_stream
	_music.play()

func stop_music() -> void:
	if _music != null:
		_music.stop()

# --- Volume (0..1 linear, stored and applied as bus dB) ---

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, music_volume)
	_save_settings()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx_volume)
	_save_settings()

func _apply_volumes() -> void:
	_apply_bus(MUSIC_BUS, music_volume)
	_apply_bus(SFX_BUS, sfx_volume)

# --- Video / window mode ---

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window_mode()
	_save_settings()

func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Give windowed mode a sensible size and center it (the project's base
		# window is deliberately small for the stretch canvas).
		DisplayServer.window_set_size(WINDOWED_SIZE)
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position((screen - WINDOWED_SIZE) / 2)

func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# A linear 0 maps to -inf dB, so mute the bus outright at the bottom of the
	# slider instead of feeding AudioServer a garbage value.
	if v <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))

# --- Key bindings ---

func _capture_default_keys() -> void:
	for action in KEYBINDS:
		_default_keys[action] = _current_key(action)

## The physical keycode currently bound to `action` (0 if none).
func _current_key(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.physical_keycode if e.physical_keycode != 0 else e.keycode
	return 0

## Human-readable name of an action's current key, e.g. "W" or "Space".
func action_key_string(action: String) -> String:
	var kc := _current_key(action)
	return OS.get_keycode_string(kc) if kc != 0 else "-"

## Replace an action's keyboard binding (joypad events are left intact).
func _apply_keybind(action: String, keycode: int) -> void:
	if not InputMap.has_action(action) or keycode == 0:
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func rebind_action(action: String, keycode: int) -> void:
	_apply_keybind(action, keycode)
	_save_settings()

func reset_keybinds() -> void:
	for action in KEYBINDS:
		if _default_keys.has(action):
			_apply_keybind(action, int(_default_keys[action]))
	_save_settings()

# --- Persistence ---

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # first run — keep defaults
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	for action in KEYBINDS:
		var kc := int(cfg.get_value("keybinds", action, 0))
		if kc != 0:
			_apply_keybind(action, kc)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # preserve any other sections we don't own
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	for action in KEYBINDS:
		cfg.set_value("keybinds", action, _current_key(action))
	cfg.save(SETTINGS_PATH)
