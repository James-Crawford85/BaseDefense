class_name TowerData
## The four purchasable tower types. behavior: "bullet" fires single-target
## projectiles, "aoe" fires slow exploding shells, "flame" ticks cone damage.

const TYPES: Dictionary = {
	"gatling": {
		"label": "Gatling", "cost": 120, "hp": 80.0, "damage": 3.5, "fire_rate": 6.0,
		"range": 240.0, "behavior": "bullet",
		"color": Color(0.55, 0.75, 0.95), "body_size": 32.0,
		"sprite": "res://assets/Turret_MachineGun.png",
	},
	"standard": {
		"label": "Guard", "cost": 150, "hp": 90.0, "damage": 10.0, "fire_rate": 2.5,
		"range": 280.0, "behavior": "bullet",
		"color": Color(0.3, 0.42, 0.6), "body_size": 36.0,
		"sprite": "res://assets/Turret_Autocannon.png",
	},
	"cannon": {
		"label": "Cannon", "cost": 220, "hp": 110.0, "damage": 35.0, "fire_rate": 0.5,
		"range": 320.0, "behavior": "aoe", "aoe_radius": 70.0,
		"color": Color(0.75, 0.45, 0.2), "body_size": 42.0,
		"sprite": "res://assets/Turret_Cannon.png",
	},
	"flame": {
		"label": "Flame", "cost": 180, "hp": 100.0, "damage": 2.5, "fire_rate": 7.0,
		"range": 140.0, "behavior": "flame", "cone_degrees": 45.0,
		"color": Color(0.95, 0.5, 0.25), "body_size": 34.0,
		"sprite": "res://assets/Turret_Flame.png",
	},
}
