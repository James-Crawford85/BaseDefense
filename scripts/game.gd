extends Node
## Autoload: run-wide state — gold, XP/levels, kills. Reset every run.
## Level-ups bank "stat picks" the player spends at the next intermission.

signal money_changed(amount: int)

var money: int = 0  # gold
var kills: int = 0
var waves_survived: int = 0
var total_earned: int = 0
var xp: int = 0
var level: int = 1
var pending_picks: int = 0

func reset() -> void:
	money = 30
	kills = 0
	waves_survived = 0
	total_earned = 0
	xp = 0
	level = 1
	pending_picks = 0
	Turret.damage_mult = 1.0
	money_changed.emit(money)

func add_money(amount: int) -> void:
	money += amount
	total_earned += amount
	money_changed.emit(money)

func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

func xp_needed() -> int:
	return 8 + 6 * level

func add_xp(amount: int) -> void:
	xp += amount
	var leveled := false
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		pending_picks += 1
		leveled = true
	if leveled:
		Sfx.play("level_up", 0.0)

func register_kill() -> void:
	kills += 1
