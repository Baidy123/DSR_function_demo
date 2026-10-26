extends SceneTree

var checks := 0
var failed := 0
var world: Node3D
var player
var combat
var target: Target
var gun: WeaponData
var fired := 0
var headshots: Array = []

class Target extends StaticBody3D:
	var damage_received := 0.0
	var hit_events := 0
	var effects_received := {}
	var retire_on_hit := false
	func receive_weapon_hit(damage: float, _source: Vector3, effects: Dictionary) -> void:
		damage_received += damage
		hit_events += 1
		effects_received = effects
		if retire_on_hit:
			collision_layer = 0
			remove_from_group("combat_target")

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.add_to_group("combat_zone")
	_box(zone, Vector3(100, 10, 100))
	world.add_child(zone)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	combat.shot_fired.connect(func(_hit, _accuracy): fired += 1)
	if combat.has_signal("headshot_hit"):
		combat.headshot_hit.connect(func(point, count, shotgun): headshots.append([point, count, shotgun]))
	gun = WeaponData.new()
	gun.shot_noise = null
	gun.min_spread_angle_degrees = 0
	gun.max_spread_angle_degrees = 0
	gun.damage = 25
	gun.magazine_capacity = 300
	gun.headshot_chance = 1
	# 保留旧显式倍率的兼容用例；新默认与秒杀／硬直另行验证。
	gun.headshot_damage_multiplier = 2.5
	combat.equip_weapon(gun)
	target = _target(Vector3(0, 0.9, -5))
	for frame in 4: await physics_frame
	check(combat.can_combat(), "Real player is in a physical combat zone")
	for mode in [0, 1]:
		combat.aim_mode = mode
		check(is_equal_approx(_shoot(1), 62.5), "Mode %d: full precision applies 2.5x actual hit damage" % mode)
		check(combat.accuracy < 1 if mode == 0 else true, "Eligibility uses pre-recoil precision")
	combat.aim_mode = 1
	check(is_equal_approx(_shoot(0.999), 25), "99.9 percent is not full precision")
	gun.headshot_chance = 0
	check(is_equal_approx(_shoot(1), 25), "Zero chance keeps ordinary damage")
	gun.headshot_chance = 1
	gun.headshot_enabled = false
	check(is_equal_approx(_shoot(1), 25), "Per-weapon disable keeps ordinary damage")
	gun.headshot_enabled = true
	gun.headshot_damage_multiplier = 3
	check(is_equal_approx(_shoot(1), 75), "Per-weapon multiplier is total damage, not additional damage")
	gun.headshot_damage_multiplier = 2.5
	gun.fire_mode = WeaponData.FireMode.AUTOMATIC
	check(is_equal_approx(_shoot(1), 62.5), "Automatic weapons have the same full-precision eligibility")
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	player.crouch_amount = 1
	check(is_equal_approx(_shoot(0.75), 25), "Crouching with unfinished convergence cannot grant headshots, even with zero spread")
	check(is_equal_approx(_shoot(1.0), 62.5), "Crouching retains headshots after base convergence completes")
	combat.crouch_bonus_blocked_until_recovery = true
	check(is_equal_approx(_shoot(0.75), 25), "Blocked crouch bonus cannot grant eligibility")
	player.crouch_amount = 0
	combat.crouch_bonus_blocked_until_recovery = false
	var wall := _target(Vector3(0, 0.9, -2))
	wall.remove_from_group("combat_target")
	for frame in 3: await physics_frame
	check(is_zero_approx(_shoot(1)) and wall.hit_events == 0, "Wall blocks damage at 100 percent headshot chance")
	wall.queue_free()
	for frame in 3: await physics_frame
	gun.fire_range = 2
	check(is_zero_approx(_shoot(1)), "Out-of-range ray cannot create bonus damage")
	gun.fire_range = 30
	await _additional_checks()
	world.queue_free()
	await process_frame
	print("HEADSHOT: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _additional_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	combat._headshot_rng.seed = 7341
	gun.headshot_chance = 0.5
	var critical_count := 0
	var expected_count := 0
	var actual_damage := 0.0
	var all_match := true
	for shot in 64:
		var expected := rng.randf() < 0.5
		if expected: expected_count += 1
		var damage := _shoot(1)
		actual_damage += damage
		if damage > 25: critical_count += 1
		all_match = all_match and is_equal_approx(damage, 62.5 if expected else 25.0)
	check(all_match and critical_count == expected_count and critical_count > 0 and critical_count < 64, "50 percent samples produce both outcomes with the configured probability")
	check(is_equal_approx(actual_damage, 25 * (64 + expected_count * 1.5)), "Only successful rolls contribute bonus damage")
	seed(416)
	var next_ballistic := randf()
	seed(416)
	_shoot(1)
	check(randf() == next_ballistic, "Headshot randomness does not consume the ordinary ballistic random stream")
	gun.headshot_chance = 1
	var bystander := _target(Vector3(0, 0.9, -2))
	for frame in 3: await physics_frame
	var locked_before := target.damage_received
	combat.is_aiming = true
	combat.accuracy = 1
	combat.shot_cooldown = 0
	combat.locked_target = target
	combat.shoot()
	check(is_equal_approx(bystander.damage_received, 62.5) and target.damage_received == locked_before, "Actual intervening target receives damage instead of the old lock")
	bystander.queue_free()
	for frame in 3: await physics_frame
	var shots_before: int = combat.shot_count
	var rounds_before: int = combat.ammo.magazine_rounds
	combat.shoot()
	check(combat.shot_count == shots_before and combat.ammo.magazine_rounds == rounds_before, "Headshots do not bypass cooldown or consume extra ammunition")
	combat.shot_cooldown = 0
	combat.ammo.magazine_rounds = 0
	combat.shoot()
	check(combat.shot_count == shots_before, "Empty magazine still blocks shots")
	combat.ammo.magazine_rounds = 2
	paused = true
	combat.shoot()
	paused = false
	check(combat.shot_count == shots_before, "Paused shots cannot roll headshots")
	await _shotgun_checks()
	await _enemy_checks()
	await _feedback_checks()
	var defaults := WeaponData.new()
	check(defaults.headshot_enabled and defaults.headshot_chance == 0.1 and defaults.headshot_damage_multiplier == 3 and defaults.headshot_instant_kill_enabled and defaults.headshot_stagger_seconds == 1.0, "Existing resources inherit the latest headshot defaults without rewriting tres files")
	gun.headshot_chance = 0.37
	gun.headshot_damage_multiplier = 3.25
	DirAccess.make_dir_recursive_absolute("res://logs/headshot")
	var path := "res://logs/headshot/roundtrip.tres"
	var saved := ResourceSaver.save(gun, path)
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved == OK and restored.headshot_chance == 0.37 and restored.headshot_damage_multiplier == 3.25, "Per-weapon headshot configuration survives save and reload")
	gun.headshot_chance = NAN
	check(gun.get_headshot_chance(1) == 0 and gun.get_headshot_chance(NAN) == 0, "Invalid values never grant eligibility")
	gun.headshot_damage_multiplier = NAN
	check(gun.get_headshot_damage_multiplier() == 1, "Invalid multiplier cannot propagate NaN into health")
	gun.headshot_chance = 1
	gun.fire_mode = WeaponData.FireMode.MELEE
	check(gun.get_headshot_chance(1) == 0, "Melee weapons have no headshot eligibility")

