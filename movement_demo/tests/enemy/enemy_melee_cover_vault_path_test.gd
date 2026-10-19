extends "res://tests/enemy/enemy_melee_low_cover_test.gd"

const Contact = preload("res://scripts/enemy/services/enemy_melee_approach.gd")
var _disconnected := true

func _run() -> void:
	_build_fixture()
	wall.vault_enabled = true
	await _prepare()
	player.health.debug_invincible = true
	enemy.global_position = Vector3(0.0, 0.0, 1.05)
	await physics_frame
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	check(ai.context.environment_ready() and ai.perception.can_see_player(), "two-island fixture has real navigation and visible standing target")
	check(ai.context.cover_selection._path_to(enemy.global_position, TARGET).is_empty(), "the two navigation islands have no ordinary walking connection")
	# Prepare genuine one-vault geometry through the existing queue, without
	# injecting a path or pretending that the gap is an ordinary walk segment.
	ai.context.routes.alternatives(TARGET)
	ai.context.routes.advance_one()
	var connected: PackedVector3Array = Contact.contact_path(ai.context)
	check(not connected.is_empty() and not ai.context.routes.alternatives(TARGET).is_empty(), "a real cached vault connection supplies the planning-only contact path")
	if connected.is_empty():
		await _finish()
		return
	var endpoint: Vector3 = connected[connected.size() - 1]
	check(ai.context.cover_selection._path_to(enemy.global_position, endpoint).is_empty(), "the actual shortened contact endpoint still requires a vault")
	var action = ai.actions[&"melee_cover"]
	var destination := {"hide": enemy.global_position, "stand": enemy.global_position, "exit": enemy.global_position, "body": wall, "crouch": true}
	_prime_charge(action, destination)
	check(action.collect_candidates(true).is_empty(), "low-wall charge cannot score a planning-only vault connection as fast walking")
	check(not action.valid(true), "running low-wall charge is invalid when its actual contact endpoint is not walkable")
	var output: Dictionary = action.tick(STEP, true)
	check(not output.running and output.direction.is_zero_approx(), "charge exits without submitting ordinary navigation through the gap")
	action.cancel(&"test_cleanup")
	# The normal melee action is still authorized to expand a real vault route.
	var engage = ai.actions[&"melee_engage"]
	var direct: Array[Dictionary] = engage.collect_candidates(true)
	engage.expand_route_candidates(direct)
	for job in 4:
		if not ai.context.routes.has_pending(): break
		ai.context.routes.advance_one()
	var expanded: Array[Dictionary] = engage.expand_route_candidates(engage.collect_candidates(true))
	check(expanded.any(func(option): return not option.get("route", {}).is_empty()), "rejecting charge preserves the original melee action's explicit vault candidate")
	# Independent cold-cache full-AI execution: no forced action or disabled
	# competing behavior. This is distinct from the phase-boundary checks above.
	await _prepare()
	player.health.debug_invincible = true
	var saw_vault := false
	var landed := false
	for frame in 360:
		await _tick()
		saw_vault = saw_vault or enemy.is_vaulting()
		if saw_vault and not enemy.is_vaulting() and enemy.global_position.z < -0.7:
			landed = true
			break
	check(saw_vault and landed, "ordinary cold-cache Utility still chooses and completes the real cross-island vault")
	ai._cancel_utility_execution()
	# Restore the connected perimeter; the same low-wall charge must retain
	# its existing finite fast approach when a real walking route is available.
	_disconnected = false
	var region: NavigationRegion3D = ai.context.navigation_region
	var iteration: int = NavigationServer3D.region_get_iteration_id(region.get_rid())
	var map_iteration: int = NavigationServer3D.map_get_iteration_id(region.get_navigation_map())
	region.navigation_mesh = _navigation_mesh()
	for frame in 24:
		await physics_frame
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) != iteration and NavigationServer3D.map_get_iteration_id(region.get_navigation_map()) != map_iteration: break
	await _prepare()
	enemy.global_position = Vector3(0.0, 0.0, 1.05)
	await physics_frame
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	action = ai.actions[&"melee_cover"]
	destination.hide = enemy.global_position
	destination.stand = enemy.global_position
	destination.exit = enemy.global_position
	_prime_charge(action, destination)
	check(not ai.context.cover_selection._path_to(enemy.global_position, TARGET).is_empty(), "connected control has a genuine walk around the low wall")
	check(not action.collect_candidates(true).is_empty() and action.valid(true), "real low-wall walking charge remains eligible with its original finite speed")
	output = action.tick(STEP, true)
	check(output.running and is_equal_approx(float(output.multiplier), action._exit_speed()), "walkable charge still executes the original movement multiplier")
	var before: Vector3 = enemy.global_position
	for frame in 24:
		await physics_frame
		output = action.tick(STEP, true)
		if not output.running: break
		enemy.move_character(output.direction, STEP, output.multiplier)
	check(enemy.global_position.distance_to(before) > 0.2, "walkable charge produces real collision movement around the wall")
	action.cancel(&"test_cleanup")
	# A player just beyond the navigation edge can still be reached from an
	# ordinary near-side contact point. Do not reject by last-known feet alone.
	enemy.global_position = START
	enemy.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 0.7)
	enemy.look_at(player.global_position)
	await physics_frame
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	destination.hide = enemy.global_position
	_prime_charge(action, destination)
	check(ai.context.cover_selection._path_to(enemy.global_position, player.global_position).is_empty() and not Contact.contact_path(ai.context).is_empty(), "off-navigation player still has a genuine reachable near-side contact point")
	check(not action.collect_candidates(true).is_empty() and action.valid(true), "charge validates the reachable contact point instead of rejecting the player's off-navigation feet")
	action.cancel(&"test_cleanup")
	check(budget_ok and ai.context.spatial.EVALUATION_POINTS_PER_FRAME == 24 and ai.context.spatial.EVALUATION_BUDGET_USEC == 2000, "the route validity fix preserves the original shared spatial budget")
	await _finish()

func _prime_charge(action, destination: Dictionary) -> void:
	# Isolate the already-selected, standing charge phase. The test checks its
	# actual candidate/valid/tick protocol; the separate loop above checks AI choice.
	action.begin(action.option(destination, 0.0, 0.0, 0.0, &"advance"), true)
	action.transfer.reset()
	action._charge_remaining = action._charge_seconds()

func _navigation_mesh() -> NavigationMesh:
	var mesh := super._navigation_mesh()
	if not _disconnected: return mesh
	mesh.clear_polygons()
	for z in [0, 2]:
		for x in 3:
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh

func _finish() -> void:
	print("MELEE COVER VAULT PATH: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
