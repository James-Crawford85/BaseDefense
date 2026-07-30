class_name WaveData
## The 10 hand-authored waves. Each wave is a list of spawn groups.
## type: EnemyData key · count: how many · interval: seconds between spawns ·
## delay: seconds after wave start before the group begins spawning.

const WAVES: Array = [
	[{"type": "grunt", "count": 6, "interval": 1.4, "delay": 0.0}],
	[{"type": "grunt", "count": 10, "interval": 1.1, "delay": 0.0}],
	[
		{"type": "grunt", "count": 8, "interval": 1.2, "delay": 0.0},
		{"type": "runner", "count": 4, "interval": 0.9, "delay": 4.0},
	],
	[
		{"type": "grunt", "count": 10, "interval": 1.0, "delay": 0.0},
		{"type": "runner", "count": 6, "interval": 0.8, "delay": 3.0},
	],
	[
		{"type": "brute", "count": 2, "interval": 6.0, "delay": 0.0},
		{"type": "grunt", "count": 8, "interval": 1.0, "delay": 2.0},
	],
	[
		{"type": "grunt", "count": 12, "interval": 0.9, "delay": 0.0},
		{"type": "runner", "count": 8, "interval": 0.7, "delay": 4.0},
	],
	[
		{"type": "brute", "count": 4, "interval": 5.0, "delay": 0.0},
		{"type": "grunt", "count": 10, "interval": 0.9, "delay": 2.0},
		{"type": "runner", "count": 4, "interval": 0.8, "delay": 8.0},
	],
	[
		{"type": "runner", "count": 14, "interval": 0.5, "delay": 0.0},
		{"type": "grunt", "count": 8, "interval": 1.0, "delay": 5.0},
	],
	[
		{"type": "brute", "count": 6, "interval": 4.0, "delay": 0.0},
		{"type": "grunt", "count": 14, "interval": 0.8, "delay": 2.0},
		{"type": "runner", "count": 6, "interval": 0.7, "delay": 10.0},
	],
	[
		{"type": "brute", "count": 8, "interval": 3.5, "delay": 0.0},
		{"type": "grunt", "count": 16, "interval": 0.7, "delay": 2.0},
		{"type": "runner", "count": 10, "interval": 0.5, "delay": 8.0},
	],
]

static func wave_clear_bonus(wave_index: int) -> int:
	return 20 + (wave_index + 1) * 5
