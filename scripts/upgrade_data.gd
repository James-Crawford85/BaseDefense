class_name UpgradeData
## Shop catalog. kind: "scaling" = repeatable with 1.5x cost growth,
## "flat" = fixed price, "rebuild" = cost computed from destroyed wall count.

const CHARACTER: Array = [
	{"id": "damage", "label": "Damage +25%", "base_cost": 30, "kind": "scaling"},
	{"id": "fire_rate", "label": "Fire Rate +20%", "base_cost": 30, "kind": "scaling"},
	{"id": "speed", "label": "Move Speed +10%", "base_cost": 25, "kind": "scaling"},
	{"id": "max_hp", "label": "Max HP +25 (+25 heal)", "base_cost": 25, "kind": "scaling"},
	{"id": "range", "label": "Attack Range +15%", "base_cost": 20, "kind": "scaling"},
]

const FORTRESS: Array = [
	{"id": "repair", "label": "Repair all walls", "base_cost": 40, "kind": "flat"},
	{"id": "reinforce", "label": "Reinforce walls +30% HP", "base_cost": 50, "kind": "scaling"},
	{"id": "rebuild", "label": "Rebuild destroyed walls", "base_cost": 50, "kind": "rebuild"},
]

const STRUCTURES: Array = [
	{"id": "turret", "label": "Build turret (placed just above you)", "base_cost": 150, "kind": "flat"},
	{"id": "turret_boost", "label": "Overcharge all turrets +30% dmg", "base_cost": 80, "kind": "scaling"},
]

static func cost_for(base_cost: int, level: int) -> int:
	return int(ceil(base_cost * pow(1.5, level)))
