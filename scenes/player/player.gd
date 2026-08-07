class_name Player
extends CharacterBody2D
## The player tank. Class chassis (TankData) sets base stats and weapon slot
## layout; WeaponMount children do all the shooting. Tank steering: left/right
## pivot the hull on its center axis and up/down drive along its facing — since
## side mounts cover hull-relative 180° arcs, where you point the tank IS weapon
## aiming. Still co-op-ready: one self-contained scene per player.

signal died

var class_key := "assault"
## Which peer drives this tank. In multiplayer each peer simulates its own
## tank's movement (broadcast to everyone); combat/HP stay host-authoritative.
var peer_id := 1

var _net_pos := Vector2.ZERO
var _net_rot := 0.0
var _send_accum := 0.0
var _dead_visual := false

var max_hp := 100.0
var hp := 100.0
var move_speed := 240.0
var turn_speed := 2.8    # hull rotation rate in rad/s (tank-style steering)
var damage_mult := 1.0
var fire_rate_mult := 1.0
var range_mult := 1.0
var armor := 0.0
var regen := 0.0
var pickup_radius := 90.0
var crit_chance := 0.0   # chance any hit deals double damage (cap 60%)
var dodge := 0.0         # chance to ignore a hit entirely (cap 50%)
var engineering := 0.0   # towers YOU deploy: +15% damage / +20% HP per point
var kill_heal := 0.0     # "salvage": HP restored on every enemy kill
var greed := 1.0         # gold pickup multiplier
var proj_speed_mult := 1.0  # shot travel speed (hitscan/flame ignore this)
var aoe_mult := 1.0         # splash radius multiplier on explosive weapons
# Regenerating overhealth layer (see docs/stats.md). shield_max 0 = no shield.
var shield := 0.0
var shield_max := 0.0
var shield_recharge_rate := 0.25  # fraction of max restored per second
var shield_recharge_delay := 3.0  # seconds after a hit before recharge begins

var mounts: Array = []

var _invuln: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_time: float = 0.0
var _time_since_hit: float = 999.0  # drives shield recharge delay
var _shield_ring: Line2D = null

# Sprite chassis art, per class: a 2-frame track-animated base plus a separately-
# rotating turret. `turret_frames` 2 means the turret has an idle frame (0) and a
# firing/muzzle-flash frame (1). Classes without art fall back to the polygon tank.
const CHASSIS := {
	"heavy": {
		"base": "res://assets/Tank Base, Heavy - Sprite.png",
		"turret": "res://assets/Tank Base, Heavy - Canon.png",
		"turret_frames": 1,
	},
	"assault": {
		"base": "res://assets/Tank Base, Medium - Sprite.png",
		"turret": "res://assets/Tank Base, Autocanon - Sprite.png",
		"turret_frames": 2,
	},
}
const SPRITE_SCALE := 0.5
var _base_sprite: Sprite2D = null
var _cannon_sprite: Sprite2D = null
var _cannon_frames := 1
var _track_timer := 0.0
var _track_frame := 0
var _last_anim_pos := Vector2.ZERO

func setup(key: String) -> void:
	class_key = key

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 4) | (1 << 5)
	var data: Dictionary = TankData.CLASSES[class_key]
	max_hp = data.hp
	hp = max_hp
	move_speed = data.speed
	damage_mult = data.damage_mult
	fire_rate_mult = data.fire_rate_mult
	range_mult = data.range_mult
	armor = data.armor
	regen = data.regen
	pickup_radius = data.pickup_radius
	# Class seeds for the newer stats (default to neutral if a class omits them).
	turn_speed = data.get("turn_speed", turn_speed)
	crit_chance = data.get("crit_chance", crit_chance)
	dodge = data.get("dodge", dodge)
	engineering = data.get("engineering", engineering)
	greed = data.get("greed", greed)
	shield_max = data.get("shield", 0.0)
	shield = shield_max
	shield_recharge_rate = data.get("shield_recharge_rate", shield_recharge_rate)
	shield_recharge_delay = data.get("shield_recharge_delay", shield_recharge_delay)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	add_child(shape)
	var cfg: Variant = CHASSIS.get(class_key, null)
	if cfg != null and ResourceLoader.exists(cfg.base) and ResourceLoader.exists(cfg.turret):
		_build_sprite_hull(cfg)
	else:
		_build_hull(data.color)

	# Shield ring: a cyan halo whose opacity tracks the shield fraction.
	_shield_ring = Line2D.new()
	_shield_ring.width = 2.5
	_shield_ring.default_color = Color(0.4, 0.8, 1.0, 0.0)
	_shield_ring.z_index = 3
	var rp := PackedVector2Array()
	for i in range(25):
		var a := TAU * i / 24.0
		rp.append(Vector2(cos(a), sin(a)) * 26.0)
	_shield_ring.points = rp
	add_child(_shield_ring)

	for slot in data.slots:
		var mount := WeaponMount.new()
		mount.tank = self
		mount.position = slot.pos
		mount.arc_center = slot.center
		mount.arc_half = slot.half
		add_child(mount)
		mounts.append(mount)
	mounts[0].set_weapon(data.start_weapon, 1)
	# On the sprite chassis the cannon sprite is the main gun's visual, so hide
	# mount #1's placeholder polygon gun.
	if _cannon_sprite != null and not mounts.is_empty():
		mounts[0].set_gun_hidden(true)

