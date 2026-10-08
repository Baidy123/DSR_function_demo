extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(enemy)
	Fixture.set_training_action(ai, &"attack_position", true)
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	ai.refresh_configuration()
	player.health.debug_invincible = true
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = wall.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3.BACK * 1.1
	player.global_position = center + Vector3.FORWARD * 4.0
	enemy.look_at(player.global_position)
	for frame in 8: await physics_frame
	ai.reset_actions()
	ai.context.reset_memory()
	var selected := false
	var hid := false
	var rose := false
	var returned := false
	var round_shots := 0
	var exposed_shots_only := true
	for frame in 480:
		await physics_frame
		var before: int = enemy.shot_count
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		var cycle = ai.actions[&"cover"].low_cycle
		selected = selected or ai.utility_current.get("mode") == &"low_cover_burst"
		if selected and enemy.is_crouching() and round_shots == 0: hid = true
		if hid and enemy.get_body_height() > 1.74: rose = true
		if enemy.shot_count > before and ai.utility_current.get("mode") == &"low_cover_burst":
			round_shots += enemy.shot_count - before
			exposed_shots_only = exposed_shots_only and enemy.get_body_height() > 1.74 and enemy.last_shot_collider == player
		if round_shots >= 3 and enemy.is_crouching():
			returned = true
			break
	check(selected, "unwarmed autonomous Utility chooses a nearby low-cover burst over ordinary open movement and corner positions")
	check(hid and rose and round_shots >= 3 and returned, "selected low-cover sequence crouches rises fires one existing burst and crouches back")
	check(exposed_shots_only, "all cover-cycle shots use standing posture and a real clear muzzle lane")
	print("LOW COVER CYCLE shots=", round_shots, " hidden=", hid, " rose=", rose, " returned=", returned)
	# Zero preference only removes the transparent credit, not the legal option.
	ai.reset_actions()
	enemy.request_crouch(false)
	enemy._physics_process(0.3)
	for frame in 3: await physics_frame
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	var cover_action = ai.actions[&"cover"]
	var destination := {"body": wall, "hide": enemy.global_position, "crouch": true, "path": ai.context.routes.planning_path(enemy.global_position, enemy.global_position)}
	var route: Dictionary = ai.context.spatial.assess_cover_route(destination.path, player.global_position, 2.0, 0.0)
	ai.training.profile.set_setting(&"cover", &"low_cover_preference", 0.0)
	var plain: Dictionary = cover_action._low_cover_option(destination, route, player.global_position, true)
	ai.training.profile.set_setting(&"cover", &"low_cover_preference", 8.0)
	var preferred: Dictionary = cover_action._low_cover_option(destination, route, player.global_position, true)
	check(not plain.is_empty() and not preferred.is_empty() and plain.outcome.preference_credit == 0.0 and preferred.outcome.preference_credit == 8.0 and plain.outcome.unavailable_seconds == preferred.outcome.unavailable_seconds and plain.outcome.exposed_seconds == preferred.outcome.exposed_seconds, "disabling preference retains the candidate and its actual fire and exposure estimates")
	var scored: Dictionary = ai.action_selector.score_outcome(ai.context, preferred.outcome.unavailable_seconds, preferred.outcome.exposed_seconds, preferred.outcome.information_loss, preferred.outcome.preference_credit)
	check(ai.action_selector.choose_option([{"id": &"cover", "cost": scored.cost}, {"id": &"better", "cost": scored.cost - 0.1}]).id == &"better", "another genuinely lower-cost option can beat nearby low-cover preference")
	var saved := "user://low_cover_behavior_training.tres"
	var saved_ok := ResourceSaver.save(ai.training.profile, saved) == OK
	var loaded = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) if saved_ok else null
	check(loaded != null and loaded.setting(&"cover", &"low_cover_preference", -1.0) == 8.0 and loaded.setting(&"cover", &"low_cover_hide_seconds", -1.0) == 0.6, "low-cover preference and crouch timing survive resource save and reload")
	ai._start_utility_option(preferred, true)
	for frame in 120:
		await physics_frame
		var output: Dictionary = cover_action.execute_tick(1.0 / 60.0, ai.perception.can_see_player())
		enemy.request_crouch(output.get("crouch", false))
		enemy.move_character(output.direction, 1.0 / 60.0, output.multiplier)
		enemy._physics_process(1.0 / 60.0)
		if cover_action.low_cycle.phase == cover_action.low_cycle.Phase.RISE: break
	check(cover_action.low_cycle.phase == cover_action.low_cycle.Phase.RISE, "equipment cancellation fixture reaches an actual crouch-to-rise transition")
	var weapon: WeaponData = enemy.weapon
	enemy.equip_weapon(null)
	var cancelled_output: Dictionary = cover_action.execute_tick(1.0 / 60.0, true)
	check(cancelled_output.fire.is_empty() and not cover_action.valid(true) and cover_action.can_interrupt({}, true), "unequipping during rise removes fire intent and releases the committed cycle safely")
	ai._cancel_utility_execution(&"configuration")
	check(not cover_action.low_cycle.active() and not cover_action.transfer.is_active() and cover_action.route_motion.route.is_empty() and ai.context.fire.request.is_empty(), "cancellation removes all cycle movement posture and attack ownership")
	enemy.equip_weapon(weapon)
	enemy.global_position = center + Vector3.BACK
	enemy.velocity = Vector3.ZERO
	player.global_position = center + Vector3.FORWARD * 0.66
	player.request_crouch(true)
	player._update_posture(0.3)
	enemy.request_crouch(false)
	enemy._physics_process(0.3)
	for frame in 4: await physics_frame
	ai.context.reset_memory()
	var captured := Vector3.INF
	var event_id := -1
	var never_visual := true
	for frame in 45:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if event_id < 0 and not ai.context.exact_cover_clue.is_empty():
			captured = ai.context.exact_cover_clue.position
			event_id = ai.context.exact_cover_clue.id
			never_visual = not ai.context.has_visual_memory and not ai.context.sees_player
			break
	check(event_id >= 0 and captured.is_equal_approx(player.global_position), "ordinary AI receives an exact low-wall clue while the close crouching player has never been visible")
	check(never_visual, "autonomous close clue does not invent visual contact")
	check(ai.context.is_alerted and ai.context.last_known_position.is_equal_approx(captured), "exact contact reaches shared knowledge and alerts the ordinary action selector")
	var search = ai.actions[&"search"]
	search._running = true
	search.route_motion.route = {"destination": center + Vector3.RIGHT * 5.0}
	search.plan = {"route": search.route_motion.route}
	ai.context.receive_exact_cover_clue(captured, wall)
	check(search.route_motion.route.is_empty() and not search.plan.has("route") and search._exact_search_origin.is_equal_approx(captured), "a new exact clue supersedes the old search route without restoring old last-seen coordinates")
	# Reproduce real blind spots at the wall end. The capsule still overlaps the
	# wall span even though its center is a little beyond the 1.5m half-length.
	var edges := [[1.55, 0.7, 1.0], [1.55, 1.0, 1.0], [1.55, 1.3, 1.0], [1.55, 1.3, 1.3], [1.7, 0.7, 1.0], [1.7, 1.0, 1.0]]
	for sample in edges:
		enemy.global_position = center + Vector3(sample[0], 0.0, sample[2])
		player.global_position = center + Vector3(sample[1], 0.0, -0.66)
		enemy.look_at(player.global_position)
		await physics_frame
		await process_frame
		ai.context.reset_memory()
		ai.context.update_evidence(0.1, ai.perception.can_see_player())
		check(not ai.context.sees_player and not ai.context.exact_cover_clue.is_empty() and ai.context.exact_cover_clue.position.is_equal_approx(player.global_position), "wall-end body overlap publishes a frozen exact clue at " + str(sample))
	enemy.global_position = center + Vector3(1.9, 0.0, 1.0)
	player.global_position = center + Vector3(1.3, 0.0, -0.66)
	await physics_frame
	check(LowCover.proximity_cover(enemy, player).is_empty(), "a body wholly outside the wall span gains no wall-end contact privilege")
	var original: Transform3D = wall.global_transform
	wall.rotation.y += 0.35
	wall.scale = Vector3(1.3, 1.0, 0.8)
	enemy.global_position = wall.to_global(Vector3(1.5 + 0.05 / 1.3, -0.55, 1.0 / 0.8))
	player.global_position = wall.to_global(Vector3(1.3, -0.55, -0.66 / 0.8))
	await physics_frame
	await process_frame
	check(not LowCover.proximity_cover(enemy, player).is_empty(), "wall-end contact uses physical radius under rotated nonuniform wall scaling")
	wall.global_transform = original
	scene.queue_free()
	await process_frame
	await _real_configuration_starts()
	await _live_attack_start()
	print("ENEMY LOW COVER BEHAVIOR: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _real_configuration_starts() -> void:
	# Keep saved weapon, burst cadence, aim settings and all learned alternatives.
	# These starts previously stayed in open engage despite a nearby legal wall.
	for offset: Vector3 in [Vector3(0, 0, 1.1), Vector3(0, 0, 2.5), Vector3(1.8, 0, 1.5), Vector3(2.5, 0, 1.5)]:
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
		player.health.debug_invincible = true
		Fixture.set_training_action(ai, &"cover", true)
		var wall = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
		var center: Vector3 = wall.global_position
		center.y = 0.0
		enemy.global_position = center + offset
		player.global_position = center + Vector3.FORWARD * 4.0
		enemy.look_at(player.global_position)
		for frame in 8: await physics_frame
		ai.reset_actions()
		ai.context.reset_memory()
		var selected := false
		var crouched := false
		var returned := false
		var shots := 0
		var legal_standing_shots := true
		for frame in 540:
			await physics_frame
			var before: int = enemy.shot_count
			ai._physics_process(1.0 / 60.0)
			enemy._physics_process(1.0 / 60.0)
			var in_cover: bool = ai.utility_current.get("mode") == &"low_cover_burst"
			selected = selected or in_cover
			if in_cover and enemy.is_crouching(): crouched = true
			if in_cover and enemy.shot_count > before:
				shots += enemy.shot_count - before
				legal_standing_shots = legal_standing_shots and not enemy.is_crouching() and ai.context.sees_player and ai.context.fire.has_clear_firing_lane(enemy.get_muzzle_position(), enemy.aim_direction, enemy.get_muzzle_position().distance_to(player.get_eye_position()))
			if crouched and shots > 0 and enemy.is_crouching():
				returned = true
				break
		check(selected, "saved firearm and training choose nearby low cover from cold start " + str(offset))
		check(crouched and shots > 0 and returned, "saved cadence completes crouch rise actual burst and return from " + str(offset))
		check(shots > 0 and legal_standing_shots, "saved spread and real muzzle lane remain enforced from " + str(offset))
		print("REAL COVER START ", offset, " shots=", shots, " burst=", ai.context.fire.burst_shot_count, " interval=", enemy.weapon.shot_interval)
		scene.queue_free()
		await process_frame

func _live_attack_start() -> void:
	# Exact live-game positions where collection accepted a head lane but the
	# former begin/recheck path rejected the wall-blocked torso every frame.
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
	player.health.debug_invincible = true
	Fixture.set_training_action(ai, &"attack_position", true)
	enemy.global_position = Vector3(21.57337, 0.0, 7.07355)
	player.global_position = Vector3(19.28211, 0.000802, 5.181592)
	enemy.look_at(player.global_position)
	for frame in 8: await physics_frame
	ai.reset_actions()
	ai.context.reset_memory()
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var point := Vector3(21.77692, 0.0, 7.05)
	var action = ai.actions[&"attack_position"]
	var assessed: Dictionary = action.evaluate_point({"position": point, "body": wall})
	var torso: Vector3 = ai.context.known_target_point(player.global_position)
	var old_geometry: Dictionary = ai.cover_selection.assess_attack_point(point, wall, torso, torso)
	check(ai.context.sees_player and not old_geometry.clear_shot and not assessed.is_empty(), "live standby fixture has a blocked torso and a legal known head/shoulder candidate")
	if assessed.is_empty():
		scene.queue_free()
		await process_frame
		return
	var candidate: Dictionary = action.option(assessed.destination, assessed.unavailable, assessed.exposed)
	var null_frames := 0
	var began := false
	var start: Vector3 = enemy.global_position
	var shots_before: int = enemy.shot_count
	var legal_shots := true
	for frame in 240:
		await physics_frame
		if ai.current_action == null: ai._start_utility_option(candidate, true)
		began = began or (ai.current_action == action and action.is_active())
		if ai.current_action == null:
			null_frames += 1
			continue
		var before: int = enemy.shot_count
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if enemy.shot_count > before:
			legal_shots = legal_shots and ai.context.sees_player and ai.context.fire.has_clear_firing_lane(enemy.get_muzzle_position(), enemy.aim_direction, enemy.get_muzzle_position().distance_to(player.get_eye_position()))
		if enemy.shot_count > shots_before: break
	check(began and null_frames == 0, "live candidate passes begin and execution without repeated null-action standby")
	check(enemy.global_position.distance_to(start) > 0.02 and enemy.shot_count > shots_before, "live attack position advances and fires through the normal AI execution path")
	check(enemy.shot_count > shots_before and legal_shots, "recovered live-position shots still require actual perception and muzzle clearance")
	print("LIVE STANDBY REGRESSION null_frames=", null_frames, " shots=", enemy.shot_count - shots_before)
	scene.queue_free()
	await process_frame
