class_name WeaponData
## Mountable tank weapons. Buying a duplicate upgrades the owned copy:
## levels scale damage/fire rate/range and are shown on the gun itself
## (tier band color + longer barrel).

const MAX_LEVEL := 4
const TIER_COLORS: Array = [
	Color(0.6, 0.62, 0.65),   # Lv1 gray
	Color(0.4, 0.85, 0.4),    # Lv2 green
	Color(0.4, 0.65, 0.95),   # Lv3 blue
	Color(1.0, 0.85, 0.3),    # Lv4 gold
]

const WEAPONS: Dictionary = {
	"machinegun": {
		"label": "Machine Gun", "cost": 30, "damage": 3.0, "fire_rate": 7.0,
		"range": 240.0, "behavior": "bullet", "barrels": 2,
		"color": Color(0.75, 0.8, 0.85),
	},
	"autocannon": {
		"label": "Autocannon", "cost": 35, "damage": 9.0, "fire_rate": 2.5,
		"range": 300.0, "behavior": "bullet", "barrels": 1,
		"color": Color(0.85, 0.9, 1.0),
	},
	"cannon": {
		"label": "Siege Cannon", "cost": 45, "damage": 30.0, "fire_rate": 0.55,
		"range": 330.0, "behavior": "aoe", "aoe_radius": 60.0, "barrels": 1,
		"color": Color(0.9, 0.65, 0.35),
	},
	"flamer": {
		"label": "Flamer", "cost": 40, "damage": 2.2, "fire_rate": 8.0,
		"range": 130.0, "behavior": "flame", "cone_degrees": 50.0, "barrels": 1,
		"color": Color(0.95, 0.5, 0.25),
	},
}

static func scaled(key: String, level: int) -> Dictionary:
	var w: Dictionary = WEAPONS[key]
	var m := level - 1
	return {
		"damage": w.damage * pow(1.3, m),
		"fire_rate": w.fire_rate * pow(1.12, m),
		"range": w.range * (1.0 + 0.05 * m),
		"behavior": w.behavior,
		"aoe_radius": w.get("aoe_radius", 0.0),
		"cone_degrees": w.get("cone_degrees", 0.0),
	}
