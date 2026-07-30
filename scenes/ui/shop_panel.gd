class_name ShopPanel
extends PanelContainer
## Intermission "armory": free level-up stat picks (1 of 3 per level gained),
## then a 4-card randomized shop with escalating reroll. Wall repair stays a
## guaranteed fixed button so shop RNG can never lock the player out of it.
## Buttons take no keyboard focus so Space/Enter can't misfire purchases.

const REPAIR_COST := 40

var main  # main.gd (untyped: it has no class_name)

var _cards: Array = []
var _card_widgets: Array = []
var _pick_ids: Array = []
var _pick_buttons: Array = []
var _rerolls := 0

var _countdown_label: Label
var _pick_section: VBoxContainer
var _pick_label: Label
var _reroll_btn: Button
var _repair_btn: Button

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -262
	offset_top = -280
	offset_right = 262
	offset_bottom = 280

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "ARMORY — INTERMISSION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	vbox.add_child(title)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 14)
	_countdown_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(_countdown_label)

	_pick_section = VBoxContainer.new()
	_pick_section.add_theme_constant_override("separation", 4)
	vbox.add_child(_pick_section)
	_pick_label = Label.new()
	_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_label.add_theme_font_size_override("font_size", 15)
	_pick_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
	_pick_section.add_child(_pick_label)
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 6)
	_pick_section.add_child(pick_row)
	for i in range(3):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(166, 58)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_pick.bind(i))
		pick_row.add_child(b)
		_pick_buttons.append(b)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	for i in range(4):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(250, 108)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		panel.add_child(vb)
		var t := Label.new()
		t.add_theme_font_size_override("font_size", 15)
		vb.add_child(t)
		var d := Label.new()
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(240, 34)
		vb.add_child(d)
		var buy := Button.new()
		buy.focus_mode = Control.FOCUS_NONE
		buy.pressed.connect(_on_buy.bind(i))
		vb.add_child(buy)
		grid.add_child(panel)
		_card_widgets.append({"panel": panel, "title": t, "desc": d, "buy": buy})

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	_reroll_btn = Button.new()
	_reroll_btn.focus_mode = Control.FOCUS_NONE
	_reroll_btn.pressed.connect(_on_reroll)
	bottom.add_child(_reroll_btn)
	_repair_btn = Button.new()
	_repair_btn.focus_mode = Control.FOCUS_NONE
	_repair_btn.pressed.connect(_on_repair)
	bottom.add_child(_repair_btn)
	var start := Button.new()
	start.text = "START NEXT WAVE"
	start.focus_mode = Control.FOCUS_NONE
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func(): main.request_start_wave())
	bottom.add_child(start)

func open() -> void:
	visible = true
	_rerolls = 0
	_roll_cards()
	_refresh_picks()
	refresh()

func set_countdown(t: float) -> void:
	_countdown_label.text = "Next wave in %ds — or start it early" % int(ceil(maxf(t, 0.0)))

func _reroll_cost() -> int:
	return 6 + (main.wave_index + 1) * 3 + _rerolls * 4

func _roll_cards() -> void:
	_cards = CardPool.draw_cards(4, main.wave_index + 1, main.player, main)

func _refresh_picks() -> void:
	if Game.pending_picks <= 0:
		_pick_section.visible = false
		return
	_pick_section.visible = true
	_pick_label.text = "LEVEL UP! Choose a free upgrade (%d remaining)" % Game.pending_picks
	_pick_ids = CardPool.draw_stat_picks(3)
	for i in range(3):
		var s: Dictionary = CardPool.STATS[_pick_ids[i]]
		_pick_buttons[i].text = "%s\n%s" % [s.label, s.desc]

func _on_pick(i: int) -> void:
	if Game.pending_picks <= 0:
		return
	main.player.apply_stat(_pick_ids[i])
	Game.pending_picks -= 1
	_refresh_picks()

func refresh() -> void:
	for i in range(_card_widgets.size()):
		var wdg: Dictionary = _card_widgets[i]
		if i >= _cards.size():
			wdg.panel.visible = false
			continue
		wdg.panel.visible = true
		var card: Dictionary = _cards[i]
		wdg.title.text = card.title
		wdg.desc.text = card.desc
		if card.get("sold", false):
			wdg.buy.text = "SOLD"
			wdg.buy.disabled = true
		else:
			wdg.buy.text = "Buy  —  $%d" % int(card.cost)
			wdg.buy.disabled = int(card.cost) > Game.money
	_reroll_btn.text = "Reroll $%d" % _reroll_cost()
	_reroll_btn.disabled = _reroll_cost() > Game.money
	_repair_btn.text = "Repair walls $%d" % REPAIR_COST
	_repair_btn.disabled = REPAIR_COST > Game.money or not main.repairable_walls()

func _on_buy(i: int) -> void:
	var card: Dictionary = _cards[i]
	if card.get("sold", false):
		return
	if card.kind == "tower" and not main.can_place_turret():
		Fx.float_text(main.player.global_position, "Stand outside the walls!", Color(1, 0.5, 0.4))
		return
	if not Game.spend(int(card.cost)):
		return
	match card.kind:
		"weapon":
			main.player.buy_weapon(card.key)
		"stat":
			main.player.apply_stat(card.key)
		"tower":
			main.place_turret(card.key)
		"reinforce":
			main.reinforce_walls()
		"rebuild":
			main.rebuild_walls()
		"overcharge":
			Turret.damage_mult *= 1.3
	card["sold"] = true
	refresh()

func _on_reroll() -> void:
	if not Game.spend(_reroll_cost()):
		return
	_rerolls += 1
	_roll_cards()
	refresh()

func _on_repair() -> void:
	if not main.repairable_walls():
		return
	if not Game.spend(REPAIR_COST):
		return
	main.repair_walls()
	refresh()