func _shotgun_checks() -> void:
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	gun.shotgun.stable_jitter_degrees = 0
	gun.shotgun.unstable_jitter_degrees = 0
	gun.shotgun.pellet_damage = 7
	gun.shotgun.shell_stability_loss = 0.2
	combat.equip_weapon(gun)
	var behind := _target(Vector3(0, 0.9, -7))
	target.retire_on_hit = true
	for frame in 3: await physics_frame
	var hits_before := target.hit_events
	var signals_before := fired
	var rounds_before: int = combat.ammo.magazine_rounds
	check(is_equal_approx(_shoot(1), 52.5) and target.hit_events == hits_before + 1 and behind.hit_events == 0, "All three pellet rays resolve before target death, with one combined 2.5x hit")
	check(fired == signals_before + 1 and combat.ammo.magazine_rounds == rounds_before - 1 and is_equal_approx(combat.accuracy, 0.8), "Shotgun headshots keep one signal, round and recoil per shell")
	check(headshots.back()[1] == 3 and headshots.back()[2], "Legacy signal reports all pellets affected by the target's single roll")
	check(target.effects_received == gun.get_attack_effects(), "Damage multiplier leaves accuracy and movement effects unchanged")
	target.retire_on_hit = false
	target.collision_layer = 1
	target.add_to_group("combat_target")
	behind.queue_free()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(-1, 0), Vector2(1, 0)])
	gun.shotgun.pattern_angle_degrees = 8
	# At five metres, eight degrees is about 0.70m to either side.
	var left := _target(Vector3(-0.70, 0.9, -5))
	var right := _target(Vector3(0.70, 0.9, -5))
	for frame in 3: await physics_frame
	gun.headshot_chance = 0.5
	combat._headshot_rng.seed = 138
	var reference := RandomNumberGenerator.new()
	reference.seed = 138
	var expected := [0.0, 0.0, 0.0]
	for index in 3: expected[index] = (17.5 if reference.randf() < 0.5 else 7.0) * (2 if index == 0 else 1)
	hits_before = target.hit_events
	var center_damage := _shoot(1)
	check(is_equal_approx(center_damage, expected[0]) and is_equal_approx(left.damage_received, expected[1]) and is_equal_approx(right.damage_received, expected[2]), "Each actually hit target rolls once, multiplying only the pellets that hit it")
	check(target.hit_events == hits_before + 1 and left.hit_events == 1 and right.hit_events == 1, "Multi-target shotgun still calls each receiver only once")
	check(combat._headshot_rng.state == reference.state, "Exactly one random sample per actual target hit")
	gun.headshot_chance = 1
	check(is_equal_approx(_shoot(0.99), 14), "Shotgun below full precision applies no critical pellet damage")
	var wall := _target(Vector3(0, 0.9, -2))
	wall.get_child(0).shape.size.x = 0.1
	wall.remove_from_group("combat_target")
	for frame in 3: await physics_frame
	check(is_zero_approx(_shoot(1)), "Blocked pellets cannot award damage through walls")
	check(left.hit_events == 3 and right.hit_events == 3, "Unblocked side pellets still hit independently")
	wall.queue_free()
	left.queue_free()
	right.queue_free()
	for frame in 3: await physics_frame
	var points := PackedVector2Array()
	points.resize(64)
	gun.shotgun.pattern.points = points
	gun.headshot_chance = 0.5
	combat._headshot_rng.seed = 914
	reference.seed = 914
	var expected_damage: float = (17.5 if reference.randf() < 0.5 else 7.0) * 64
	hits_before = target.hit_events
	signals_before = headshots.size()
	var started := Time.get_ticks_usec()
	var damage := _shoot(1)
	print("64-pellet whole shot (including rays/effects): %d us" % (Time.get_ticks_usec() - started))
	check(is_equal_approx(damage, expected_damage) and target.hit_events == hits_before + 1 and headshots.size() == signals_before + (1 if expected_damage > 448 else 0) and combat._headshot_rng.state == reference.state, "64 pellets on one target still use one roll, one damage call and at most one feedback event")
	# Same pattern RNG seed yields the same stream whether headshots are enabled or disabled.
	combat._shotgun_rng.seed = 92
	_shoot(1)
	var state: int = combat._shotgun_rng.state
	combat._shotgun_rng.seed = 92
	gun.headshot_enabled = false
	_shoot(1)
	check(state == combat._shotgun_rng.state, "Headshots do not change the shotgun ballistic random stream")
	gun.headshot_enabled = true

