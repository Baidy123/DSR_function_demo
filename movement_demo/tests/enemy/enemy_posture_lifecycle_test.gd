extends SceneTree

const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)
func settle(count := 3) -> void:
	for index in count: await physics_frame

func _run() -> void:
	var packed = load("res://scenes/enemy/enemy.tscn")
	var order_a = packed.instantiate()
	order_a.fast_movement_noise_radius = 9.0
	order_a.movement_noise_radius = 4.5
	order_a._normalize_legacy_noise_radius()
	check(order_a.fast_noise_multiplier == 2.0 and order_a.get_movement_noise_radius(true) == 9.0, "legacy radius normalizes after base radius load")
	var order_b = packed.instantiate()
	order_b.movement_noise_radius = 4.5
	order_b.fast_movement_noise_radius = 9.0
	order_b._normalize_legacy_noise_radius()
	check(order_b.fast_noise_multiplier == order_a.fast_noise_multiplier, "legacy property load order has no effect")
	order_b.fast_noise_multiplier = 3.0
	check(order_b.get_movement_noise_radius(true) == 13.5, "new multiplier replaces old custom radius")
	order_a.free()
	order_b.free()
	for special in [false, true]:
		var source = packed.instantiate()
		source.movement_noise_radius = 0.0
		if special: source.fast_movement_noise_radius = 6.0
		else: source.fast_noise_multiplier = 2.0
		source._normalize_legacy_noise_radius()
		var saved := PackedScene.new()
		saved.pack(source)
		var path := "res://logs/enemy_posture_noise_%s.tscn" % special
		DirAccess.make_dir_recursive_absolute("res://logs")
		check(ResourceSaver.save(saved, path) == OK, "noise configuration saves")
		var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		restored._normalize_legacy_noise_radius()
		check(restored.get_movement_noise_radius(true) == (6.0 if special else 0.0), "base zero preserves legacy nonzero fast sound across reload")
		if not special:
			restored.movement_noise_radius = 3.0
			check(restored.get_movement_noise_radius(true) == 6.0, "new zero-base configuration retains its multiplier after reload")
		source.free()
		restored.free()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	var cover = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = cover.global_position
	center.y = 0.0
	player.global_position = center + Vector3.FORWARD * 4.0
	enemy.global_position = center + Vector3.BACK
	await settle(6)
	var plan := LowCover.query_vault(enemy, Vector3.FORWARD)
	check(plan.get("valid", false) and enemy.begin_vault(plan), "lifecycle test starts a physically checked vault")
	for frame in 20:
		await physics_frame
		enemy.move_character(Vector3.ZERO, 1.0 / 60.0)
		var progress: float = enemy.body_motion.progress
		enemy.move_character(Vector3.ZERO, 1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		check(enemy.body_motion.progress == progress, "each physics frame advances vault at most once")
	check(enemy.global_position.y > 1.0, "interruption occurs above the wall")
	enemy.receive_melee_hit(0.0, enemy.global_position - Vector3.RIGHT, 0.5, 0.2)
	for frame in 120:
		await physics_frame
		enemy._physics_process(1.0 / 60.0)
		if enemy.is_on_floor() and enemy.global_position.y > 0.2:
			check(enemy.is_vaulting() and not enemy.can_reload(), "wall-top contact retains attack occupation")
		if not enemy.is_vaulting(): break
	check(not enemy.is_vaulting() and enemy.global_position.y < 0.2 and enemy._hit_push_remaining <= 0.0, "hit interruption consumes push immediately and safely lands off the wall")
	enemy.global_position = center + Vector3.BACK
	enemy.body_motion.reset()
	await settle()
	plan = LowCover.query_vault(enemy, Vector3.FORWARD)
	enemy.begin_vault(plan)
	for frame in 20:
		await physics_frame
		enemy.move_character(Vector3.ZERO, 1.0 / 60.0)
	enemy.receive_hit(enemy.health + 1.0)
	for frame in 120:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if not enemy.is_vaulting(): break
	check(enemy.is_dead and not enemy.is_vaulting() and enemy.global_position.y < 0.2, "death and disabled AI preserve gravity until safe landing")
	scene.queue_free()
	await process_frame
	await _blocked_landings()
	print("ENEMY POSTURE LIFECYCLE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _blocked_landings() -> void:
	for sample in [[-1.0, false], [1.0, false], [1.0, true]]:
		var scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		var enemy = scene.get_node("Arena/Enemy")
		var ai = enemy.get_node("AI")
		var player = scene.get_node("Player")
		ai.set_physics_process(false)
		enemy.set_physics_process(false)
		player.set_physics_process(false)
		player.combat.set_physics_process(false)
		var center: Vector3 = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover").global_position
		center.y = 0.0
		player.global_position = center + Vector3(-3, 0, -3)
		enemy.global_position = center + Vector3(1.0, 0.0, sample[0])
		await settle(8)
		var plan := LowCover.query_vault(enemy, Vector3.FORWARD * sample[0])
		check(plan.get("valid", false) and enemy.begin_vault(plan), "right-end dynamic-landing fixture starts with both original endpoints clear")
		for frame in 60:
			await physics_frame
			enemy._physics_process(1.0 / 60.0)
			if enemy.body_motion.progress > 0.55: break
		ai._cancel_utility_execution(&"test_revoke")
		enemy.body_motion.interrupt()
		player.global_position = plan.exit
		var blocker: StaticBody3D
		if sample[1]:
			blocker = StaticBody3D.new()
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.7, 2.0, 0.7)
			collision.shape = shape
			blocker.add_child(collision)
			scene.add_child(blocker)
			blocker.global_position = plan.entry + Vector3.UP
		var occupied_safely := true
		for frame in 120:
			await physics_frame
			enemy._physics_process(1.0 / 60.0)
			if enemy.is_vaulting(): occupied_safely = occupied_safely and not enemy.can_reload() and not enemy.can_fire() and ai.current_action == null
			if not enemy.is_vaulting(): break
		if sample[1]:
			check(enemy.is_vaulting() and enemy.global_position.y > 0.2, "two newly occupied endpoints retain vault ownership instead of releasing on the wall")
			player.global_position = center + Vector3(-3, 0, -3)
			for frame in 180:
				await physics_frame
				enemy._physics_process(1.0 / 60.0)
				if not enemy.is_vaulting(): break
		check(not enemy.is_vaulting() and enemy.global_position.y < 0.2, "dynamic endpoint blockage recovers through a physically clear original endpoint " + str(sample))
		check(occupied_safely and ai.current_action == null, "recovery preserves attack exclusion and never revives the revoked action")
		scene.queue_free()
		await process_frame