func _build_hull(color: Color) -> void:
	for tx in [-17.0, 10.0]:
		var tread := Polygon2D.new()
		tread.polygon = PackedVector2Array([
			Vector2(tx, -20), Vector2(tx + 7, -20), Vector2(tx + 7, 20), Vector2(tx, 20)])
		tread.color = Color(0.14, 0.15, 0.16)
		add_child(tread)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([
		Vector2(-8, -22), Vector2(8, -22), Vector2(12, -14), Vector2(12, 18),
		Vector2(6, 22), Vector2(-6, 22), Vector2(-12, 18), Vector2(-12, -14)])
	hull.color = color
	add_child(hull)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([
		Vector2(-6, -20), Vector2(6, -20), Vector2(6, -16), Vector2(-6, -16)])
	stripe.color = color.lightened(0.35)
	add_child(stripe)

## Sprite chassis: track-animated base (frames flip while moving) + a main gun
## that rotates to face the nearest enemy, both centred on the hull. The base
## inherits hull rotation; the cannon's global rotation is driven independently.
func _build_sprite_hull(cfg: Dictionary) -> void:
	_base_sprite = Sprite2D.new()
	_base_sprite.texture = load(cfg.base)
	_base_sprite.hframes = 2         # two track-animation frames side by side
	_base_sprite.frame = 0
	_base_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_base_sprite.z_index = 1
	add_child(_base_sprite)
	_cannon_frames = int(cfg.turret_frames)
	_cannon_sprite = Sprite2D.new()
	_cannon_sprite.texture = load(cfg.turret)
	_cannon_sprite.hframes = _cannon_frames   # frame 0 idle, frame 1 muzzle flash
	_cannon_sprite.frame = 0
	_cannon_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_cannon_sprite.z_index = 2       # main gun draws over the base
	add_child(_cannon_sprite)
	_last_anim_pos = global_position

## Drives the sprite chassis visuals on every peer (local and remote tanks).
func _process(delta: float) -> void:
	if _base_sprite == null:
		return
	# Track animation: alternate the two frames while the tank is actually moving.
	var moved := global_position.distance_to(_last_anim_pos)
	_last_anim_pos = global_position
	if moved > 0.4:
		_track_timer += delta
		if _track_timer >= 0.08:
			_track_timer = 0.0
			_track_frame = 1 - _track_frame
			_base_sprite.frame = _track_frame
	# Main gun sprite follows mount #1's real aim, so barrel and shots agree.
	if _cannon_sprite != null and not mounts.is_empty():
		var m0: WeaponMount = mounts[0]
		_cannon_sprite.visible = m0.weapon_key != ""
		_cannon_sprite.global_rotation = m0.barrel_world_rotation()
		# Two-frame turrets flip to the muzzle-flash frame briefly after each shot.
		if _cannon_frames >= 2:
			_cannon_sprite.frame = 1 if m0.muzzle_flash > 0.0 else 0

func is_local() -> bool:
	return not Net.active() or peer_id == Net.my_id()

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	_invuln -= delta
	_dash_cooldown -= delta
	_dash_time -= delta
	if Net.is_authority():
		_time_since_hit += delta
		if regen > 0.0:
			hp = minf(hp + regen * delta, max_hp)
		# Shield refills once you've gone shield_recharge_delay seconds unhit.
		if shield_max > 0.0 and shield < shield_max and _time_since_hit >= shield_recharge_delay:
			shield = minf(shield_max, shield + shield_max * shield_recharge_rate * delta)
	_update_shield_ring()

	if not is_local():
		# Remote tank: follow the owner's broadcast transform.
		position = position.lerp(_net_pos, minf(1.0, 12.0 * delta))
		rotation = lerp_angle(rotation, _net_rot, 12.0 * delta)
		return

	# Tank controls: left/right pivot the hull on its center axis (even while
	# stationary), up/down drive along the way it's pointing. Reverse is slower,
	# like a real tank. Hull facing doubles as weapon aim, so steering aims too.
	var turn_input := Input.get_axis("move_left", "move_right")
	var drive_input := Input.get_axis("move_up", "move_down")  # up = -1, down = +1
	rotation += turn_input * turn_speed * delta
	var throttle := -drive_input  # forward is positive
	if throttle < 0.0:
		throttle *= 0.6           # reverse at 60% speed
	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0 and throttle != 0.0:
		_dash_time = 0.15
		_dash_cooldown = 1.0
		_invuln = maxf(_invuln, 0.25)
		Sfx.play("dash")
	var speed := move_speed * (2.4 if _dash_time > 0.0 else 1.0)
	velocity = Vector2.UP.rotated(rotation) * throttle * speed
	move_and_slide()

	if Net.active():
		_send_accum += delta
		if _send_accum >= 0.05 and Net.game != null:
			_send_accum = 0.0
			Net.game.rpc(&"net_player_pos", position, rotation)

