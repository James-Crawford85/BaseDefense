class_name EnemyData
## Speed and damage derive from the `weights` triangle (speed, damage, health
## — normalized, so leaning one way costs the others); HP is explicit per type
## for direct kill-feel tuning. Money value is derived from the final stats,
## so new types price themselves.
##
## Every vehicle is RANGED (they're gun platforms): attack_range is the
## distance it stops at to open fire. Short-range types (bikes, rams) still
## have to drive nearly into your lap; long-range siege types (>=150) pay a
## 25% damage tax for shelling from safety.

## hp is explicit per class so the kill-feel is directly tunable: light types
## die to 1-3 level-1 hits on wave 1 (MG 3 dmg / autocannon 9 / cannon 30),
## heavies take real focus, and group-finale bosses multiply on top of this.
const TYPES: Dictionary = {
	"grunt": {  # mid-range line tank — the 1-3 hit baseline
		"weights": Vector3(0.34, 0.33, 0.33), "cooldown": 1.0, "attack_range": 130.0, "hp": 10.0,
		"body_size": 24.0, "color": Color(0.5, 0.32, 0.6), "vehicle": "light_tank", "seeks_gaps": false,
	},
	"runner": {  # short-range harasser — 2 MG hits / 1 autocannon
		"weights": Vector3(0.7, 0.15, 0.15), "cooldown": 0.8, "attack_range": 90.0, "hp": 6.0,
		"body_size": 18.0, "color": Color(0.95, 0.85, 0.3), "vehicle": "buggy", "seeks_gaps": true,
	},
	"stinger": {  # point-blank drive-by — dies to any single hit
		"weights": Vector3(0.85, 0.1, 0.05), "cooldown": 0.6, "attack_range": 50.0, "hp": 3.0,
		"body_size": 14.0, "color": Color(0.4, 0.9, 0.95), "vehicle": "bike", "seeks_gaps": true,
	},
	"brute": {  # heavy — has to shove its gun in your face, soaks a clip
		"weights": Vector3(0.1, 0.25, 0.65), "cooldown": 1.6, "attack_range": 60.0, "hp": 60.0,
		"body_size": 40.0, "color": Color(0.85, 0.35, 0.35), "vehicle": "apc", "seeks_gaps": false,
	},
	"ogre": {  # heavy long-range siege cannon
		"weights": Vector3(0.05, 0.5, 0.45), "cooldown": 1.8, "attack_range": 240.0, "hp": 40.0,
		"body_size": 36.0, "color": Color(0.85, 0.55, 0.2), "vehicle": "siege", "seeks_gaps": false,
	},
	"spitter": {  # artillery — extreme range, light chassis
		"weights": Vector3(0.25, 0.5, 0.25), "cooldown": 1.5, "attack_range": 300.0, "hp": 14.0,
		"body_size": 22.0, "color": Color(0.9, 0.45, 0.75), "vehicle": "artillery", "seeks_gaps": false,
	},
}

# Per-wave difficulty growth, applied at spawn time (see wave_scaled):
# HP outpaces damage so late waves demand both firepower AND survivability.
# Base HP values are small (1-3 hit lights), so HP leans on this growth.
const HP_GROWTH := 0.10
const DAMAGE_GROWTH := 0.045
# Bounty grows on sqrt(wave) rather than linearly: it climbs quickly through the
# early waves (when you need those first upgrades) then flattens out, so the
# swelling late-wave swarms don't multiply into insane payouts. Since the number
# of enemies dropping gold already rises every wave (the wave budget grows), a
# gentle per-coin curve is enough. Paired with the linear HP growth above, income
# never keeps pace with cost on its own -- players have to invest in greed
# ("War Profiteer") to actually get rich.
const MONEY_GROWTH := 0.16

# Group-finale boss packs: multipliers on top of wave scaling.
const BOSS_HP_MULT := 6.0
const BOSS_MONEY_MULT := 4.0
const BOSS_SIZE_MULT := 1.25

static var _cache: Dictionary = {}

static func stats_for(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var def: Dictionary = TYPES[key]
	var w: Vector3 = def.weights
	var total := w.x + w.y + w.z
	var sw := w.x / total
	var dw := w.y / total
	var siege: bool = def.attack_range >= 150.0
	var speed := 25.0 + 145.0 * sw
	var hp: float = def.hp
	var dps := 3.0 + 30.0 * dw
	var damage: float = dps * def.cooldown * (0.75 if siege else 1.0)
	var stats := {
		"hp": hp,
		"speed": speed,
		"damage": damage,
		"attack_cooldown": def.cooldown,
		"attack_range": def.attack_range,
		# Base bounty is deliberately tiny: 1-2 for light chassis, ~3 for heavies,
		# so a fresh coin is worth 1-3 gold. Wave scaling (below) grows this and
		# greed upgrades multiply it -- gold stays a resource you choose how to
		# spend, not something you drown in.
		"money": maxi(1, int(round(0.6 + hp / 40.0 + dps / 22.0 + speed / 320.0))),
		"body_size": def.body_size,
		"color": def.color,
		"vehicle": def.vehicle,
		"seeks_gaps": def.seeks_gaps,
	}
	_cache[key] = stats
	return stats

static func wave_scaled(key: String, wave: int, boss: bool = false) -> Dictionary:
	var s := stats_for(key).duplicate()
	var w := maxi(wave - 1, 0)
	s.hp = s.hp * (1.0 + HP_GROWTH * w)
	s.damage = s.damage * (1.0 + DAMAGE_GROWTH * w)
	s.money = maxi(1, int(round(s.money * (1.0 + MONEY_GROWTH * sqrt(float(w))))))
	if boss:
		s.hp = s.hp * BOSS_HP_MULT
		s.money = int(round(s.money * BOSS_MONEY_MULT))
		s.body_size = s.body_size * BOSS_SIZE_MULT
	return s
