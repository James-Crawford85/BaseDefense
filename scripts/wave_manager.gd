class_name WaveManager
extends Node
## Spawns enemies per WaveData schedule and reports when a wave is fully cleared.

signal wave_cleared(wave_index: int)

var arena: Node2D
var wall_line_x: float = 0.0
var gap_ys: Array = []
var core: Node2D
var spawn_edge_x: float = 1020.0
var spawn_y_min: float = 40.0
var spawn_y_max: float = 530.0

var _schedule: Array = []
var _elapsed: float = 0.0
var _spawning: bool = false
var _active: bool = false
var _wave_index: int = -1

func start_wave(index: int) -> void:
	_wave_index = index
	_schedule.clear()
	for group in WaveData.schedule(index):
		for i in range(group.count):
			_schedule.append({"time": group.delay + i * group.interval, "type": group.type})
	_schedule.sort_custom(func(a, b): return a.time < b.time)
	_elapsed = 0.0
	_spawning = true
	_active = true

func stop() -> void:
	_active = false
	_spawning = false

func _process(delta: float) -> void:
	if not _active:
		return
	if _spawning:
		_elapsed += delta
		while not _schedule.is_empty() and _schedule[0].time <= _elapsed:
			_spawn(_schedule.pop_front().type)
		if _schedule.is_empty():
			_spawning = false
	elif get_tree().get_nodes_in_group("enemies").is_empty():
		_active = false
		wave_cleared.emit(_wave_index)

func _spawn(type: String) -> void:
	var enemy := Enemy.new()
	enemy.setup(type, wall_line_x, gap_ys, core, _wave_index + 1)
	enemy.position = Vector2(spawn_edge_x + randf_range(40.0, 80.0), randf_range(spawn_y_min, spawn_y_max))
	arena.add_child(enemy)