func net_transform(pos: Vector2, rot: float) -> void:
	_net_pos = pos
	_net_rot = rot

## Fades the shield halo with the current shield fraction (runs on every peer).
func _update_shield_ring() -> void:
	if _shield_ring == null:
		return
	var frac: float = (shield / shield_max) if shield_max > 0.0 else 0.0
	_shield_ring.default_color = Color(0.4, 0.8, 1.0, 0.55 * frac if frac > 0.01 else 0.0)

## Snapshot HP + shield mirror on clients (host owns damage/heals/recharge).
func net_set_hp(new_hp: float, new_max: float, new_shield: float = 0.0, new_shield_max: float = 0.0) -> void:
	if Net.is_authority():
		return
	max_hp = new_max
	shield = new_shield
	shield_max = new_shield_max
	if new_hp < hp:
		Fx.flash(self)
	hp = new_hp
	if hp <= 0.0 and not _dead_visual:
		_die_visual()

func _die_visual() -> void:
	_dead_visual = true
	hp = 0.0
	hide()
	set_physics_process(false)
	collision_layer = 0

# --- Weapon slot management (shop hooks) ---

func has_empty_slot() -> bool:
	for m in mounts:
		if m.weapon_key == "":
			return true
	return false

func lowest_mount_with(key: String) -> WeaponMount:
	var best: WeaponMount = null
	for m in mounts:
		if m.weapon_key == key and (best == null or m.level < best.level):
			best = m
	return best

## Duplicate purchases upgrade the owned copy; otherwise fill an empty slot.
## Returns the changed mount index (-1 if nothing changed) so multiplayer can
## mirror the loadout on every peer.
func buy_weapon(key: String) -> int:
	var owned := lowest_mount_with(key)
	if owned != null and owned.level < WeaponData.MAX_LEVEL:
		owned.set_weapon(key, owned.level + 1)
		Fx.float_text(global_position, "%s → Lv %d" % [WeaponData.WEAPONS[key].label, owned.level], Color(0.5, 0.9, 1.0))
		return mounts.find(owned)
	for m in mounts:
		if m.weapon_key == "":
			m.set_weapon(key, 1)
			Fx.float_text(global_position, "%s mounted" % WeaponData.WEAPONS[key].label, Color(0.5, 0.9, 1.0))
			return mounts.find(m)
	return -1

## `count` lets shop cards sell bigger versions of the same upgrade (x2 / x3).
func apply_stat(id: String, count: int = 1) -> void:
	for i in range(count):
		match id:
			"max_hp":
				max_hp += 15.0
				hp = minf(hp + 15.0, max_hp)
			"damage":
				damage_mult *= 1.08
			"fire_rate":
				fire_rate_mult *= 1.08
			"speed":
				move_speed *= 1.06
			"range":
				range_mult *= 1.08
			"regen":
				regen += 0.6
			"armor":
				armor += 1.0
			"crit":
				crit_chance = minf(crit_chance + 0.05, 0.6)
			"dodge":
				dodge = minf(dodge + 0.04, 0.5)
			"engineering":
				engineering += 1.0
			"salvage":
				kill_heal += 0.5
			"greed":
				greed += 0.08

func heal(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(hp + amount, max_hp)

func take_damage(amount: float) -> void:
	if not Net.is_authority():
		return  # damage is host-authoritative; clients mirror via net_set_hp
	if _invuln > 0.0 or hp <= 0.0:
		return
	if randf() < dodge:
		Fx.float_text(global_position, "DODGE", Color(0.6, 0.9, 1.0))
		return
	_time_since_hit = 0.0  # taking a hit restarts the shield recharge delay
	var dmg := maxf(1.0, amount - armor)
	if shield > 0.0:  # the shield layer soaks damage before HP
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	if dmg > 0.0:
		hp -= dmg
	_invuln = 0.6
	Fx.flash(self)
	Fx.shake(4.0)
	Sfx.play("player_hit")
	if hp <= 0.0:
		_die_visual()
		died.emit()
