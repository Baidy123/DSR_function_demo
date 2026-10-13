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
	check(handoff.suppression_shots + reload_case.suppression_shots > 0, "An individually trained suppression action can execute assigned support with real shots")
	var retreat: Dictionary = await _support_case(&"retreat")
	check(retreat.roles.has(&"assisted_retreat") and retreat.retreat_movement > 0.5 and retreat.retreat_shots > 0 and retreat.retreat_arrived, "A planned retreat reaches real cover under assigned allied fire")
	var transfer: Dictionary = await _support_case(&"transfer")
	check(transfer.front_transfer_movement > 0.5 and transfer.waited_for_transfer and transfer.proactive and transfer.filled and not transfer.unsafe_start, "A hidden provider physically reaches its firing position before the dependent reload starts")
	var unavailable: Dictionary = await _support_case(&"handoff_unavailable")
	check(unavailable.failed_handoff_seconds >= 0.0 and unavailable.failed_handoff_seconds <= 2.35, "Without a spare, an actual low-ammo provider releases the dependency within the fixed recovery window")
	check(reload_case.fixed and advance.fixed and empty.fixed and handoff.fixed and retreat.fixed and transfer.fixed and unavailable.fixed, "Support preparation, execution and handoff preserve fixed plan deadlines")
	print("TEAM SUPPORT EXECUTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _support_case(kind: StringName) -> Dictionary:
	var f: Dictionary = await _fixture(2 if kind in [&"transfer", &"retreat", &"handoff_unavailable"] else 3, false)
	var binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd").new()
	binding.profile.level = 2
	if kind == &"transfer": binding.profile.deployment_spacing = 1.5
	f.arena.team_cooperation_bindings.assign([binding])
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
		actor.ammo.magazine_rounds = 0 if kind == &"empty" else (6 if kind in [&"reload", &"transfer"] and index == 0 else 40)
		ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 12)
		ai.training.profile.set_setting(&"tactics", &"support_burst_shot_count", 12)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 0.4)
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
			actor.global_position = Vector3(27.4, f.ground_y, 2.5)
			actor.look_at(f.player.global_position)
	f.arena.cooperation.reset()
	var result := {"kind": kind, "roles": [], "proactive": false, "filled": false, "reload_shots": 0,
		"unsafe_start": false, "double_proactive": false, "linked_movement": 0.0, "advance_shots": 0,
		"all_empty_started": false, "fixed": true, "handoffs": 0, "completed_handoffs": 0, "premature_handoff": false, "suppression_shots": 0, "retreat_candidates": 0,
		"retreat_movement": 0.0, "retreat_shots": 0, "retreat_arrived": false, "front_transfer_movement": 0.0, "waited_for_transfer": false, "failed_handoff_seconds": -1.0, "trace": []}
	var rounds: Dictionary = {}
	var positions: Dictionary = {}
	var shots: Dictionary = {}
	var reloading: Dictionary = {}
	var empty_started: Dictionary = {}
	var deadlines: Dictionary = {}
	var providers: Dictionary = {}
	var lowered := false
	var failed_plan := 0
	var lowered_at := 0.0
	for actor in f.actors:
		var id: int = actor.get_instance_id()
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
		for actor in f.actors: actor.get_node("AI")._physics_process(STEP)
		var active_proactive := 0
		for actor in f.actors:
			var id: int = actor.get_instance_id()
			var ai = actor.get_node("AI")
			var assignment: Dictionary = ai.context.coordination_assignment()
			if not assignment.is_empty() and not result.roles.has(assignment.role): result.roles.append(assignment.role)
			if assignment.get("owner_action") == &"suppression" and assignment.get("accepted", false): result.suppression_shots += maxi(0, actor.shot_count - int(shots[id]))
			if ai.utility_options.any(func(choice): return choice.get("coordination_role") == &"assisted_retreat"): result.retreat_candidates += 1
			if actor.ammo.is_reloading:
				if actor.ammo.magazine_rounds > 0: active_proactive += 1
				if not reloading[id]:
					if rounds[id] == 0: empty_started[id] = true
					elif assignment.get("role") == &"assisted_reload":
						result.proactive = true
						result.unsafe_start = result.unsafe_start or not before[id].get("ready", false)
				for other in f.actors:
					if other != actor: result.reload_shots += maxi(0, other.shot_count - int(shots[other.get_instance_id()]))
			if reloading[id] and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > rounds[id]: result.filled = true
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
		for shared: Dictionary in f.arena.cooperation._coordination_plans.values():
			if deadlines.has(shared.plan_id): result.fixed = result.fixed and deadlines[shared.plan_id] == shared.expires_at
			else: deadlines[shared.plan_id] = shared.expires_at
			if not shared.get("handoff", {}).is_empty(): result.handoffs += 1
			for link: Dictionary in shared.get("support_links", []):
				var key: Array = [shared.plan_id, link.beneficiary_id]
				if providers.has(key) and providers[key] != link.provider_id:
					result.completed_handoffs += 1
					var actual: Dictionary = f.arena.cooperation._coordination_actual(f.arena.cooperation._context(link.provider_id), shared.target_id)
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
		if kind == &"handoff_unavailable" and lowered and result.failed_handoff_seconds < 0.0 and not f.arena.cooperation._coordination_plans.values().any(func(shared): return shared.plan_id == failed_plan):
			result.failed_handoff_seconds = f.arena.cooperation.elapsed - lowered_at
		if frame % 60 == 0:
			var row: Array = [frame]
			for actor in f.actors:
				var ai = actor.get_node("AI")
				row.append({"action": ai.utility_current.get("id"), "role": ai.context.coordination_assignment().get("role"), "rounds": actor.ammo.magazine_rounds, "reload": actor.ammo.is_reloading, "support": ai.context.coordination_support_state(),
					"retreat_options": ai.utility_options.filter(func(choice): return choice.id == &"covering_retreat").map(func(choice): return {"role": choice.get("coordination_role"), "cost": choice.cost, "position": choice.destination.hide}), "baseline": ai.context.cooperation._coordination_baselines.get(actor.get_instance_id(), {})})
			result.trace.append(row)
	print("SUPPORT_SAMPLE ", JSON.stringify(result))
	await _dispose(f)
	return result

func _retreat_cover(f: Dictionary, kind: StringName) -> void:
	var region: NavigationRegion3D = f.arena.get_node("NavigationRegion3D")
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	cover.position = Vector3(4, 1.1, 1.5) if kind == &"retreat" else Vector3(6, 1.1, 3.5)
	cover.rotation.y = PI * 0.5
	region.add_child(cover)
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var xs: Array[float] = [-8.0, 5.1, 6.9, 8.0]
	var zs: Array[float] = [-8.0, 1.1, 5.9, 8.0]
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
