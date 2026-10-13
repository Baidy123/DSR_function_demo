extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

func _run() -> void:
	var spread: Dictionary = await _posture_case(&"disperse")
	check(spread.postures.has(&"disperse") and spread.assigned_movement > 1.0, "Clustered strong members select and physically execute complementary deployment")
	check(spread.maximum_far <= 1 and spread.front_shots > 0, "Three-member deployment preserves a real shooting front and the half-team quota")
	var compact: Dictionary = await _posture_case(&"concentrate")
	check(compact.postures.has(&"concentrate") and compact.concentrate_movement > 1.0 and compact.nearest < compact.initial_nearest - 1.0, "An isolated member physically closes toward an available supporting ally")
	var hold: Dictionary = await _posture_case(&"hold")
	check(hold.assigned_movement < 0.1 and hold.shots > 0, "An already complementary legal deployment keeps ordinary real fire")
	check(spread.fixed_deadlines and compact.fixed_deadlines and hold.fixed_deadlines, "Deployment decisions and continued execution never extend original deadlines")
	print("TEAM POSTURE RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _posture_case(scenario: StringName) -> Dictionary:
	var fixture: Dictionary = await _fixture(3 if scenario == &"disperse" else 2, false)
	var actors: Array = fixture.actors
	if scenario == &"concentrate":
		actors[0].global_position = Vector3(25, fixture.ground_y, -1.5)
		actors[1].global_position = Vector3(27, fixture.ground_y, 6.0)
	elif scenario == &"hold":
		actors[0].global_position = Vector3(25, fixture.ground_y, 0)
		actors[1].global_position = Vector3(15, fixture.ground_y, 0)
	for actor in actors:
		actor.look_at(fixture.player.global_position)
		actor.get_node("AI").reset_actions()
	fixture.arena.cooperation.reset()
	var binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd").new()
	binding.profile.level = 2
	fixture.arena.team_cooperation_bindings.assign([binding])
	fixture.arena.enemy_environment()
	for actor in actors: actor.get_node("AI").refresh_configuration()
	var result := {"scenario": scenario, "postures": [], "assigned_movement": 0.0, "concentrate_movement": 0.0,
		"initial_nearest": actors[0].global_position.distance_to(actors[1].global_position), "nearest": INF,
		"shots": 0, "front_shots": 0, "maximum_far": 0, "fixed_deadlines": true, "plans": 0, "reasons": {}}
	var previous: Dictionary = {}
	var deadlines: Dictionary = {}
	for actor in actors: previous[actor.get_instance_id()] = actor.global_position
	for frame in 900:
		await physics_frame
		var far := 0
		for actor in actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var assignment: Dictionary = ai.context.coordination_assignment()
			if not assignment.is_empty(): result.assigned_movement += actor.global_position.distance_to(previous[actor.get_instance_id()])
			if ai.utility_current.get("destination", {}).get("team_posture") == &"concentrate": result.concentrate_movement += actor.global_position.distance_to(previous[actor.get_instance_id()])
			previous[actor.get_instance_id()] = actor.global_position
			if actor.global_position.x < fixture.player.global_position.x - 0.5: far += 1
		result.maximum_far = maxi(result.maximum_far, far)
		result.nearest = minf(result.nearest, actors[0].global_position.distance_to(actors[1].global_position))
		for plan_value: Dictionary in fixture.arena.cooperation._coordination_plans.values():
			result.plans += 1
			if not result.postures.has(plan_value.get("posture")): result.postures.append(plan_value.get("posture"))
			if deadlines.has(plan_value.plan_id): result.fixed_deadlines = result.fixed_deadlines and deadlines[plan_value.plan_id] == plan_value.expires_at
			else: deadlines[plan_value.plan_id] = plan_value.expires_at
	for actor in actors:
		result.shots += actor.shot_count
		if actor.global_position.x > fixture.player.global_position.x + 0.5: result.front_shots += actor.shot_count
	print("POSTURE_SAMPLE ", JSON.stringify(result))
	await _dispose(fixture)
	return result
