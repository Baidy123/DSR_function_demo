extends "res://tests/enemy/enemy_melee_low_cover_test.gd"

const LowGeometry = preload("res://scripts/world/low_cover_geometry.gd")
var _nav_gap := 1.0
var _nav_height := 0.0
var _opposite_only := false
var _vault_connection_only := false

func _run() -> void:
	_build_fixture()
	wall.vault_enabled = true
	await _prepare()
	player.health.debug_invincible = true
	var region: NavigationRegion3D = ai.context.navigation_region
	var nominal := Vector3(0.0, 0.0, 0.9)
	var projected := NavigationServer3D.region_get_closest_point(region.get_rid(), nominal)
	check(is_equal_approx(ai.context._horizontal_distance_between(nominal, projected), 0.1), "fixture reproduces the saved arena's 10-cm entry-to-navigation gap")
	check(LowGeometry.query_vault_at(enemy, wall, nominal, Vector3.FORWARD).get("valid", false), "the rejected nominal entry has a genuinely clear vault arc")
	check(ai.context.cover_selection._path_to(enemy.global_position, nominal).is_empty(), "ordinary shared paths still reject the original off-navigation entry")
	var routes: Array = ai.context.routes._evaluate(TARGET)
	check(not routes.is_empty(), "planner finds a reachable nearby same-side entry without relaxing shared paths")
	if not routes.is_empty():
		var route: Dictionary = routes[0]
		check(route.vault.entry.is_equal_approx(projected) and route.before[route.before.size() - 1].distance_to(projected) <= 0.05, "route and physical vault use the same projected reachable entry")
		check(LowGeometry.query_vault_at(enemy, wall, route.vault.entry, Vector3.FORWARD, 0.8, false).get("valid", false), "adjusted entry passes the complete physical preflight again")
	check(not ai.context.cover_selection._path_to(START, TARGET).is_empty(), "connected control retains the ordinary walk around the low wall")
	await _preference_checks()
	await _prepare()
	player.health.debug_invincible = true
	# A connected arena legitimately allows the finite melee-cover charge to
	# beat a vault. Isolate navigation-entry execution using the same local gap
	# on two islands; leave every action, score and frame limit unchanged.
	_vault_connection_only = true
	await _replace_navigation()
	check(ai.context.cover_selection._path_to(START, TARGET).is_empty(), "autonomous fixture has two islands joined only by the physical vault")
	var saw_vault := false
	var landed := false
	for frame in 300:
		await _tick()
		saw_vault = saw_vault or enemy.is_vaulting()
		if saw_vault and not enemy.is_vaulting() and enemy.global_position.z < -0.7:
			landed = true
			break
	check(saw_vault and landed, "cold-cache actual Utility crosses the navigation-edge wall and safely lands")
	ai._cancel_utility_execution()
	_vault_connection_only = false
	await _replace_navigation()
	region.rotation.y = PI * 0.5
	await _synchronize_navigation()
	enemy.global_position = region.to_global(START)
	player.global_position = region.to_global(TARGET)
	enemy.look_at(player.global_position)
	ai.context.reset_memory()
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	routes = ai.context.routes._evaluate(player.global_position)
	check(not routes.is_empty(), "the same bounded entry projection works on a rotated wall and navigation region")
	region.rotation.y = 0.0
	await _synchronize_navigation()
	enemy.global_position = START
	player.global_position = TARGET
	var blocker := _box(Vector3(0.8, 2.0, 0.8), Vector3(0.0, 1.0, 1.0))
	scene.add_child(blocker)
	await physics_frame
	check(ai.context.routes._evaluate(TARGET).is_empty(), "occupied projected standing space cannot create a vault route")
	blocker.queue_free()
	await physics_frame
	_nav_gap = 1.5
	await _replace_navigation()
	check(ai.context.routes._evaluate(TARGET).is_empty(), "a distant navigation projection is rejected rather than pulling the entry across empty space")
	_nav_gap = 1.0
	_nav_height = 0.8
	await _replace_navigation()
	check(ai.context.routes._evaluate(TARGET).is_empty(), "navigation on another height cannot substitute for the entry floor")
	_nav_height = 0.0
	_opposite_only = true
	await _replace_navigation()
	projected = NavigationServer3D.region_get_closest_point(region.get_rid(), nominal)
	check(projected.z < 0.0 and ai.context.routes._evaluate(TARGET).is_empty(), "navigation solely on the opposite side never creates a walk-to-vault entry")
	check(budget_ok and ai.context.spatial.EVALUATION_POINTS_PER_FRAME == 24 and ai.context.spatial.EVALUATION_BUDGET_USEC == 2000, "entry repair keeps the existing shared spatial budget")
	print("ENEMY VAULT NAVIGATION: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _preference_checks() -> void:
	# Compare actual connected walk/vault alternatives without changing score
	# weights, physical timing, navigation or the candidate's original outcome.
	check(ai.context.setting(&"selection", &"vault_preference", 0.0) == 6.0, "existing training inherits the stronger six-point vault preference")
	ai.training.profile.selected_tactics.clear()
	ai.training.profile.set_setting(&"selection", &"vault_preference", 0.0)
	ai.refresh_configuration(true)
	player.combat.cancel_reload()
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	var options: Array[Dictionary] = []
	for frame in 32:
		await physics_frame
		options = ai.action_selector.assess_options(ai, true)
	var walks: Array = options.filter(func(pick): return pick.id == &"melee_engage" and pick.get("route", {}).is_empty())
	var vaults: Array = options.filter(func(pick): return pick.id == &"melee_engage" and not pick.get("route", {}).is_empty())
	check(not walks.is_empty() and not vaults.is_empty(), "preference control prepares genuine connected walking and vault alternatives")
	if walks.is_empty() or vaults.is_empty(): return
	var baseline: Dictionary = vaults[0].duplicate(true)
	var without_preference: Dictionary = ai.action_selector.choose_option(options)
	ai.training.profile.set_setting(&"selection", &"vault_preference", 2.0)
	options = ai.action_selector.assess_options(ai, true)
	vaults = options.filter(func(pick): return pick.id == &"melee_engage" and not pick.get("route", {}).is_empty())
	check(not vaults.is_empty(), "enabling preference preserves the same geometrically valid vault")
	if vaults.is_empty(): return
	var preferred: Dictionary = vaults[0]
	check(is_equal_approx(baseline.cost - preferred.cost, 2.0) and preferred.outcome.unavailable_seconds == baseline.outcome.unavailable_seconds and preferred.outcome.exposed_seconds == baseline.outcome.exposed_seconds and preferred.outcome.information_loss == baseline.outcome.information_loss, "two preference points change only credit, preserving real time, exposure and information costs")
	check(without_preference.get("route", {}).is_empty() and not ai.action_selector.choose_option(options).get("route", {}).is_empty(), "preference changes the ordinary winner from walking to vaulting without forcing the action")
	var saved := "res://logs/vault_preference_training.tres"
	var error := ResourceSaver.save(ai.training.profile, saved)
	var restored = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) if error == OK else null
	check(restored != null and restored.selection.vault_preference == 2.0 and restored.selection.overridden.has("vault_preference"), "training retains the adjustable vault preference across save and reload")
	ai.training.profile.set_setting(&"selection", &"vault_preference", 0.0)
	options = ai.action_selector.assess_options(ai, true)
	check(ai.action_selector.choose_option(options).get("route", {}).is_empty(), "zero preference restores the original winner without accumulating credit")
	ai.training.profile.set_setting(&"selection", &"vault_preference", 6.0)
	ai._cancel_utility_execution()
	ai.context.spatial.reset_evaluation()
	var crossed := false
	var saw_vault := false
	for frame in 300:
		await _tick()
		saw_vault = saw_vault or enemy.is_vaulting()
		if saw_vault and not enemy.is_vaulting() and enemy.global_position.z < -0.7:
			crossed = true
			break
	check(saw_vault and crossed, "cold-cache connected pursuit autonomously vaults and lands with the default preference")
	# Strong preference must still defer to the body's live character checks.
	ai._cancel_utility_execution()
	enemy.global_position = START
	enemy.velocity = Vector3.ZERO
	player.global_position = TARGET
	await physics_frame
	var routes: Array = ai.context.routes._evaluate(TARGET)
	check(not routes.is_empty(), "landing-occupancy control has a physically valid planned crossing")
	if routes.is_empty(): return
	var vault: Dictionary = routes[0].vault
	enemy.global_position = vault.entry
	player.global_position = vault.exit
	await physics_frame
	var blocked: Dictionary = LowGeometry.query_vault_at(enemy, wall, enemy.global_position, vault.exit - vault.entry, vault.duration, false)
	check(blocked.get("reason") == "landing_space" and not enemy.begin_vault(vault) and not enemy.is_vaulting(), "six preference points never permit vaulting into the player's occupied landing space")

func _replace_navigation() -> void:
	ai.context.navigation_region.navigation_mesh = _navigation_mesh()
	await _synchronize_navigation()
	ai.context.spatial.reset_evaluation()

func _synchronize_navigation() -> void:
	var region: NavigationRegion3D = ai.context.navigation_region
	var previous: int = NavigationServer3D.region_get_iteration_id(region.get_rid())
	var previous_map: int = NavigationServer3D.map_get_iteration_id(region.get_navigation_map())
	for frame in 24:
		await physics_frame
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) != previous and NavigationServer3D.map_get_iteration_id(region.get_navigation_map()) != previous_map: return

func _navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	var xs := [-8.0, -2.5, 2.5, 8.0]
	var zs := [-8.0, -_nav_gap, _nav_gap, 8.0]
	var vertices := PackedVector3Array()
	for z in zs:
		for x in xs: vertices.append(Vector3(x, _nav_height, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if (x == 1 and z == 1) or (_opposite_only and z != 0) or (_vault_connection_only and z == 1): continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh
