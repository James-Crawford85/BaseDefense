class_name ShopPanel
extends PanelContainer
## Intermission shop: three tabs mirroring the three-way spending tension
## (character / fortress / outer structures). Mouse-driven for the prototype;
## buttons deliberately take no keyboard focus so Space/Enter can't misfire
## purchases while the player repositions.

var main  # main.gd (untyped: it has no class_name)

var _levels: Dictionary = {}
var _buttons: Array = []
var _countdown_label: Label

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -250
	offset_top = -220
	offset_right = 250
	offset_bottom = 220

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "INTERMISSION — SPEND YOUR MONEY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	vbox.add_child(title)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 15)
	_countdown_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(_countdown_label)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(460, 270)
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	vbox.add_child(tabs)
	_build_tab(tabs, "Character", UpgradeData.CHARACTER)
	_build_tab(tabs, "Fortress", UpgradeData.FORTRESS)
	_build_tab(tabs, "Structures", UpgradeData.STRUCTURES)

	var start := Button.new()
	start.text = "START NEXT WAVE"
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(func(): main.request_start_wave())
	vbox.add_child(start)

func _build_tab(tabs: TabContainer, tab_name: String, items: Array) -> void:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override("separation", 6)
	tabs.add_child(box)
	for item in items:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_try_buy.bind(item))
		box.add_child(btn)
		_buttons.append({"btn": btn, "item": item})

func open() -> void:
	visible = true
	refresh()

func set_countdown(t: float) -> void:
	_countdown_label.text = "Next wave in %ds — or start it early" % int(ceil(maxf(t, 0.0)))

func _cost(item: Dictionary) -> int:
	match item.kind:
		"rebuild":
			return item.base_cost * int(main.destroyed_wall_count())
		"flat":
			return item.base_cost
		"tower":
			return TowerData.TYPES[item.tower].cost
		_:
			return UpgradeData.cost_for(item.base_cost, _levels.get(item.id, 0))

func refresh() -> void:
	for entry in _buttons:
		var item: Dictionary = entry.item
		var cost := _cost(item)
		var lvl: int = _levels.get(item.id, 0)
		var txt: String = "%s  —  $%d" % [item.label, cost]
		if item.kind == "scaling" and lvl > 0:
			txt += "  (Lv %d)" % lvl
		var disabled: bool = cost > Game.money
		match item.id:
			"repair":
				disabled = disabled or not main.repairable_walls()
			"rebuild":
				disabled = disabled or main.destroyed_wall_count() == 0
		entry.btn.text = txt
		entry.btn.disabled = disabled

func _try_buy(item: Dictionary) -> void:
	var cost := _cost(item)
	if item.kind == "tower" and not main.can_place_turret():
		Fx.float_text(main.player.global_position, "Stand outside the walls!", Color(1, 0.5, 0.4))
		return
	if not Game.spend(cost):
		return
	_apply(item)
	if item.kind == "scaling":
		_levels[item.id] = _levels.get(item.id, 0) + 1
	refresh()

func _apply(item: Dictionary) -> void:
	if item.kind == "tower":
		main.place_turret(item.tower)
		return
	var p: Player = main.player
	match item.id:
		"damage":
			p.damage *= 1.25
		"fire_rate":
			p.fire_rate *= 1.2
		"speed":
			p.move_speed *= 1.1
		"max_hp":
			p.max_hp += 25.0
			p.hp = minf(p.hp + 25.0, p.max_hp)
		"range":
			p.fire_range *= 1.15
		"repair":
			main.repair_walls()
		"reinforce":
			main.reinforce_walls()
		"rebuild":
			main.rebuild_walls()
		"turret_boost":
			Turret.damage_mult *= 1.3
