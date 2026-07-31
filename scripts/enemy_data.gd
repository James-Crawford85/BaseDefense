class_name EnemyData
## Enemies live on a Speed/Damage/Health triangle: `weights` is
## (speed, damage, health), normalized before deriving stats — so leaning
## into one stat always costs the other two. Money value is derived from the
## final stats, so new types price themselves. Tune the curves in stats_for(),
## the roster here.
##
## Every vehicle is RANGED (they're gun platforms): attack_range is the
## distance it stops at to open fire. Short-range types (bikes, rams) still
## have to drive nearly into your lap; long-range siege types (>=150) pay a
## 25% damage tax for shelling from safety.

const TYPES: Dictionary = {
	"grunt": {  # dead center of the triangle — mid-range line tank
		"weights": Vector3(0.34, 0.33, 0.33), "cooldown": 1.0, "attack_range": 130.0,
		"body_size": 24.0, "color": Color(0.5, 0.32, 0.6), "vehicle": "light_tank", "seeks_gaps": false,
	},
	"runner": {  # speed corner, moderate — short-range harasser
		"weights": Vector3(0.7, 0.15, 0.15), "cooldown": 0.8, "attack_range": 90.0,
		"body_size": 18.0, "color": Color(0.95, 0.85, 0.3), "vehicle": "buggy", "seeks_gaps": true,
	},
	"stinger": {  # speed corner, extreme — point-blank drive-by
		"weights": Vector3(0.85, 0.1, 0.05), "cooldown": 0.6, "attack_range": 50.0,
		"body_size": 14.0, "color": Color(0.4, 0.9, 0.95), "vehicle": "bike", "seeks_gaps": true,
	},
	"brute": {  # health corner — has to shove its gun in your face
		"weights": Vector3(0.1, 0.25, 0.65), "cooldown": 1.6, "attack_range": 60.0,
		"body_size": 40.0, "color": Color(0.85, 0.35, 0.35), "vehicle": "apc", "seeks_gaps": false,
	},
	"ogre": {  # damage/health edge — long-range siege cannon
		"weights": Vector3(0.05, 0.5, 0.45), "cooldown": 1.8, "attack_range": 240.0,
		"body_size": 36.0, "color": Color(0.85, 0.55, 0.2), "vehicle": "siege", "seeks_gaps": false,
	},
	"spitter": {  # damage-leaning artillery — extreme range
		"weights": Vector3(0.25, 0.5, 0.25), "cooldown": 1.5, "attack_range": 300.0,
		"body_size": 22.0, "color": Color(0.9, 0.45, 0.75), "vehicle": "artillery", "seeks_gaps": false,
	},
}

# Per-wave difficulty growth, applied at spawn time (see wave_scaled):
# HP outpaces damage so late waves demand both firepower AND survivability;
# bounty grows slower than either so income never fully keeps pace.
# Tuned for the 100-wave run (wave counts also grow, so per-unit growth is mild).
const HP_GROWTH := 0.06
const DAMAGE_GROWTH := 0.045
const MONEY_GROWTH := 0.035

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
	var siege: bool = def.attack_range >= 150.0
	var speed := 25.0 + 145.0 * sw
	var hp := 10.0 + 320.0 * hw * hw  # quadratic so tanks feel properly tanky
	var dps := 3.0 + 30.0 * dw
	var damage: float = dps * def.cooldown * (0.75 if siege else 1.0)
	var stats := {
		"hp": hp,
		"speed": speed,
		"damage": damage,
		"attack_cooldown": def.cooldown,
		"attack_range": def.attack_range,
		"money": int(round(2.0 + hp / 20.0 + dps / 4.0 + speed / 60.0)),
		"body_size": def.body_size,
		"color": def.color,
		"vehicle": def.vehicle,
		"seeks_gaps": def.seeks_gaps,
	}
	_cache[key] = stats
	return stats

static func wave_scaled(key: String, wave: int) -> Dictionary:
	var s := stats_for(key).duplicate()
	var w := maxi(wave - 1, 0)
	s.hp = s.hp * (1.0 + HP_GROWTH * w)
	s.damage = s.damage * (1.0 + DAMAGE_GROWTH * w)
	s.money = int(round(s.money * (1.0 + MONEY_GROWTH * w)))
	return s
