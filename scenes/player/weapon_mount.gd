class_name WeaponMount
extends Node2D
## One weapon slot on a tank. Sits at a fixed hull position with a firing arc
## (hull-local); the gun graphic traverses independently to track targets and
## clamps at its arc limits, so arcs read visually. The gun's look encodes the
## weapon (barrel shape/count) and its level (tier band color, barrel length).

const SHOT_SFX := {"machinegun": "shot_mg", "autocannon": "shot_auto", "cannon": "shot_cannon"}

var tank: Player
var arc_center := 0.0   # hull-local radians
var arc_half := PI      # PI = full 360
var weapon_key := ""
var level := 0

var _stats: Dictionary = {}
var _cooldown := 0.0
var _gun: Node2D
var _cone: Polygon2D

func set_weapon(key: String, lvl: int) -> void:
	weapon_key = key
	level = lvl
	_stats = WeaponData.scaled(key, lvl)
	_rebuild_gun()

func _rebuild_gun() -> void:
	if _gun != null:
		_gun.queue_free()
	if _cone != null:
		_cone.queue_free()
		_cone = null
	_gun = Node2D.new()
	add_child(_gun)
	var w: Dictionary = WeaponData.WEAPONS[weapon_key]
	var col: Color = w.color
	var barrels: int = w.barrels
	var blen := 13.0 + 2.5 * level

	var base := Polygon2D.new()
	var base_pts := PackedVector2Array()
	for i in range(10):
		var a := TAU * i / 10.0
		base_pts.append(Vector2(cos(a), sin(a)) * 6.0)
	base.polygon = base_pts
	base.color = Color(0.18, 0.2, 0.23)
	_gun.add_child(base)

	for b in range(barrels):
		var barrel := Polygon2D.new()
		var x := (b - (barrels - 1) / 2.0) * 4.5
		barrel.polygon = PackedVector2Array([
			Vector2(x - 1.3, 0), Vector2(x + 1.3, 0),
			Vector2(x + 1.3, -blen), Vector2(x - 1.3, -blen)])
		barrel.color = col
		_gun.add_child(barrel)

	if w.behavior == "flame":
		var nozzle := Polygon2D.new()
		nozzle.polygon = PackedVector2Array([
			Vector2(-3.5, -blen), Vector2(3.5, -blen), Vector2(0, -blen - 5.0)])
		nozzle.color = col.darkened(0.3)
		_gun.add_child(nozzle)
		_cone = Polygon2D.new()
		var pts := PackedVector2Array([Vector2.ZERO])
		var half := deg_to_rad(_stats.cone_degrees) / 2.0
		for i in range(7):
			var a := -half + (half * 2.0) * i / 6.0
			pts.append(Vector2(cos(a), sin(a)) * float(_stats.range))
		_cone.polygon = pts
		_cone.color = Color(1.0, 0.55, 0.2, 0.22)
		_cone.visible = false
		add_child(_cone)

	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([
		Vector2(-4.5, 3), Vector2(4.5, 3), Vector2(4.5, 6), Vector2(-4.5, 6)])
	band.color = WeaponData.TIER_COLORS[level - 1]
	_gun.add_child(band)
	_gun.rotation = arc_center + PI / 2.0

func _physics_process(delta: float) -> void:
	if weapon_key == "" or tank == null:
		return
	_cooldown -= delta
	var range_eff: float = _stats.range * tank.range_mult
	var target := _acquire(range_eff)

	# Traverse the gun: toward the target (clamped to the arc) or back to rest.
	var desired_local := arc_center
	if target != null:
		var local := wrapf((target.global_position - global_position).angle() - tank.global_rotation, -PI, PI)
		var diff := clampf(wrapf(local - arc_center, -PI, PI), -arc_half, arc_half)
		desired_local = arc_center + diff
	_gun.rotation = lerp_angle(_gun.rotation, desired_local + PI / 2.0, 10.0 * delta)

	if _stats.behavior == "flame":
		_flame_tick(target, range_eff)
	elif target != null and _cooldown <= 0.0 and Net.is_authority():
		# Firing (and damage) is simulation-authority only; clients see the
		# tracer via the broadcast_shot event and just traverse their guns.
		var dir := (target.global_position - global_position).normalized()
		var aoe: float = _stats.aoe_radius
		var dmg: float = _stats.damage * tank.damage_mult
		if randf() < tank.crit_chance:
			dmg *= 2.0
			Fx.float_text(global_position, "CRIT", Color(1.0, 0.8, 0.3))
		var speed := 420.0 if aoe > 0.0 else 620.0
		var p := Projectile.new()
		p.setup(dir, dmg, range_eff + 80.0,
			WeaponData.WEAPONS[weapon_key].color, false, aoe, speed)
		p.position = global_position + dir * 14.0
		tank.get_parent().add_child(p)
		_cooldown = 1.0 / (_stats.fire_rate * tank.fire_rate_mult)
		var sfx: String = SHOT_SFX.get(weapon_key, "shot_auto")
		Sfx.play(sfx)
		if Net.game != null:
			Net.game.broadcast_shot(p.position, dir, speed, range_eff + 80.0,
				WeaponData.WEAPONS[weapon_key].color, sfx)

func _flame_tick(target: Node2D, range_eff: float) -> void:
	if _cone == null:
		return
	if target == null:
		_cone.visible = false
		return
	_cone.rotation = _gun.rotation - PI / 2.0
	_cone.visible = true
	if _cooldown > 0.0 or not Net.is_authority():
		return
	_cooldown = 1.0 / (_stats.fire_rate * tank.fire_rate_mult)
	Sfx.play("flame")
	if Net.hosting():
		Net.game.rpc(&"cl_sfx", "flame")
	var aim := tank.global_rotation + _gun.rotation - PI / 2.0
	var aim_dir := Vector2.from_angle(aim)
	var half := deg_to_rad(_stats.cone_degrees) / 2.0
	var dmg: float = _stats.damage * tank.damage_mult
	if randf() < tank.crit_chance:
		dmg *= 2.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Enemy
		if n == null:
			continue
		var off := n.global_position - global_position
		if off.length() <= range_eff and absf(aim_dir.angle_to(off)) <= half:
			n.take_damage(dmg)

func _acquire(range_eff: float) -> Node2D:
	var best: Node2D = null
	var best_d := range_eff * range_eff
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(global_position)
		if d >= best_d:
			continue
		if arc_half < PI:
			var local := wrapf((n.global_position - global_position).angle() - tank.global_rotation, -PI, PI)
			if absf(wrapf(local - arc_center, -PI, PI)) > arc_half:
				continue
		best_d = d
		best = n
	return best
