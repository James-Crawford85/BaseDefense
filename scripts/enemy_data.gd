class_name EnemyData
## Balance data for enemy types. Edit numbers here, not in enemy.gd.

const TYPES: Dictionary = {
	"grunt": {
		"hp": 30.0, "speed": 60.0, "damage": 8.0, "attack_cooldown": 1.0,
		"money": 5, "body_size": 24.0, "color": Color(0.5, 0.32, 0.6), "shape": "square",
		"seeks_gaps": false,
	},
	"runner": {
		"hp": 12.0, "speed": 140.0, "damage": 5.0, "attack_cooldown": 0.8,
		"money": 4, "body_size": 18.0, "color": Color(0.95, 0.85, 0.3), "shape": "triangle",
		"seeks_gaps": true,
	},
	"brute": {
		"hp": 150.0, "speed": 35.0, "damage": 25.0, "attack_cooldown": 1.5,
		"money": 15, "body_size": 40.0, "color": Color(0.85, 0.35, 0.35), "shape": "square",
		"seeks_gaps": false,
	},
}
