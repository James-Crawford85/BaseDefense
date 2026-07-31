class_name ShopPanel
extends PanelContainer
## Between-group "armory": a 4-card randomized shop with escalating reroll.
## Buying out all four cards rolls a fresh hand for free. Wall repair stays a
## guaranteed fixed button so shop RNG can never lock the player out of it.
## Buttons take no keyboard focus so Space/Enter can't misfire purchases.
## (Level-up stat picks live in the HUD pause overlay now, not here.)

const REPAIR_COST := 40
const CARD_W := 180.0

const CARD_TEXTURES: Array = [
	preload("res://assets/card_lv1.png"),
	preload("res://assets/card_lv2.png"),
	preload("res://assets/card_lv3.png"),
	preload("res://assets/card_lv4.png"),
]

var main  # main.gd (untyped: it has no class_name)

var _cards: Array = []
var _card_widgets: Array = []
var _rerolls := 0

var _countdown_label: Label
var _reroll_btn: Button
var _repair_btn: Button

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -400
	offset_top = -252
	offset_right = 400
	offset_bottom = 252

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

	# One-row hand of art cards; the whole card is the buy button. Card frame
	# art comes from the tier templates (assets/card_lv1..4.png), text is
	# overlaid with anchors matched to the template's banner / body / footer.
	var tex0: Texture2D = CARD_TEXTURES[0]
	var card_h := CARD_W * tex0.get_height() / tex0.get_width()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)
	for i in range(4):
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(CARD_W, card_h)
		btn.pressed.connect(_on_buy.bind(i))
		grid.add_child(btn)
		var art := TextureRect.new()
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(art)
		var t := _card_label(btn, 0.09, 0.035, 0.91, 0.135, 13)
		var d := _card_label(btn, 0.12, 0.30, 0.88, 0.72, 12)
		d.add_theme_color_override("font_color", Color(0.82, 0.84, 0.86))
		var cost := _card_label(btn, 0.15, 0.76, 0.85, 0.92, 16)
		cost.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_card_widgets.append({"panel": btn, "art": art, "title": t, "desc": d, "cost": cost})

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

## Overlay label positioned by fractional anchors within a card's rect.
func _card_label(parent: Control, ax0: float, ay0: float, ax1: float, ay1: float, font_size: int) -> Label:
	var l := Label.new()
	l.anchor_left = ax0
	l.anchor_top = ay0
	l.anchor_right = ax1
	l.anchor_bottom = ay1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func open() -> void:
	visible = true
	_rerolls = 0
	_roll_cards()
	refresh()

func set_countdown(t: float) -> void:
	_countdown_label.text = "Next wave in %ds — or start it early" % int(ceil(maxf(t, 0.0)))

func _reroll_cost() -> int:
	return 6 + (main.wave_index + 1) * 3 + _rerolls * 4

func _roll_cards() -> void:
	_cards = CardPool.draw_cards(4, main.wave_index + 1, main.player, main)

func refresh() -> void:
	for i in range(_card_widgets.size()):
		var wdg: Dictionary = _card_widgets[i]
		if i >= _cards.size():
			wdg.panel.visible = false
			continue
		wdg.panel.visible = true
		var card: Dictionary = _cards[i]
		wdg.art.texture = CARD_TEXTURES[clampi(int(card.get("tier", 1)), 1, 4) - 1]
		wdg.title.text = String(card.title).to_upper()
		wdg.desc.text = card.desc
		if card.get("sold", false):
			wdg.cost.text = "SOLD"
			wdg.panel.modulate = Color(0.45, 0.45, 0.45)
		else:
			wdg.cost.text = "$%d" % int(card.cost)
			# Dim cards the player can't afford (still clickable; spend() guards).
			wdg.panel.modulate = Color.WHITE if int(card.cost) <= Game.money else Color(0.6, 0.58, 0.56)
	_reroll_btn.text = "Reroll $%d" % _reroll_cost()
	_reroll_btn.disabled = _reroll_cost() > Game.money
	_repair_btn.text = "Repair walls $%d" % REPAIR_COST
	_repair_btn.disabled = REPAIR_COST > Game.money or not main.repairable_walls()

func _on_buy(i: int) -> void:
	var card: Dictionary = _cards[i]
	if card.get("sold", false):
		return
	if not Game.spend(int(card.cost)):
		Sfx.play("deny", 0.0)
		return
	Sfx.play("buy", 0.0)
	match card.kind:
		"weapon":
			main.player.buy_weapon(card.key)
		"stat":
			main.player.apply_stat(card.key, int(card.get("count", 1)))
		"tower":
			main.add_tower_kit(card.key)
		"reinforce":
			main.reinforce_walls()
		"rebuild":
			main.rebuild_walls()
		"overcharge":
			Turret.damage_mult *= 1.3
	card["sold"] = true
	# Bought out the whole hand? Fresh cards on the house.
	var all_sold := true
	for c in _cards:
		if not c.get("sold", false):
			all_sold = false
			break
	if all_sold:
		_roll_cards()
		Sfx.play("reroll", 0.0)
	refresh()

func _on_reroll() -> void:
	if not Game.spend(_reroll_cost()):
		Sfx.play("deny", 0.0)
		return
	Sfx.play("reroll", 0.0)
	_rerolls += 1
	_roll_cards()
	refresh()

func _on_repair() -> void:
	if not main.repairable_walls():
		return
	if not Game.spend(REPAIR_COST):
		Sfx.play("deny", 0.0)
		return
	Sfx.play("buy", 0.0)
	main.repair_walls()
	refresh()
