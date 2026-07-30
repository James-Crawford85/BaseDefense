class_name EnemyData
## Enemies live on a Speed/Damage/Health triangle: `weights` is
## (speed, damage, health), normalized before deriving stats — so leaning
## into one stat always costs the other two. Money value is derived from the
## final stats, so new types price themselves. Tune the curves in stats_for(),
## the roster here.
##
## attack_range > 0 makes the type RANGED: it stops at that distance and
## shoots instead of meleeing (ranged pays a 25% damage tax for the safety).

const TYPES: Dictionary = {
	"grunt": {  # dead center of the triangle
		"weights": Vector3(0.34, 0.33, 0.33), "cooldown": 1.0, "attack_range": 0.0,
		"body_size": 24.0, "color": Color(0.5, 0.32, 0.6), "shape": "square", "seeks_gaps": false,
	},
	"runner": {  # speed corner, moderate
		"weights": Vector3(0.7, 0.15, 0.15), "cooldown": 0.8, "attack_range": 0.0,
		"body_size": 18.0, "color": Color(0.95, 0.85, 0.3), "shape": "triangle", "seeks_gaps": true,
	},
	"stinger": {  # speed corner, extreme — dies to a stiff breeze
		"weights": Vector3(0.85, 0.1, 0.05), "cooldown": 0.6, "attack_range": 0.0,
		"body_size": 14.0, "color": Color(0.4, 0.9, 0.95), "shape": "dart", "seeks_gaps": true,
	},
	"brute": {  # health corner
		"weights": Vector3(0.1, 0.25, 0.65), "cooldown": 1.6, "attack_range": 0.0,
		"body_size": 40.0, "color": Color(0.85, 0.35, 0.35), "shape": "square", "seeks_gaps": false,
	},
	"ogre": {  # damage/health edge — slow wrecking ball
		"weights": Vector3(0.05, 0.5, 0.45), "cooldown": 1.8, "attack_range": 0.0,
		"body_size": 36.0, "color": Color(0.85, 0.55, 0.2), "shape": "pentagon", "seeks_gaps": false,
	},
	"spitter": {  # damage-leaning RANGED siege unit
		"weights": Vector3(0.25, 0.5, 0.25), "cooldown": 1.5, "attack_range": 190.0,
		"body_size": 22.0, "color": Color(0.9, 0.45, 0.75), "shape": "diamond", "seeks_gaps": false,
	},
}

static var _cache: Dictionary = {}

static func stats_for(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var def: Dictionary = TYPES[key]
	var w: Vector3 = def.weights
	var total := w.x + w.y + w.z
	var sw := w.x / total
	var dw := w.y / total
	var hw := w.z / total
	var ranged: bool = def.attack_range > 0.0
	var speed := 25.0 + 145.0 * sw
	var hp := 10.0 + 320.0 * hw * hw  # quadratic so tanks feel properly tanky
	var dps := 3.0 + 30.0 * dw
	var damage: float = dps * def.cooldown * (0.75 if ranged else 1.0)
	var stats := {
		"hp": hp,
		"speed": speed,
		"damage": damage,
		"attack_cooldown": def.cooldown,
		"attack_range": def.attack_range,
		"money": int(round(2.0 + hp / 20.0 + dps / 4.0 + speed / 60.0)),
		"body_size": def.body_size,
		"color": def.color,
		"shape": def.shape,
		"seeks_gaps": def.seeks_gaps,
	}
	_cache[key] = stats
	return stats
