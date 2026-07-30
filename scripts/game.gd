extends Node
## Autoload: run-wide state (money, kills, stats). Reset at the start of every run.

signal money_changed(amount: int)

var money: int = 0
var kills: int = 0
var waves_survived: int = 0
var total_earned: int = 0

func reset() -> void:
	money = 40
	kills = 0
	waves_survived = 0
	total_earned = 0
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

func register_kill(value: int) -> void:
	kills += 1
	add_money(value)
