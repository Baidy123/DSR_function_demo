extends "res://tests/enemy/enemy_vault_navigation_test.gd"

## Independent collision/nav geometry, actual area/AI/body loops, no injected
## observations, candidates, selected actions, tasks or body vault requests.
const NativeRoute = preload("res://scripts/enemy/services/enemy_navigation_route.gd")
var actors: Array = []
var level := 0

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = int(arg.trim_prefix("--level="))
	_vault_connection_only = true
	_build_fixture()
	var arena = scene.get_node("Arena")
	arena.set_physics_process(true)
	wall.vault_enabled = true
	var squad := Node3D.new()
	squad.name = "Squad"
	squad.set_script(preload("res://scripts/world/squad_controller.gd"))
	squad.profile.level = level
	arena.add_child(squad)
	enemy.reparent(squad, true)
	actors = [enemy]
	for index in 1:
		var peer = load("res://scenes/enemy/enemy.tscn").instantiate()
		peer.name = "Follower"
		peer.position = Vector3(1.45, 0, 4.5)
		peer.get_node("NavigationAgent3D").path_height_offset = 0.0
		peer.get_node("UnitType").profile = enemy.get_node("UnitType").profile.duplicate(true)
		peer.get_node("Training").profile = enemy.get_node("Training").profile.duplicate(true)
		peer.get_node("Training").profile.selected_tactics.clear()
		peer.weapon = enemy.weapon.duplicate(true)
		squad.add_child(peer)
		actors.append(peer)
	for actor in actors:
		actor.set_physics_process(false)
		actor.get_node("AI").set_physics_process(false)
		actor.get_node("Training").profile.selected_tactics.clear()
		if OS.get_cmdline_user_args().has("--all-trained"):
			for definition in actor.get_node("UnitType").profile.tactical_actions:
				actor.get_node("Training").profile.selected_tactics.append(definition.action_id)
		actor.get_node("AI").refresh_configuration(true)
		actor.look_at(player.global_position)
	player.health.debug_invincible = true
	for frame in 100:
		await physics_frame
		for actor in actors: actor.get_node("AI").context.refresh_environment()
		if arena.vault_navigation.ready and not arena.vault_navigation.connections().is_empty(): break
	await physics_frame
	await physics_frame
	# Registry preparation does not finish the server's asynchronous map update.
	NavigationServer3D.map_force_update(ai.agent.get_navigation_map())
	# Let the normal AI entry assemble/freeze capabilities before querying them.
	for actor in actors: actor.get_node("AI")._physics_process(STEP)
	check(arena.vault_navigation.ready and not arena.vault_navigation.connections().is_empty(), "Owned static graph creates real native links")
	check(ai.context.cover_selection._path_to(START, TARGET).is_empty() and ai.agent.navigation_layers == 1, "Walk-only navigation cannot cross the disconnected wall")
	var description := {}
	for frame in 24:
		await physics_frame
		description = NativeRoute.query(ai.context, TARGET)
		if not description.is_empty(): break
	check(not description.is_empty() and description.segments.map(func(segment): return segment.kind) == [&"walk", &"vault", &"walk"], "Shared query returns typed walk/vault/walk segments")
	check(_pure(description), "Shared plan contains pure values and numeric owner identities")
	if not description.is_empty():
		var vault: Dictionary = description.segments[1]
		check(arena.cooperation.acquire_vault_transit(ai.context, vault) and not arena.cooperation.acquire_vault_transit(actors[1].get_node("AI").context, vault), "Same channel has one physical transit owner")
		arena.cooperation.release_vault_transit(ai.context)
		player.global_position = vault.exit
		enemy.global_position = vault.entry
		await physics_frame
		check(not enemy.begin_vault(NativeRoute.execution_vault(ai.context, vault)), "Player occupying actual landing prevents body execution")
		enemy.global_position = START
		player.global_position = TARGET
	for actor in actors:
		actor.velocity = Vector3.ZERO
		actor.reset_target()
		actor.get_node("AI").context.spatial.reset_evaluation()
	var saw := {}
	var landed := {}
	var owned := true
	var minimum := INF
	var costs: Array[int] = []
	var typed_command := false
	for frame in 720:
		await physics_frame
		var cost: int = arena.cooperation.last_advance_usec
		for actor in actors:
			actor._physics_process(STEP)
			var brain = actor.get_node("AI")
			brain._physics_process(STEP)
			for value in brain.frame_costs.values(): cost += int(value)
			owned = owned and brain.context.commanded() == (level > 0)
			typed_command = typed_command or brain.context.coordination_assignment().has("route_plan")
			if actor.is_vaulting(): saw[actor.name] = true
			if saw.has(actor.name) and not actor.is_vaulting() and actor.global_position.z < -0.7: landed[actor.name] = true
		minimum = minf(minimum, actors[0].global_position.distance_to(actors[1].global_position))
		costs.append(cost)
		if frame % 120 == 0: print("TRACE level=", level, " frame=", frame, " positions=", actors.map(func(actor): return actor.global_position), " actions=", actors.map(func(actor): return actor.get_node("AI").utility_current.get("id")), " tasks=", actors.map(func(actor): return actor.get_node("AI").context.coordination_assignment().get("reason")))
		if landed.size() == actors.size() and actors.all(func(actor): return actor.melee_count > 0): break
	check(owned and (level == 0 or typed_command), "Original personal/team authority owns actual typed pursuit")
	check(landed.size() == actors.size(), "Every active melee member autonomously vaults and safely lands")
	check(actors.all(func(actor): return actor.melee_count > 0), "Melee engagement continues after landing")
	check(minimum >= 0.64, "Physical character separation survives shared vault pursuit")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Original P99 <16ms / maximum <50ms budgets")
	print("NATIVE VAULT RUNTIME level=", level, " ", checks - failures, "/", checks, " p99=", costs[int(costs.size() * 0.99)], " peak=", costs[-1], " landed=", landed)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _pure(value: Variant) -> bool:
	if value is Object or value is RID: return false
	if value is Dictionary:
		for key in value:
			if not _pure(key) or not _pure(value[key]): return false
	elif value is Array:
		for item in value:
			if not _pure(item): return false
	return true
