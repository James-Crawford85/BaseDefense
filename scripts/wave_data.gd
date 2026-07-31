class_name WaveData
## Procedural wave schedule: 100 waves in 10 groups of 10. The shop only opens
## between groups, so waves inside a group chain back-to-back with just the
## incoming-wave breather. Each wave spends a growing point budget on spawn
## packs; heavier types unlock as the run progresses, and every group finale
## (wave 10, 20, ...) tops the wave off with a heavy escort pack.

const FINAL_WAVE := 100
const GROUP_SIZE := 10

## Roster ordered by unlock wave (insertion order matters for the finale pick).
## cost: budget points per unit · pack: min/max spawned per pack ·
## interval: base seconds between spawns within a pack.
const ROSTER: Dictionary = {
	"grunt": {"unlock": 1, "cost": 1.0, "pack": Vector2i(4, 9), "interval": 1.0},
	"runner": {"unlock": 3, "cost": 1.2, "pack": Vector2i(3, 8), "interval": 0.7},
	"stinger": {"unlock": 6, "cost": 1.4, "pack": Vector2i(4, 10), "interval": 0.5},
	"spitter": {"unlock": 9, "cost": 2.6, "pack": Vector2i(2, 5), "interval": 2.8},
	"brute": {"unlock": 13, "cost": 3.5, "pack": Vector2i(1, 3), "interval": 4.5},
	"ogre": {"unlock": 17, "cost": 4.5, "pack": Vector2i(1, 3), "interval": 5.5},
}

static func schedule(index: int) -> Array:
	var wave := index + 1
	var budget := 8.0 + 2.2 * index + 0.008 * index * index
	var unlocked: Array = []
	for key in ROSTER:
		if wave >= int(ROSTER[key].unlock):
			unlocked.append(key)
	var groups: Array = []
	var delay := 0.0
	while budget > 0.0:
		var key: String = unlocked[randi() % unlocked.size()]
		var def: Dictionary = ROSTER[key]
		var pack: Vector2i = def.pack
		var count := randi_range(pack.x, pack.y)
		count = mini(count, maxi(1, int(ceil(budget / float(def.cost)))))
		groups.append({"type": key, "count": count,
			"interval": float(def.interval) * randf_range(0.85, 1.15),
			"delay": delay})
		budget -= count * float(def.cost)
		delay += randf_range(1.5, 4.0)
	if wave % GROUP_SIZE == 0:
		# Group finale: BOSS pack of the heaviest unlocked type (6x HP, 4x
		# bounty, oversized) closing out the wave.
		var heavy: String = unlocked[unlocked.size() - 1]
		groups.append({"type": heavy, "count": 1 + wave / 25,
			"interval": 4.0, "delay": delay + 2.0, "boss": true})
	return groups

static func wave_clear_bonus(wave_index: int) -> int:
	var bonus := 8 + (wave_index + 1) * 2
	if (wave_index + 1) % GROUP_SIZE == 0:
		bonus *= 2  # group finale pays double going into the shop
	return bonus
