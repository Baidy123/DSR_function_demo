extends SceneTree

const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Pattern = preload("res://scripts/weapons/shotgun_pattern.gd")
var checks := 0
var failed := 0
var fired := 0

class Target extends StaticBody3D:
	var damage_received: float = 0
	var hit_events: int = 0
	var effects_received: Dictionary = {}
	var disable_on_hit: bool = false
	func get_torso_position() -> Vector3: return global_position
	func receive_weapon_hit(damage: float, _source: Vector3, effects: Dictionary) -> void:
		damage_received += damage
		hit_events += 1
		effects_received = effects
		if disable_on_hit: collision_layer = 0

class Listener extends Node:
	var notices: int = 0
	func _ready() -> void: add_to_group("shot_listener")
	func notice_shot(_origin: Vector3, _endpoint: Vector3, _effects: Dictionary) -> void: notices += 1


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)


func _run() -> void:
	_geometry()
	await _physics()
	await _actors()
	print("SHOTGUN: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)


func _geometry() -> void:
	var data: WeaponData = load("res://resources/weapons/test_shotgun.tres").duplicate(true)
	var gun := data.shotgun
	var rng := RandomNumberGenerator.new()
	rng.seed = 4251
	check(data.fire_mode == WeaponData.FireMode.SHOTGUN and data.ammo_type == WeaponData.AmmoType.SHOTGUN, "Fire Mode selects pellets within existing WeaponData and ammo slots")
	check(gun.get_aim_settings(false) == gun.get_aim_settings(true), "Both player aim modes and enemy share shotgun stability settings")
	for name in ["balanced", "horizontal", "vertical"]:
		gun.pattern = load("res://resources/weapons/patterns/%s.tres" % name)
		var points := gun.get_pattern_points()
		var sum := Vector2.ZERO
		for point in points: sum += point
		check(points.size() == 9 and sum.is_zero_approx(), name + " has nine balanced points without a biased center")
	gun.stable_jitter_degrees = 0.0
	gun.unstable_jitter_degrees = 0.0
	var stable := Ballistics.sample_offsets(gun, 1.0, rng)
	var unstable := Ballistics.sample_offsets(gun, 0.0, rng)
	check(stable == unstable, "Accuracy does not scale, rotate or translate the fixed pattern")
	gun.unstable_jitter_degrees = 0.55
	var bounded := true
	var independent := false
	var immutable := gun.pattern.points.duplicate()
	for sample in 64:
		var offsets := Ballistics.sample_offsets(gun, 0.0, rng)
		var first_delta: Vector2 = offsets[0] - stable[0]
		for i in offsets.size():
			bounded = bounded and offsets[i].distance_to(stable[i]) <= 0.55001
			independent = independent or not (offsets[i] - stable[i]).is_equal_approx(first_delta)
	check(bounded and independent, "Each pellet has its own bounded deviation, not a shared shift")
	check(immutable == gun.pattern.points, "Shooting never writes back to shared pattern resources")
	for axis in [Vector3.ZERO, Vector3.FORWARD, Vector3.UP, Vector3.DOWN]:
		var valid := true
		for direction in Ballistics.directions(axis, stable): valid = valid and direction.is_finite() and is_equal_approx(direction.length(), 1.0)
		check(valid, "Finite unit pellet directions for axis " + str(axis))
	var shot_direction := Ballistics.directions(Vector3.FORWARD, PackedVector2Array([Vector2(3, 0)]))[0]
	check(is_equal_approx(shot_direction.x / -shot_direction.z * 10.0, tan(deg_to_rad(3.0)) * 10.0), "Three degrees projects to the correct physical coverage at ten meters")
	gun.pattern = Pattern.new()
	gun.pattern.points = PackedVector2Array()
	check(gun.get_pattern_points().size() == 1, "Empty patterns have a safe one-pellet fallback")
	gun.pattern.points.resize(100)
	check(gun.get_pattern_points().size() == 64, "Oversized patterns have a bounded ray count")
	DirAccess.make_dir_recursive_absolute("res://logs/shotgun")
	gun.pattern = load("res://resources/weapons/patterns/horizontal.tres").duplicate(true)
	var error := ResourceSaver.save(data, "res://logs/shotgun/saved_gun.tres")
	var reloaded = load("res://logs/shotgun/saved_gun.tres")
	check(error == OK and reloaded is WeaponData and reloaded.fire_mode == WeaponData.FireMode.SHOTGUN and reloaded.shotgun.pattern.points == gun.pattern.points, "Independent weapon and custom pattern survive save/reload")
	var visible := []
	for property in gun.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR: visible.append(property.name)
	check("pellet_damage" in visible and "starting_stability" in visible and not "damage" in visible and not "min_spread_angle_degrees" in visible, "Shotgun inspector exposes used fields and hides legacy ballistic fields")
	var legacy := WeaponData.new()
	check(legacy.damage == 25 and legacy.get_aim_settings(false).initial == 0.5, "Old WeaponData defaults remain intact")


func _physics() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var shooter := CharacterBody3D.new()
	world.add_child(shooter)
	var center := _target(world, Vector3(0, 1, -10))
	var left := _target(world, Vector3(-0.524, 1, -10))
	var right := _target(world, Vector3(0.524, 1, -10))
	var gun := _test_gun(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(-1, 0), Vector2(1, 0)]))
	var rng := RandomNumberGenerator.new()
	await physics_frame
	await physics_frame
	var pellets := Ballistics.trace(shooter, gun, Vector3(0, 1, 0), Vector3.FORWARD, 1, rng)
	var hits := Ballistics.count_hits(pellets, &"combat_target")
	check(hits.size() == 3 and hits.get(center) == 2 and hits.get(left) == 1 and hits.get(right) == 1, "Each pellet follows its own ray and multiple targets can be hit")
	var wall := _target(world, Vector3(0, 1, -5))
	wall.remove_from_group("combat_target")
	await physics_frame
	await physics_frame
	pellets = Ballistics.trace(shooter, gun, Vector3(0, 1, 0), Vector3.FORWARD, 1, rng)
	hits = Ballistics.count_hits(pellets, &"combat_target")
	check(not hits.has(center) and hits.has(left) and hits.has(right), "Wall truncates only blocked pellets, not the entire shell")
	check(pellets[0].endpoint.z > -6 and pellets[0].collider == wall, "Real endpoints stop at the first collision")
	check(not Ballistics.near_miss_endpoint(center, Vector3(0, 1, 0), [pellets[0]], 1.5).is_finite(), "A stopped pellet cannot suppress behind the wall")
	var near := _target(world, Vector3(0.7, 1, -7))
	near.collision_layer = 0
	check(Ballistics.near_miss_endpoint(near, Vector3(0, 1, 0), pellets, 1.5).is_finite(), "An unhit nearby target can receive a visible pellet near miss")
	world.queue_free()
	await process_frame


