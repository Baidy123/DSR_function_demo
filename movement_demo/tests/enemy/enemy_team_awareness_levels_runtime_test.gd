extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

func _run() -> void:
	for count in [1, 2, 3, 6]:
		var intel: Dictionary = await _awareness_run(count, 0)
		var tactical: Dictionary = await _awareness_run(count, 1)
		check(intel.advice == 0 and intel.assigned == 0 and intel.cooperate_frames == 0, "%d intel-only members keep ordinary execution without tactical offers or assignments" % count)
		check(tactical.assigned == 0 and tactical.waiting == 0, "%d tactical members never enter strong assignments or partner waits" % count)
		check(intel.shots > 0 and tactical.shots > 0, "%d members actually fire in both awareness modes" % count)
		if count > 1:
			check(intel.shared and tactical.shared, "%d members preserve real sight reports in both modes" % count)
			check(tactical.advice > 0 and tactical.moving > 0.5, "%d tactical members select advice through normal Utility and physically move" % count)
			check(tactical.maximum_far <= floori(count / 2.0), "%d tactical members respect the physical half-squad flank quota" % count)
			check(tactical.personal_choices, "%d advised members retain ordinary legal alternatives" % count)
			check(tactical.no_preview_reservation and tactical.fixed_deadlines, "%d recommendations reserve only after selection and retain fixed deadlines" % count)
			check(tactical.unsupported_movement > 0.1, "%d tactical members continue legal movement during teammates' actual firing gaps" % count)
		else:
			check(tactical.advice == 0, "A single tactical member has no fictitious teammate advice")
	print("TEAM AWARENESS RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _awareness_run(count: int, level: int) -> Dictionary:
	var fixture: Dictionary = await _fixture(count, false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").attach_squad(fixture.arena, fixture.actors, level)
	await physics_frame
	fixture.arena.enemy_environment()
	for actor in fixture.actors: actor.get_node("AI").refresh_configuration()
	var result := {"count": count, "level": level, "advice": 0, "assigned": 0, "waiting": 0,
		"shots": 0, "moving": 0.0, "shared": false, "maximum_far": 0, "cooperate_frames": 0, "personal_choices": false,
		"no_preview_reservation": true, "fixed_deadlines": true, "unsupported_movement": 0.0}
	var before: Dictionary = {}
	var deadlines: Dictionary = {}
	for actor in fixture.actors: before[actor.get_instance_id()] = actor.global_position
	for frame in (240 if count == 1 else 900):
		await physics_frame
		var far := 0
		for actor in fixture.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var advice: Dictionary = task if task.get("constraint_mode") == &"advisory" else {}
			if not advice.is_empty():
				result.advice += 1
				if deadlines.has(advice.assignment_id): result.fixed_deadlines = result.fixed_deadlines and deadlines[advice.assignment_id] == advice.expires_at
				else: deadlines[advice.assignment_id] = advice.expires_at
				if not advice.accepted:
					result.no_preview_reservation = result.no_preview_reservation and not fixture.arena.cooperation._reservations.values().any(func(e): return e.get("assignment_id") == advice.assignment_id)
				var choices: Array = ai.context.coordination_choices(ai.utility_options)
				result.personal_choices = result.personal_choices or choices.any(func(c): return not c.has("coordination_role"))
			if not task.is_empty() and task.get("constraint_mode") != &"advisory": result.assigned += 1
			if ai.utility_current.get("id") == &"cooperate":
				result.cooperate_frames += 1
				result.moving += actor.global_position.distance_to(before[actor.get_instance_id()])
				if not ai.current_action._support_ready(): result.unsupported_movement += actor.global_position.distance_to(before[actor.get_instance_id()])
				if ai.current_action.phase == ai.current_action.Phase.WAIT_SUPPORT: result.waiting += 1
			if actor.global_position.x < fixture.player.global_position.x - 0.5: far += 1
			before[actor.get_instance_id()] = actor.global_position
		# The last observer's real report is now available to the other members.
		# Querying immediately after the same actor publishes would exclude itself.
		for actor in fixture.actors:
			result.shared = result.shared or not fixture.arena.cooperation.evidence(actor.get_node("AI").context, fixture.player.get_instance_id()).is_empty()
		result.maximum_far = maxi(result.maximum_far, far)
	for actor in fixture.actors: result.shots += actor.shot_count
	print("AWARENESS_SAMPLE ", JSON.stringify(result))
	await _dispose(fixture)
	return result
