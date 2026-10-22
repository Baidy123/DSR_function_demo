extends "res://tests/enemy/enemy_team_tactical_board_test.gd"

const Squad = preload("res://scripts/world/squad_controller.gd")
const Settings = preload("res://scripts/enemy/config/cooperation_settings.gd")

func _run() -> void:
	await _setup()
	_tactical_setup()
	var shared := Settings.new()
	shared.level = Settings.Level.COORDINATED
	var first := Node3D.new()
	first.set_script(Squad)
	first.name = "FirstSquad"
	first.position = Vector3(1, 0, 2)
	first.profile = shared
	first.communication_group = &"shared"
	var second := Node3D.new()
	second.set_script(Squad)
	second.name = "SecondSquad"
	second.position = Vector3(-2, 0, 1)
	second.profile = shared
	second.communication_group = &"shared"
	arena.add_child(first)
	arena.add_child(second)
	var container := Node3D.new()
	first.add_child(container)
	var memory_point := _point(2, 2)
	contexts[0].last_seen_position = memory_point
	contexts[0].is_alerted = true
	actors[0].health = 65.0
	actors[0].ammo.magazine_rounds = 2
	var training = actors[0].get_node("Training").profile
	var spawn: Vector3 = contexts[0]._spawn_position
	var spawn_transform: Transform3D = actors[0].get_parent().global_transform * actors[0].initial_transform
	actors[0].reparent(container)
	actors[1].reparent(first)
	actors[2].reparent(second)
	for frame in 3: await physics_frame
	check(contexts[0].last_seen_position == memory_point and contexts[0].is_alerted, "Same-area reparent preserves personal perception memory")
	check(actors[0].health == 65.0 and actors[0].ammo.magazine_rounds == 2 and actors[0].get_node("Training").profile == training, "Squad membership preserves health, ammunition and personal Training")
	check(contexts[0]._spawn_position == spawn, "Same-area reparent preserves the original spawn point")
	check((actors[0].get_parent().global_transform * actors[0].initial_transform).is_equal_approx(spawn_transform), "Transformed squad containers preserve the body's reset transform in world space")
	check(contexts[0].squad_node == first and contexts[1].squad_node == first and contexts[2].squad_node == second, "Nearest explicit squad is found through ordinary containers")
	check(first.team_id != second.team_id and first.coordinator != second.coordinator, "Same faction, radio and profile never merge explicit squad identity or state")
	check(contexts[0].cooperation_member_count() == 2 and contexts[2].cooperation_member_count() == 1, "Cooperation eligibility counts only this squad")
	check(board._binding_coordinators.values().all(func(coordinator): return coordinator.registered_member_count() == 0), "Explicit members are not registered in a second coordinator through old binding resources")
	check(contexts[0].tactical_map == contexts[2].tactical_map, "Different squads share exactly one area tactical map")
	check(board.can_share_intel(actors[0].get_instance_id(), actors[2].get_instance_id()) and not board.can_cooperate(actors[0].get_instance_id(), actors[2].get_instance_id()), "Cross-squad radio sharing does not grant task authority")
	var single_choice := {"id": &"search", "destination": {"position": _point(0, 4)}}
	var single_choices: Array[Dictionary] = [single_choice]
	var choices: Array = contexts[2].coordination_choices(single_choices)
	check(choices.size() == 1 and not choices[0].get("coordination_offer", {}).is_empty(), "A solo squad still publishes regional physical reservation offers")
	if not choices.is_empty():
		var transaction: Dictionary = contexts[2].prepare_coordination_choice(choices[0])
		check(transaction.get("required", false) and not transaction.get("token", {}).is_empty(), "A solo squad acquires its public movement lease before execution")
		contexts[2].rollback_coordination_choice(transaction)
	check(actors[0].communication_group == &"tactical_test" and board.member_group(actors[0]) == &"shared", "Squad identity is inherited without overwriting serialized member settings")
	var foreign_task: Dictionary = first.coordinator.prepare_assignment(contexts[2], {"owner_action": &"search"}, "foreign")
	check(foreign_task.is_empty(), "A coordinator rejects task acceptance from another squad's member")
	board.publish_status(contexts[1], {"position": actors[1].global_position, "target_id": contexts[1].cooperation_target_id(), "ready": true, "support_seconds": 3.0})
	board.publish_status(contexts[2], {"position": actors[2].global_position, "target_id": contexts[2].cooperation_target_id(), "reloading": true})
	check(first.coordinator.reload_opportunity(contexts[0]).allowed, "Another squad's reload does not veto this squad's supported reload opportunity")
	for context in contexts:
		context.is_alerted = true
		context.sees_player = false
		_versions(context)
		board.publish_personal_baseline(context, {"cost": 10.0, "horizon": 4.0, "unavailable_seconds": 0.0, "exposed_seconds": 0.0, "information_loss": 1.0})
	var source := _source(contexts[0])
	_pair(source)
	var job: Dictionary = board.assignment(contexts[0])
	check(not job.is_empty() and first.coordinator._coordination_plans.size() == 1 and second.coordinator._coordination_plans.is_empty(), "Actual inspection plan is owned only by its squad")
	check(board.assignment(contexts[2]).is_empty() and board.coordination_source(contexts[2], contexts[2].cooperation_target_id()).is_empty(), "Another squad cannot read the first squad's plan or planning frame")
	var token: Dictionary = board.prepare_reservation(contexts[2], _offer(contexts[2], _point(0, 3), "cross-squad-position"))
	check(not token.is_empty() and not board.reservation_offer_available(contexts[0], _offer(contexts[0], _point(0, 3), "same-location")), "Public physical reservations reject cross-squad destination collisions")
	var public_occupancy: Array = first.coordinator._coordination_occupancy(contexts[0])
	var foreign_id: int = actors[2].get_instance_id()
	check(public_occupancy.any(func(value): return value.actor_id == foreign_id and value.kind == &"body") and public_occupancy.any(func(value): return value.actor_id == foreign_id and value.kind == &"reservation" and value.path_summary.has("body_radius")), "Squad planner occupancy includes another squad's real body and regional reservation")
	board.release_reservation(contexts[2], token)
	var id_before: Dictionary = board.coordination_identity(contexts[0])
	actors[0].reparent(second)
	for frame in 3: await physics_frame
	_versions(contexts[0])
	var id_after: Dictionary = board.coordination_identity(contexts[0])
	check(id_after.team_id == second.team_id and id_after.member_generation != id_before.member_generation, "Same-area squad transfer changes membership generation")
	check(board.prepare_assignment(contexts[0], job, "left").is_empty(), "Old-squad assignment cannot be revived after transfer")
	check((actors[0].get_parent().global_transform * actors[0].initial_transform).is_equal_approx(spawn_transform), "Changing squads again does not move the original body spawn")
	check(contexts[0].cooperation_member_count() == 2 and contexts[1].cooperation_member_count() == 1, "Both rosters update after transfer")
	var previous_configuration: int = first.coordinator.configuration_revision
	first.profile = shared.duplicate(true)
	board.refresh_squads()
	check(first.coordinator.configuration_revision > previous_configuration, "Replacing a profile resource invalidates its version even when its values are equal")
	first.profile = shared
	board.refresh_squads()
	shared.level = Settings.Level.INTEL_ONLY
	board.refresh_squads()
	check(contexts.all(func(context): return context.cooperation_level() == 0), "Editing a shared template updates both squads' permission")
	check(first.coordinator._coordination_plans.is_empty() and second.coordinator._coordination_plans.is_empty(), "Lowering permission invalidates every affected squad's old plans")
	first.profile = null
	board.refresh_squads()
	check(contexts[1].cooperation_level() == 0 and not contexts[1].team_cooperation_abilities().diagnostic.is_empty(), "Missing explicit profile has a diagnostic and does not borrow the legacy binding")
	second.communication_group = &"other_radio"
	board.refresh_squads()
	check(not board.can_share_intel(actors[1].get_instance_id(), actors[0].get_instance_id()) and board.can_share_space(actors[1].get_instance_id(), actors[0].get_instance_id()), "Radio change revokes intelligence while retaining friendly physical safety")
	board.publish_status(contexts[0], {"position": _point(0, 0)})
	var origin := _point(-2, 0) + Vector3.UP
	var endpoint := _point(2, 0) + Vector3.UP
	check(not board.line_safe(contexts[1], origin, endpoint), "Execution gun-line safety includes a friendly body on another radio channel")
	contexts[1].begin_cooperation_preview()
	check(not contexts[1].cooperation_line_safe(origin, endpoint), "Candidate preview preserves the same cross-radio physical safety")
	contexts[1].end_cooperation_preview()
	var nested := Node3D.new()
	nested.set_script(Squad)
	first.add_child(nested)
	actors[1].reparent(nested)
	for frame in 3: await physics_frame
	check(contexts[1].squad_node == nested and first.coordinator.registered_member_count() == 0, "An outer squad never double-registers a nested squad member")
	check(nested.profile != second.profile and nested.profile.level == 0, "A new squad starts with an independent intel-only profile")
	var plain_container := Node.new()
	nested.add_child(plain_container)
	actors[1].reparent(plain_container)
	for frame in 3: await physics_frame
	var original_spawn: Vector3 = contexts[1]._spawn_position
	actors[1].reset_target()
	check(actors[1].global_position.is_equal_approx(original_spawn) and contexts[1].squad_node == nested, "Reset through a plain Node container preserves both the original world spawn and squad membership")
	var other_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(other_scene)
	var other_area = other_scene.get_node("Arena")
	for actor in preload("res://tests/enemy/enemy_fire_fixture.gd").members(other_area): actor.get_node("AI").set_physics_process(false)
	second.reparent(other_area)
	for frame in 3: await physics_frame
	check(contexts[0].arena == other_area and contexts[0].cooperation == other_area.cooperation and second.coordinator.environment == other_area.cooperation, "Moving a whole squad across areas rebinds the node, service and member environment")
	check(not board._members.has(actors[0].get_instance_id()) and not board._squads.has(second.get_instance_id()), "The old area retains neither the transferred member nor its squad")
	actors[0].is_dead = true
	other_area.cooperation.advance(0.0)
	check(not other_area.cooperation._members.has(actors[0].get_instance_id()), "Death unregisters a transferred member from its current area")
	second.queue_free()
	for frame in 2: await physics_frame
	check(other_area.cooperation._squads.size() == 1, "Freeing the transferred squad removes its registration without affecting the saved squad")
	other_scene.queue_free()
	await process_frame
	board.reset()
	check(board.coordination_debug_snapshot(&"_coordination_plans").is_empty() and board.reservation_snapshot(contexts[1]).is_empty(), "Area reset clears all squad plans and public leases")
	print("SQUAD NODE: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)
