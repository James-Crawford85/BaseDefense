class_name CardPool
## Builds the randomized intermission card offers. Cards are plain dicts:
## {id, kind, key, title, desc, cost, weight, tier}. tier (1-4) picks the card
## frame art (weapon upgrades use the target level). Weapon cards adapt to the
## player's loadout (mount new vs. upgrade owned). Stat definitions here are
## shared by paid shop cards and free level-up picks (player.apply_stat).

const STATS: Dictionary = {
	"max_hp": {"label": "Reinforced Plating", "desc": "+15 Max HP (and heal 15)"},
	"damage": {"label": "Heavy Shells", "desc": "+8% damage"},
	"fire_rate": {"label": "Autoloader", "desc": "+8% attack speed"},
	"speed": {"label": "Tuned Engine", "desc": "+6% move speed"},
	"range": {"label": "Gunnery Optics", "desc": "+8% weapon range"},
	"regen": {"label": "Repair Drones", "desc": "+0.6 HP/s regeneration"},
	"armor": {"label": "Spaced Armor", "desc": "+1 armor (flat damage reduction)"},
}

static func draw_stat_picks(count: int) -> Array:
	var ids := STATS.keys()
	ids.shuffle()
	return ids.slice(0, count)

static func draw_cards(count: int, wave: int, player: Player, main) -> Array:
	var pool: Array = []
	for key in WeaponData.WEAPONS:
		var w: Dictionary = WeaponData.WEAPONS[key]
		var owned: WeaponMount = player.lowest_mount_with(key)
		if owned != null and owned.level < WeaponData.MAX_LEVEL:
			pool.append({"id": "w_" + key, "kind": "weapon", "key": key,
				"title": w.label, "desc": "Upgrade to Lv %d" % (owned.level + 1),
				"cost": int(w.cost) * (owned.level + 1) + wave * 5, "weight": 3,
				"tier": owned.level + 1})
		elif player.has_empty_slot():
			pool.append({"id": "w_" + key, "kind": "weapon", "key": key,
				"title": w.label, "desc": "Mount on an empty slot",
				"cost": int(w.cost) + wave * 5, "weight": 3, "tier": 1})
	for id in STATS:
		var s: Dictionary = STATS[id]
		pool.append({"id": "s_" + id, "kind": "stat", "key": id,
			"title": s.label, "desc": s.desc, "cost": 18 + wave * 4, "weight": 2, "tier": 1})
	for key in TowerData.TYPES:
		var t: Dictionary = TowerData.TYPES[key]
		pool.append({"id": "t_" + key, "kind": "tower", "key": key,
			"title": "%s Tower" % t.label, "desc": "Deployed just ahead of you — must stand outside the walls",
			"cost": int(t.cost), "weight": 2, "tier": 2})
	pool.append({"id": "reinforce", "kind": "reinforce", "key": "",
		"title": "Reinforce Walls", "desc": "All wall segments +30% HP",
		"cost": 50 + wave * 5, "weight": 2, "tier": 1})
	if main.destroyed_wall_count() > 0:
		pool.append({"id": "rebuild", "kind": "rebuild", "key": "",
			"title": "Rebuild Walls", "desc": "Rebuild all destroyed segments",
			"cost": 50 * int(main.destroyed_wall_count()), "weight": 3, "tier": 2})
	pool.append({"id": "overcharge", "kind": "overcharge", "key": "",
		"title": "Tower Overcharge", "desc": "+30% damage to all towers",
		"cost": 90 + wave * 5, "weight": 1, "tier": 3})

	var cards: Array = []
	while cards.size() < count and not pool.is_empty():
		var total := 0
		for c in pool:
			total += int(c.weight)
		var r := randi() % total
		var acc := 0
		for i in range(pool.size()):
			acc += int(pool[i].weight)
			if r < acc:
				cards.append(pool[i])
				pool.remove_at(i)
				break
	return cards