func _enemy_checks() -> void:
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	enemy.weapon = gun
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(0, 0, -3)
	enemy.look_at(player.global_position)
	gun.headshot_chance = 1
	gun.headshot_damage_multiplier = 2.5
	gun.shotgun.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	gun.headshot_instant_kill_enabled = false
	gun.headshot_stagger_seconds = 0
	for frame in 3: await physics_frame
	var enemy_health: float = enemy.health
	_shoot(1)
	check(is_equal_approx(enemy_health - enemy.health, 62.5), "Real enemy health receives player headshot damage through original weapon-hit interface")
	var health = player.get_node("Health")
	health.debug_invincible = false
	for mode in [WeaponData.FireMode.SEMI_AUTO, WeaponData.FireMode.SHOTGUN]:
		gun.fire_mode = mode
		enemy.equip_weapon(gun)
		enemy.shooting_enabled = true
		enemy.aim_direction = (player.get_torso_position() - enemy.get_shot_origin()).normalized()
		enemy.aim_acquired = true
		enemy.has_aim = true
		enemy.weapon_stability = 1
		enemy.shot_cooldown = 0
		for frame in 3: await physics_frame
		var before: float = health.health
		var expected: float = 25 if mode == WeaponData.FireMode.SEMI_AUTO else 21
		check(enemy.try_fire() and is_equal_approx(before - health.health, expected), "Enemy sharing enabled weapon keeps ordinary damage in mode %d" % mode)
	enemy.queue_free()
	for frame in 3: await physics_frame

