class_name TankData
## Player tank classes. Chassis stats + weapon slot layout.
## Slot angles are hull-local radians (0 = hull right, -PI/2 = hull forward);
## `half` is the half-angle of the firing arc — PI means full 360.

const CLASSES: Dictionary = {
	"assault": {
		"label": "Assault", "color": Color(0.45, 0.55, 0.35),
		"hp": 100.0, "speed": 240.0, "damage_mult": 1.1, "fire_rate_mult": 1.0,
		"range_mult": 1.0, "armor": 0.0, "regen": 0.0, "pickup_radius": 90.0,
		"start_weapon": "autocannon",
		"blurb": "Balanced hull. +10% damage.",
		"slots": [
			{"pos": Vector2(0, -2), "center": -PI / 2, "half": PI},      # main turret, 360
			{"pos": Vector2(-15, 4), "center": PI, "half": PI / 2},      # left mount, 180
			{"pos": Vector2(15, 4), "center": 0.0, "half": PI / 2},      # right mount, 180
		],
	},
	"heavy": {
		"label": "Heavy", "color": Color(0.4, 0.45, 0.55),
		"hp": 150.0, "speed": 185.0, "damage_mult": 1.0, "fire_rate_mult": 0.95,
		"range_mult": 1.0, "armor": 2.0, "regen": 0.0, "pickup_radius": 80.0,
		"start_weapon": "cannon",
		"blurb": "Slow fortress. 2 armor, 4 weapon slots.",
		"slots": [
			{"pos": Vector2(0, -2), "center": -PI / 2, "half": PI},
			{"pos": Vector2(-16, 4), "center": PI, "half": PI / 2},
			{"pos": Vector2(16, 4), "center": 0.0, "half": PI / 2},
			{"pos": Vector2(0, 16), "center": PI / 2, "half": PI / 2},   # rear mount, 180
		],
	},
	"scout": {
		"label": "Scout", "color": Color(0.75, 0.65, 0.35),
		"hp": 70.0, "speed": 300.0, "damage_mult": 1.0, "fire_rate_mult": 1.15,
		"range_mult": 1.0, "armor": 0.0, "regen": 0.0, "pickup_radius": 140.0,
		"start_weapon": "machinegun",
		"blurb": "Fast and greedy. +15% attack speed,\nbig pickup radius, only 2 slots.",
		"slots": [
			{"pos": Vector2(0, -2), "center": -PI / 2, "half": PI},
			{"pos": Vector2(0, 14), "center": PI / 2, "half": PI / 2},   # rear mount
		],
	},
}
