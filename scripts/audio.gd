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

var music_volume := 0.6   # 0..1 linear
var sfx_volume := 0.9

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
	_load_settings()
	_apply_volumes()

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

# --- Persistence ---

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # first run — keep defaults
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # preserve any other sections we don't own
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)