func _actors() -> void:
	var scene = load("res://scenes/presentation/shotgun_range.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var combat = player.get_node("Combat")
	var equipment = player.get_node("Equipment")
	check(combat.weapon.fire_mode == WeaponData.FireMode.SHOTGUN and equipment.primary_weapon == combat.weapon, "F6 range equips new gun through original Equipment slot")
	combat.ammo.magazine_rounds -= 1
	combat.accuracy = 0.2
	combat.shot_cooldown = 0.5
	check(equipment.select_slot(1) and combat.weapon.fire_mode != WeaponData.FireMode.SHOTGUN, "Original Equipment can switch from shotgun to a legacy gun")
	check(equipment.select_slot(0) and combat.ammo.magazine_rounds == 5 and is_equal_approx(combat.accuracy, 0.2) and is_equal_approx(combat.shot_cooldown, 0.5), "Switching back preserves shotgun ammo, low stability and cooldown")
	for path in ["CombatTest/TargetA", "CombatTest/TargetB", "CombatTest/Cover"]:
		scene.get_node(path).position.x = 8
	var gun := _test_gun(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
	gun.shotgun.pellet_damage = 7
	gun.shotgun.shell_stability_loss = 0.2
	gun.shot_noise = null
	combat.equip_weapon(gun, false, combat.Ammo.new(gun, {WeaponData.AmmoType.SHOTGUN: 12}))
	var muzzle: Vector3 = player.get_muzzle_position()
	var front := _target(scene, muzzle + Vector3(0, 0, -1))
	front.disable_on_hit = true
	var behind := _target(scene, muzzle + Vector3(0, 0, -2))
	var hit_listener := Listener.new()
	front.add_child(hit_listener)
	var nearby := _target(scene, muzzle + Vector3(0.3, 0, -0.5))
	nearby.collision_layer = 0
	var near_listener := Listener.new()
	nearby.add_child(near_listener)
	for frame in 5: await physics_frame
	combat.is_aiming = true
	combat.accuracy = 1.0
	combat.clear_target_lock()
	combat.shot_fired.connect(func(_hit, _stability): fired += 1)
	var ammo_before: int = combat.ammo.magazine_rounds
	combat.shoot()
	check(front.hit_events == 1 and front.damage_received == 21 and behind.hit_events == 0, "All player rays resolve before death disables front collision; damage aggregates once")
	check(hit_listener.notices == 0 and near_listener.notices == 1, "Hit target gets no extra near miss; other target gets one notice per shell")
	check(combat.ammo.magazine_rounds == ammo_before - 1 and fired == 1 and combat.shot_count == 1, "One shell consumes one round and emits one shot")
	check(is_equal_approx(combat.accuracy, 0.8) and is_equal_approx(combat.shot_cooldown, gun.shot_interval), "One recoil penalty and cooldown per shell")
	combat.shoot()
	check(fired == 1, "Shotgun respects cooldown")
	combat.shot_cooldown = 0
	check(combat.ammo.start_reload(), "A spent shell can reload from a shotgun reserve pool")
	combat.shoot()
	check(fired == 1, "Shotgun cannot fire during reload")
	combat.ammo.advance_reload(gun.reload_seconds)
	check(combat.ammo.magazine_rounds == gun.magazine_capacity, "Shotgun reload uses existing magazine system")
	combat.ammo.magazine_rounds = 0
	combat.shoot()
	check(fired == 1, "Empty shotgun cannot fire")
	for body in [front, behind, nearby]: body.queue_free()
	await process_frame
	# A real enemy actor uses the same pellet geometry but retains its own attack and fire gates.
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.weapon = gun
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(0, 0, -3)
	enemy.equip_weapon(gun)
	enemy.shooting_enabled = true
	enemy.look_at(player.global_position)
	enemy.aim_direction = (player.get_torso_position() - enemy.get_shot_origin()).normalized()
	enemy.aim_acquired = true
	enemy.has_aim = true
	enemy.weapon_stability = 1
	player.get_node("Health").debug_invincible = false
	var health_before: float = player.get_node("Health").health
	var enemy_fired := [0]
	enemy.shot_fired.connect(func(): enemy_fired[0] += 1)
	for frame in 80: await physics_frame
	var enemy_rounds: int = enemy.ammo.magazine_rounds
	var success: bool = enemy.try_fire()
	check(success and enemy.shot_count == 1 and enemy_fired[0] == 1 and enemy.ammo.magazine_rounds == enemy_rounds - 1, "Real enemy fires one shell through normal ammo and signal path")
	check(is_equal_approx(health_before - player.get_node("Health").health, 21.0), "Enemy pellets aggregate actual player damage")
	check(is_equal_approx(enemy.weapon_stability, 0.8) and not enemy.try_fire(), "Enemy recoil once and cooldown still blocks another shot")
	enemy.shot_cooldown = 0
	enemy.global_position.x = 100
	enemy.offscreen_fire_chance = 0.0
	check(not enemy.try_fire(), "Shotgun enemies with zero offscreen chance skip the whole shell")
	check(equipment.secondary_weapon is WeaponData and equipment.secondary_weapon.fire_mode != WeaponData.FireMode.SHOTGUN, "Existing secondary resource is unchanged")
	gun.shot_interval = 0.9
	combat.ammo.magazine_rounds = 3
	combat.shot_cooldown = 0
	combat.is_aiming = true
	var count: int = combat.shot_count
	Input.action_press("aim")
	_fire_input(combat, true)
	combat.begin_frame(0.0, true)
	combat.end_frame(0.0, false)
	for frame in 10:
		combat.begin_frame(0.05, true)
		combat.end_frame(0.05, false)
	check(combat.shot_count == count + 1, "Semi-auto pellet mode fires once while holding the trigger")
	_fire_input(combat, false)
	_fire_input(combat, true)
	combat.begin_frame(0.0, true)
	combat.end_frame(0.0, false)
	check(combat.shot_count == count + 1, "Longer Shot Interval blocks rapid re-clicks to simulate pump pacing")
	combat.begin_frame(0.4, true)
	combat.end_frame(0.4, false)
	_fire_input(combat, false)
	_fire_input(combat, true)
	combat.begin_frame(0.0, true)
	combat.end_frame(0.0, false)
	check(combat.shot_count == count + 2, "After the interval a fresh trigger press fires the next shell")
	_fire_input(combat, false)
	Input.action_release("aim")
	scene.queue_free()
	await process_frame


func _target(parent: Node3D, at: Vector3) -> Target:
	var body := Target.new()
	body.position = at
	body.add_to_group("combat_target")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.18, 1, 0.18)
	body.add_child(shape)
	parent.add_child(body)
	return body


func _test_gun(points: PackedVector2Array) -> WeaponData:
	var gun := Data.new()
	# 本专项核对原弹丸基础伤害；概率爆头由 headshot_test 单独覆盖。
	gun.headshot_enabled = false
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.ammo_type = WeaponData.AmmoType.SHOTGUN
	gun.magazine_capacity = 6
	gun.aim_range = 18
	gun.shotgun.pattern = Pattern.new()
	gun.shotgun.pattern.points = points
	gun.shotgun.stable_jitter_degrees = 0
	gun.shotgun.unstable_jitter_degrees = 0
	return gun


func _fire_input(combat: Node, pressed: bool) -> void:
	if pressed: Input.action_press("fire")
	else: Input.action_release("fire")
	var event := InputEventAction.new()
	event.action = "fire"
	event.pressed = pressed
	combat._unhandled_input(event)
