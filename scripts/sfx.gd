extends Node
## Autoload: procedural retro sound effects. Every sound is synthesized once at
## startup into an AudioStreamWAV from a tiny recipe (wave type, pitch sweep,
## envelope) — no audio assets needed. To replace any sound with real audio
## later, drop a file at assets/sfx/<name>.wav (or .ogg); it wins automatically.
##
## Playback goes through a small voice pool with per-sound rate limiting so a
## screenful of simultaneous deaths can't blow out the mix.

const MIX_RATE := 22050
const VOICES := 12
const BASE_DB := -8.0
const MIN_INTERVAL_MS := 45

var _streams: Dictionary = {}
var _players: Array = []
var _last_played: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # shop/menu sounds while paused
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()

## `jitter` randomizes pitch a little so rapid fire doesn't sound stamped out;
## pass 0.0 for melodic sounds that must stay in tune.
func play(sound: String, jitter: float = 0.06, volume_db: float = 0.0) -> void:
	if not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < MIN_INTERVAL_MS:
		return
	_last_played[sound] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound]
			p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
			p.volume_db = BASE_DB + volume_db
			p.play()
			return
	# All voices busy — drop the sound; inaudible in that much din anyway.

func _add(sound: String, synthesized: AudioStreamWAV) -> void:
	for ext in ["wav", "ogg"]:
		var path := "res://assets/sfx/%s.%s" % [sound, ext]
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)
			return
	_streams[sound] = synthesized

func _build_all() -> void:
	# Gunfire (player weapons + towers share these by weapon character)
	_add("shot_mg", _render(0.07, [
		{"wave": "square", "f0": 880.0, "f1": 420.0, "vol": 0.15}]))
	_add("shot_auto", _render(0.11, [
		{"wave": "square", "f0": 520.0, "f1": 230.0, "vol": 0.2}]))
	_add("shot_cannon", _render(0.3, [
		{"wave": "sine", "f0": 150.0, "f1": 52.0, "vol": 0.55, "curve": 2.5},
		{"wave": "noise", "f0": 1.0, "vol": 0.22, "curve": 3.0}]))
	_add("flame", _render(0.13, [
		{"wave": "noise", "f0": 1.0, "vol": 0.08, "curve": 1.2}]))
	_add("shot_artillery", _render(0.22, [
		{"wave": "sine", "f0": 300.0, "f1": 70.0, "vol": 0.4, "curve": 2.0},
		{"wave": "noise", "f0": 1.0, "vol": 0.1, "curve": 2.5}]))
	# Deaths / impacts
	_add("explode_small", _render(0.35, [
		{"wave": "noise", "f0": 1.0, "vol": 0.38, "curve": 2.5},
		{"wave": "sine", "f0": 140.0, "f1": 45.0, "vol": 0.42, "curve": 2.0}]))
	_add("explode_big", _render(0.6, [
		{"wave": "noise", "f0": 1.0, "vol": 0.5, "curve": 2.5},
		{"wave": "sine", "f0": 110.0, "f1": 32.0, "vol": 0.5, "curve": 2.0}]))
	_add("wall_hit", _render(0.09, [
		{"wave": "noise", "f0": 1.0, "vol": 0.18, "curve": 2.0},
		{"wave": "sine", "f0": 180.0, "f1": 80.0, "vol": 0.3, "curve": 2.0}]))
	_add("player_hit", _render(0.14, [
		{"wave": "noise", "f0": 1.0, "vol": 0.22, "curve": 2.0},
		{"wave": "sine", "f0": 250.0, "f1": 95.0, "vol": 0.32, "curve": 2.0}]))
	_add("core_hit", _render(0.24, [
		{"wave": "sine", "f0": 95.0, "f1": 55.0, "vol": 0.55, "curve": 1.8},
		{"wave": "noise", "f0": 1.0, "vol": 0.12, "curve": 2.5}]))
	_add("wall_breach", _render_notes([698.0, 494.0, 698.0, 494.0], 0.13, "saw", 0.3))
	# Movement / pickups
	_add("dash", _render(0.16, [
		{"wave": "noise", "f0": 1.0, "vol": 0.1, "curve": 1.0},
		{"wave": "saw", "f0": 180.0, "f1": 420.0, "vol": 0.08, "curve": 1.2}]))
	_add("pickup_gold", _render_notes([1047.0, 1568.0], 0.06, "square", 0.13))
	_add("pickup_xp", _render(0.09, [
		{"wave": "sine", "f0": 600.0, "f1": 1000.0, "vol": 0.14, "curve": 1.2}]))
	# Shop / flow
	_add("buy", _render_notes([660.0, 990.0], 0.05, "square", 0.15))
	_add("deny", _render(0.18, [
		{"wave": "square", "f0": 160.0, "f1": 140.0, "vol": 0.18, "curve": 1.0}]))
	_add("reroll", _render_notes([500.0, 700.0, 900.0], 0.045, "square", 0.12))
	_add("wave_start", _render(0.45, [
		{"wave": "saw", "f0": 196.0, "vol": 0.22, "curve": 1.2},
		{"wave": "saw", "f0": 294.0, "vol": 0.15, "curve": 1.2}]))
	_add("level_up", _render_notes([523.0, 659.0, 784.0, 1047.0], 0.08, "square", 0.16))
	_add("victory", _render_notes([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.13, "square", 0.18))
	_add("defeat", _render_notes([392.0, 330.0, 262.0, 196.0], 0.22, "saw", 0.2))

# --- Synthesis ---

## Renders summed layers. Layer keys: wave (square/saw/sine/noise), f0 -> f1
## exponential pitch sweep (f1 defaults to f0), vol, curve (decay exponent,
## default 2 — higher = snappier), attack (seconds, default 4 ms).
func _render(dur: float, layers: Array) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases: Array[float] = []
	phases.resize(layers.size())
	for f in range(n):
		var t := float(f) / MIX_RATE
		var u := t / dur
		var v := 0.0
		for li in range(layers.size()):
			var L: Dictionary = layers[li]
			var f0: float = L.f0
			var f1: float = L.get("f1", f0)
			var freq := f0 * pow(f1 / f0, u)
			var attack: float = L.get("attack", 0.004)
			var curve: float = L.get("curve", 2.0)
			var env := minf(t / attack, 1.0) * pow(1.0 - u, curve)
			var vol: float = L.vol
			v += _sample(L.wave, phases[li]) * vol * env
			phases[li] += freq / MIX_RATE
		data.encode_s16(f * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(data)

## Renders a short note sequence (arpeggios, alarms, fanfares).
func _render_notes(freqs: Array, note_dur: float, wave: String, vol: float) -> AudioStreamWAV:
	var n := int(note_dur * freqs.size() * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for f in range(n):
		var t := float(f) / MIX_RATE
		var idx := mini(int(t / note_dur), freqs.size() - 1)
		var tn := t - idx * note_dur
		var freq: float = freqs[idx]
		var env := minf(tn / 0.004, 1.0) * pow(1.0 - tn / note_dur, 1.5)
		data.encode_s16(f * 2, int(clampf(_sample(wave, phase) * vol * env, -1.0, 1.0) * 32767.0))
		phase += freq / MIX_RATE
	return _wav(data)

func _sample(wave: String, phase: float) -> float:
	match wave:
		"noise":
			return randf() * 2.0 - 1.0
		"sine":
			return sin(TAU * phase)
		"saw":
			return 2.0 * fposmod(phase, 1.0) - 1.0
		_:  # square
			return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav
