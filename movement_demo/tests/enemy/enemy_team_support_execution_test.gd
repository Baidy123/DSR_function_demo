extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

func _run() -> void:
	var reload_case: Dictionary = await _support_case(&"reload")
	check(reload_case.roles.has(&"assisted_reload") and reload_case.proactive and reload_case.filled, "Normal strong AI schedules, starts and completes a real nonempty reload")
	check(reload_case.reload_shots > 0 and not reload_case.unsafe_start and not reload_case.double_proactive, "Scheduled reload begins with actual support and overlaps real allied shots")
	var advance: Dictionary = await _support_case(&"advance")
	check(advance.linked_movement > 1.0 and advance.advance_shots > 0, "An assigned maneuver physically advances while its designated provider fires")
	var empty: Dictionary = await _support_case(&"empty")
	check(empty.all_empty_started and empty.filled, "Every empty member can actually reload without a fictitious provider")
	var handoff: Dictionary = await _support_case(&"handoff")
	check(handoff.handoffs > 0 and handoff.completed_handoffs > 0 and not handoff.premature_handoff, "A low-ammo change causes normal AI to establish real replacement fire before handing over")
	var trained: Dictionary = await _support_case(&"trained_support")
	check(trained.suppression_shots > 0, "An individually trained suppression action can execute assigned support with real shots")
	check(trained.proactive and trained.transfer_plan_filled and trained.transfer_plan_shots > 0 and not trained.transfer_plan_aborted and not trained.unsafe_start, "The same suppression plan establishes actual fire before and during its partner's completed reload")
	check(trained.get("damage_received", false) and trained.get("damage_preserved", false), "An actual hit cannot discard accepted suppression support before comparing executable self-preservation")
	var retreat: Dictionary = await _support_case(&"retreat")
	check(retreat.roles.has(&"assisted_retreat") and retreat.retreat_movement > 0.5 and retreat.retreat_shots > 0 and retreat.retreat_arrived, "A planned retreat reaches real cover under assigned allied fire")
	var transfer: Dictionary = await _support_case(&"transfer")
	check(transfer.front_transfer_movement > 0.5 and transfer.waited_for_transfer and transfer.proactive and transfer.filled and not transfer.unsafe_start, "A hidden provider physically reaches its firing position before the dependent reload starts")
	check(transfer.transfer_plan_filled and transfer.transfer_plan_shots > 0 and not transfer.transfer_plan_aborted, "The same hidden-provider plan reaches real fire and completes its dependent reload without restarting")
	var unavailable: Dictionary = await _support_case(&"handoff_unavailable")
	check(unavailable.failed_handoff_seconds >= 0.0 and unavailable.failed_handoff_seconds <= 2.35, "Without a spare, an actual low-ammo provider releases the dependency within the fixed recovery window")
	check(reload_case.fixed and advance.fixed and empty.fixed and handoff.fixed and trained.fixed and retreat.fixed and transfer.fixed and unavailable.fixed, "Support preparation, execution and handoff preserve fixed plan deadlines")
	print("TEAM SUPPORT EXECUTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _support_case(kind: StringName) -> Dictionary:
	var f: Dictionary = await _fixture(2 if kind in [&"transfer", &"retreat", &"handoff_unavailable", &"trained_support"] else 3, false)
	var squad = preload("res://tests/enemy/enemy_fire_fixture.gd").attach_squad(f.arena, f.actors, 0 if kind == &"trained_support" else 2)
	await physics_frame
	f.arena.enemy_environment()
	if kind in [&"retreat", &"transfer"]: _retreat_cover(f, kind)
	if kind == &"retreat": f.player.global_position = Vector3(20, f.ground_y, -1)
	for index in f.actors.size():
		var actor = f.actors[index]
		var ai = actor.get_node("AI")
		ai.reset_actions()
		actor.weapon.magazine_capacity = 40
		actor.weapon.reload_seconds = 1.2
		actor.weapon.shot_interval = 0.35
		actor.ammo.magazine_rounds = 0 if kind == &"empty" else (6 if kind in [&"reload", &"transfer", &"trained_support"] and index == 0 else 40)
		ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 12)
		ai.training.profile.set_setting(&"tactics", &"support_burst_shot_count", 12)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 0.4)
		if kind == &"trained_support" and index == 1:
			ai.training.profile.set_setting(&"suppression", &"duration_min", 4.0)
			ai.training.profile.set_setting(&"suppression", &"duration_max", 4.0)
		ai.refresh_configuration(true)
		if kind == &"retreat" and index == 0:
			actor.health = actor.max_health * 0.15
			actor.global_position = Vector3(25.4, f.ground_y, -1)
			actor.look_at(f.player.global_position)
		elif kind == &"retreat":
			actor.global_position = Vector3(23, f.ground_y, -4)
			actor.look_at(f.player.global_position)
		if kind == &"handoff":
			actor.global_position = Vector3(27, f.ground_y, (index - 1) * 4)
			actor.look_at(f.player.global_position)
		if kind == &"transfer" and index == 1:
			# Start inside the real occluded sector.
			actor.global_position = Vector3(27.4, f.ground_y, 3.5)
			actor.look_at(f.player.global_position)
	if kind in [&"retreat", &"transfer"]:
		# Install the fixture's changed mesh before any plan captures its version.
		# A pending navigation sync correctly invalidates an accepted plan; it is
		# not part of this static-wall transfer scenario.
		var navigation_map: RID = f.actors[0].agent.get_navigation_map()
		NavigationServer3D.map_force_update(navigation_map)
		var iteration := -1
		var stable_frames := 0
		for preparation_frame in 30:
			await physics_frame
			await process_frame
			var current_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
			stable_frames = stable_frames + 1 if current_iteration == iteration and iteration > 0 else 0
			iteration = current_iteration
			if stable_frames >= 3: break
		check(stable_frames >= 3, "The support fixture starts after its real navigation mesh is synchronized")
	if kind == &"trained_support":
		# Warm real perception, aim and fire timing before isolating the bridge.
		for frame in 45:
			await physics_frame
			for actor in f.actors: actor.get_node("AI")._physics_process(STEP)
		for actor in f.actors: actor.get_node("AI")._cancel_utility_execution(&"test_setup")
		f.actors[0].ammo.magazine_rounds = 6
		f.actors[1].ammo.magazine_rounds = 40
		squad.profile.level = 2
		for actor in f.actors: actor.get_node("AI").refresh_configuration(true)
	f.arena.cooperation.reset()
	if kind == &"trained_support":
		for actor in f.actors:
			var ai = actor.get_node("AI")
			ai.context.update_evidence(0.0, ai.context.perception.can_see_player())
			ai.context.spatial.advance_evaluation()
			ai.context.prepare_coordination_evaluation()
			ai.context.cooperation_publish_execution({})
		for index in f.actors.size():
			var ai = f.actors[index].get_node("AI")
			var scored: Array[Dictionary] = ai.action_selector.assess_options(ai, ai.context.sees_player)
			ai.context.coordination_choices(scored)
			var action = ai.actions[&"reload" if index == 0 else &"suppression"]
			ai.context.publish_coordination_offers(scored, action.coordination_offers(ai.context.sees_player))
		f.actors[0].get_node("AI").context._coordinator()._advance_coordination()
		check(f.actors[1].get_node("AI").context.coordination_assignment().get("owner_action") == &"suppression", "The real planner creates a suppression assignment from the isolated, normally scored action offers")
	var result := {"kind": kind, "roles": [], "proactive": false, "filled": false, "reload_shots": 0,
		"unsafe_start": false, "double_proactive": false, "linked_movement": 0.0, "advance_shots": 0,
		"all_empty_started": false, "fixed": true, "handoffs": 0, "completed_handoffs": 0, "premature_handoff": false, "suppression_shots": 0, "retreat_candidates": 0,
		"retreat_movement": 0.0, "retreat_shots": 0, "retreat_arrived": false, "front_transfer_movement": 0.0, "waited_for_transfer": false, "failed_handoff_seconds": -1.0,
		"transfer_plan_id": 0, "transfer_plan_filled": false, "transfer_plan_shots": 0, "transfer_plan_aborted": false, "trace": []}
	if kind == &"trained_support": result.transfer_plan_id = f.actors[1].get_node("AI").context.coordination_assignment().get("plan_id", 0)
	var rounds: Dictionary = {}
	var positions: Dictionary = {}
	var shots: Dictionary = {}
	var reloading: Dictionary = {}
	var reload_plans: Dictionary = {}
	var empty_started: Dictionary = {}
	var deadlines: Dictionary = {}
	var providers: Dictionary = {}
	var lowered := false
	var failed_plan := 0
	var lowered_at := 0.0
	for actor in f.actors:
		var id: int = actor.get_instance_id()
		actor.shot_fired.connect(_record_suppression_shot.bind(actor, result))
		rounds[id] = actor.ammo.magazine_rounds
		positions[id] = actor.global_position
		shots[id] = actor.shot_count
		reloading[id] = false
	# Observe two complete 14-second maneuver leases plus their recovery window;
	# every individual plan must still keep its original deadline throughout.
	for frame in (1800 if kind in [&"handoff", &"retreat"] else 660):
		await physics_frame
		var before: Dictionary = {}
		for actor in f.actors: before[actor.get_instance_id()] = actor.get_node("AI").context.coordination_support_state()
		if kind == &"trained_support" and not result.get("damage_received", false) and f.actors[0].ammo.is_reloading:
			var provider = f.actors[1]
			var ai = provider.get_node("AI")
			if ai.context.coordination_assignment().get("accepted", false) and ai.current_action == ai.actions[&"suppression"]:
				provider.receive_hit(1.0, f.player.global_position)
				result.damage_received = true
				result.damage_preserved = ai.current_action._running
		for actor in f.actors: actor.get_node("AI")._physics_process(STEP)
		if kind == &"transfer" and frame == 0:
			check(not f.actors[1].get_node("AI").context.sees_player, "The transferring provider begins with real target occlusion")
		var active_proactive := 0
		for actor in f.actors:
			var id: int = actor.get_instance_id()
			var ai = actor.get_node("AI")
			var assignment: Dictionary = ai.context.coordination_assignment()
			if kind == &"transfer" and result.transfer_plan_id == 0 and assignment.get("role") == &"front_support" and not ai.context.sees_player:
				result.transfer_plan_id = assignment.plan_id
			if not assignment.is_empty() and not result.roles.has(assignment.role): result.roles.append(assignment.role)
			if ai.utility_options.any(func(choice): return choice.get("coordination_role") == &"assisted_retreat"): result.retreat_candidates += 1
			if actor.ammo.is_reloading:
				if actor.ammo.magazine_rounds > 0: active_proactive += 1
				if not reloading[id]:
					reload_plans[id] = assignment.get("plan_id", 0)
					if rounds[id] == 0: empty_started[id] = true
					elif assignment.get("role") == &"assisted_reload":
						result.proactive = true
						result.unsafe_start = result.unsafe_start or not before[id].get("ready", false)
				for other in f.actors:
					if other != actor:
						var fired: int = maxi(0, other.shot_count - int(shots[other.get_instance_id()]))
						result.reload_shots += fired
						if result.transfer_plan_id != 0 and reload_plans.get(id, 0) == result.transfer_plan_id: result.transfer_plan_shots += fired
			if reloading[id] and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > rounds[id]: result.filled = true
			if reloading[id] and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > rounds[id] and result.transfer_plan_id != 0 and reload_plans.get(id, 0) == result.transfer_plan_id:
				result.transfer_plan_filled = true
			var moved: float = actor.global_position.distance_to(positions[id])
			var support: Dictionary = ai.context.coordination_support_state()
			if assignment.get("role") == &"front_support" and actor.global_position.distance_to(assignment.get("staging_position", actor.global_position)) > 0.35:
				result.front_transfer_movement += moved
				for other in f.actors:
					var other_task: Dictionary = other.get_node("AI").context.coordination_assignment()
					if other_task.get("role") == &"assisted_reload" and not other.ammo.is_reloading: result.waited_for_transfer = true
			if support.get("linked", false) and assignment.get("role") in [&"flank", &"team_position", &"assisted_retreat"]:
				result.linked_movement += moved
				if assignment.role == &"assisted_retreat" and ai.utility_current.get("id") == &"covering_retreat":
					result.retreat_movement += moved
					var retreat_action = ai.actions[&"covering_retreat"]
					result.retreat_arrived = result.retreat_arrived or retreat_action.transfer.phase == retreat_action.transfer.Phase.HIDE
				if moved > 0.005:
					for other in f.actors:
						if other.get_instance_id() == support.provider_id:
							var count: int = maxi(0, other.shot_count - int(shots[other.get_instance_id()]))
							result.advance_shots += count
							if assignment.role == &"assisted_retreat": result.retreat_shots += count
			positions[id] = actor.global_position
			rounds[id] = actor.ammo.magazine_rounds
			reloading[id] = actor.ammo.is_reloading
		result.double_proactive = result.double_proactive or active_proactive > 1
		for actor in f.actors: shots[actor.get_instance_id()] = actor.shot_count
		result.all_empty_started = empty_started.size() == f.actors.size()
		if result.transfer_plan_id != 0 and not result.transfer_plan_filled:
			result.transfer_plan_aborted = result.transfer_plan_aborted or not f.actors.any(func(actor): return actor.get_node("AI").context.coordination_assignment().get("plan_id", 0) == result.transfer_plan_id)
		for shared: Dictionary in f.arena.cooperation.coordination_debug_snapshot(&"_coordination_plans").values():
			if deadlines.has(shared.plan_id): result.fixed = result.fixed and deadlines[shared.plan_id] == shared.expires_at
			else: deadlines[shared.plan_id] = shared.expires_at
			if not shared.get("handoff", {}).is_empty(): result.handoffs += 1
			for link: Dictionary in shared.get("support_links", []):
				var key: Array = [shared.plan_id, link.beneficiary_id]
				if providers.has(key) and providers[key] != link.provider_id:
					result.completed_handoffs += 1
					var provider = f.arena.cooperation._context(link.provider_id)
					var actual: Dictionary = provider.squad_coordinator._coordination_actual(provider, shared.target_id)
					result.premature_handoff = result.premature_handoff or not actual.fire_ready
				providers[key] = link.provider_id
				if kind in [&"handoff", &"handoff_unavailable"] and not lowered and shared.phase == &"executing" and (kind == &"handoff_unavailable" or (shared.tactic == &"flank" and shared.assignments.size() < f.actors.size() and shared.expires_at - f.arena.cooperation.elapsed > 3.0)):
					# Change ammunition, not the selected action or any readiness fact.
					# A continuing flank still needs fire; a short completed deployment
					# is correctly allowed to end before an unnecessary handoff finishes.
					var provider = f.arena.cooperation._context(link.provider_id).actor
					provider.ammo.magazine_rounds = mini(provider.ammo.magazine_rounds, 13)
					lowered = true
					failed_plan = shared.plan_id
					lowered_at = f.arena.cooperation.elapsed
		if kind == &"handoff_unavailable" and lowered and result.failed_handoff_seconds < 0.0 and not f.arena.cooperation.coordination_debug_snapshot(&"_coordination_plans").values().any(func(shared): return shared.plan_id == failed_plan):
			result.failed_handoff_seconds = f.arena.cooperation.elapsed - lowered_at
		if frame % 60 == 0:
			var row: Array = [frame]
			for actor in f.actors:
				var ai = actor.get_node("AI")
				row.append({"action": ai.utility_current.get("id"), "role": ai.context.coordination_assignment().get("role"), "rounds": actor.ammo.magazine_rounds, "reload": actor.ammo.is_reloading, "support": ai.context.coordination_support_state(),
					"retreat_options": ai.utility_options.filter(func(choice): return choice.id == &"covering_retreat").map(func(choice): return {"role": choice.get("coordination_role"), "cost": choice.cost, "position": choice.destination.hide}), "baseline": ai.context.squad_coordinator._coordination_baselines.get(actor.get_instance_id(), {})})
			result.trace.append(row)
	print("SUPPORT_SAMPLE ", JSON.stringify(result))
	await _dispose(f)
	return result

func _record_suppression_shot(actor, result: Dictionary) -> void:
	# Sample at the actual shot, before on_shot_fired can retire the final wave
	# or another member can retire the plan in the same physics step.
	var ai = actor.get_node("AI")
	var assignment: Dictionary = ai.context.coordination_assignment()
	if result.kind == &"trained_support" and assignment.get("plan_id", 0) != result.transfer_plan_id: return
	if ai.utility_current.get("id") == &"suppression" and assignment.get("owner_action") == &"suppression" and assignment.get("accepted", false):
		result.suppression_shots += 1

func _retreat_cover(f: Dictionary, kind: StringName) -> void:
	var region: NavigationRegion3D = f.arena.get_node("NavigationRegion3D")
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	cover.position = Vector3(4, 1.1, 1.5) if kind == &"retreat" else Vector3(6, 1.1, 3.5)
	cover.rotation.y = PI * 0.5
	if kind == &"transfer":
		cover.get_node("CollisionShape3D").shape.size.x = 5.0
		cover.get_node("Mesh").mesh.size.x = 5.0
	region.add_child(cover)
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var xs: Array[float] = [-8.0, 5.1, 6.9, 8.0]
	var zs: Array[float] = [-8.0, 0.1, 6.9, 8.0]
	if kind == &"retreat":
		xs = [-8.0, 3.1, 4.9, 8.0]
		zs = [-8.0, -0.9, 3.9, 8.0]
	for z in zs:
		for x in xs: vertices.append(Vector3(x, 0.5, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if x == 1 and z == 1: continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	region.navigation_mesh = mesh