func _feedback_checks() -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 10, 6)
	camera.look_at(target.global_position)
	camera.current = true
	root.get_node("DebugSettings").enabled = false
	combat._apply_debug_mode(false)
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	combat.equip_weapon(gun)
	var reticle = combat.get_node("HUD/Reticle")
	reticle.set_process(false)
	combat.is_aiming = true
	combat.locked_target = target
	combat.accuracy = 1
	reticle._process(0)
	check(reticle.visible and reticle._headshot_ready and not combat.get_node("HUD/Panel").visible, "Full precision shows eligibility with Debug disabled")
	gun.headshot_chance = 0
	reticle._process(0)
	check(not reticle._headshot_ready, "Disabled chance hides eligibility indicator")
	gun.headshot_chance = 1
	combat.accuracy = 0.999
	reticle._process(0)
	check(not reticle._headshot_ready, "Eligibility indicator disappears below full precision")
	gun.min_spread_angle_degrees = 1
	gun.max_spread_angle_degrees = 4
	combat.accuracy = 0.5
	player.crouch_amount = 0
	reticle._process(0)
	var standing_radius: float = reticle.radius
	player.crouch_amount = 1
	reticle._process(0)
	check(reticle.radius < standing_radius and not reticle._headshot_ready and combat.accuracy == 0.5, "Crouched reticle follows smaller spread without granting headshot eligibility")
	combat.crouch_spread_reduction = 0.99
	reticle._process(0)
	check(reticle.radius == reticle.minimum_radius and not reticle._headshot_ready, "Even saturated stance reduction cannot light the headshot indicator")
	combat.crouch_spread_reduction = 0.25
	player.crouch_amount = 0
	gun.min_spread_angle_degrees = 0
	gun.max_spread_angle_degrees = 0
	target.retire_on_hit = true
	_shoot(1)
	reticle._process(0)
	check(reticle.visible and not reticle._draw_aim and reticle._headshot_markers.size() == 1, "Lethal headshot feedback survives loss of lock and target eligibility")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://logs/headshot")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/headshot/feedback.png")
	reticle.set_process(true)
	paused = true
	await create_timer(0.03, true).timeout
	check(reticle._headshot_markers.size() == 1 and is_equal_approx(reticle._headshot_markers[0].remaining, 0.65), "Pause freezes actual feedback processing")
	reticle.set_process(false)
	paused = false
	reticle._process(0.7)
	check(not reticle.visible and reticle._headshot_markers.is_empty(), "Hit feedback expires without retaining dead targets")
	target.retire_on_hit = false
	target.collision_layer = 1
	target.add_to_group("combat_target")
	for frame in 3: await physics_frame
	_shoot(1)
	combat.equip_weapon(gun)
	check(reticle._headshot_markers.is_empty(), "Switching weapons clears prior headshot feedback")
	_shoot(1)
	player.is_in_dialogue = true
	reticle._process(0)
	check(not reticle.visible and reticle._headshot_markers.is_empty(), "Dialogue clears headshot feedback")
	player.is_in_dialogue = false
	_shoot(1)
	player.get_node("Health").receive_hit(player.get_node("Health").max_health)
	reticle._process(0)
	check(not reticle.visible and reticle._headshot_markers.is_empty(), "Player death clears headshot feedback")
	reticle.set_process(true)
	camera.queue_free()

func _shoot(precision: float) -> float:
	var before := target.damage_received
	combat.is_aiming = true
	combat.accuracy = precision
	combat.shot_cooldown = 0
	combat.clear_target_lock()
	combat.shoot()
	return target.damage_received - before

func _target(at: Vector3) -> Target:
	var body := Target.new()
	body.position = at
	body.add_to_group("combat_target")
	_box(body, Vector3(0.6, 1.8, 0.6))
	world.add_child(body)
	return body

func _box(body: CollisionObject3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
