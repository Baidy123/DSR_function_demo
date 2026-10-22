extends "res://tests/enemy/enemy_search_formation_fallback_test.gd"

## Saved-map regression for ordinary search, including the real failure where
## two idle searches were hidden by the third member's successful flank.
func _run() -> void:
	for level in [0, 1]:
		if not OS.get_cmdline_user_args().has("--occupied-clue"):
			await _personal_search_case(level)
		await _occupied_clue_case(level)
	print("PERSONAL SEARCH RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _enter_left_cover(level: int, initial_frames: int = 20) -> void:
	seed(20261021)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3.ZERO)
	actors = Fixture.members(arena)
	var squad = arena.get_node("Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	for actor in actors:
		actor.get_node("AI").refresh_configuration(true)
		actor.look_at(player.global_position)
	for frame in initial_frames: await physics_frame
	check(actors.filter(func(a): return a.get_node("AI").context.sees_player).size() == 1, "Level %d: only one original member establishes real initial sight" % level)
	for point in [Vector3(-2.2, 0, -1.9), Vector3(-4.84, 0, -1.9), Vector3(-4.84, 0, -0.2)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.08)
			await physics_frame
	check(actors.all(func(a): return not a.get_node("AI").context.sees_player), "Level %d: actual left-cover retreat breaks all personal sight" % level)

func _personal_search_case(level: int) -> void:
	await _enter_left_cover(level)
	var origins: Array = actors.map(func(a): return a.global_position)
	var progressed := {}
	var contact := -1
	var minimum := INF
	var unauthorized := false
	for frame in 600:
		await physics_frame
		for index in actors.size():
			var actor = actors[index]
			var context = actor.get_node("AI").context
			if actor.global_position.distance_to(origins[index]) > 1.0 and not progressed.has(index): progressed[index] = frame
			if context.sees_player and contact < 0: contact = frame
			var task: Dictionary = context.coordination_assignment()
			unauthorized = unauthorized or not context.inspection_order().is_empty() or (not task.is_empty() and (level == 0 or task.get("constraint_mode") != &"advisory"))
			for other in range(index): minimum = minf(minimum, actor.global_position.distance_to(actors[other].global_position))
	check(progressed.size() == actors.size() and progressed.values().all(func(frame): return frame < 180), "Level %d: every member actually advances within three seconds; one flanker cannot mask idle searches" % level)
	check(contact >= 0 and contact < 480, "Level %d: personal search reacquires around the real wall within eight seconds" % level)
	check(not unauthorized and minimum >= 0.69, "Level %d: real body clearance and the configured task permissions remain valid" % level)
	print("PERSONAL SEARCH level=", level, " first_moves=", progressed, " contact=", contact, " minimum=", minimum)
	scene.queue_free()
	await physics_frame

## Keep a teammate's real destination reservation occupied after an action
## handoff. Search must choose another reachable point without waiting for that
## lease to expire, and without acquiring the occupied position itself.
func _occupied_clue_case(level: int) -> void:
	await _enter_left_cover(level, 30)
	for actor in actors:
		actor.get_node("AI").set_physics_process(false)
		actor.get_node("AI").reset_actions()
	var ai = actors[0].get_node("AI")
	var blocker = actors[1].get_node("AI").context
	var clue: Vector3 = ai.context.last_known_position
	var reservation := Fixture.reserve_position(blocker, clue, 12.0)
	check(not reservation.is_empty() and not ai.context.cooperation_search_available(clue), "Level %d: a teammate genuinely reserves the retained disappearance clue" % level)
	var origin: Vector3 = actors[0].global_position
	var idle := 0
	var longest_idle := 0
	var first_search := -1
	var reserved_occupied_clue := false
	ai.set_physics_process(true)
	for frame in 240:
		await physics_frame
		idle = idle + 1 if ai.current_action == null else 0
		longest_idle = maxi(longest_idle, idle)
		if first_search < 0 and ai.utility_current.get("id") == &"search": first_search = frame
		var own: Dictionary = ai.context._coordination_reservation
		if not own.is_empty() and own.position.distance_to(clue) < 0.1: reserved_occupied_clue = true
	check(first_search >= 0 and first_search < 2 and longest_idle < 2, "Level %d: occupied clue cannot filter Search into a persistent idle state" % level)
	check(actors[0].global_position.distance_to(origin) > 1.0, "Level %d: Search actually advances to another point while the clue remains occupied" % level)
	check(not reserved_occupied_clue and blocker.cooperation.validate_reservation(blocker, reservation), "Level %d: recovery preserves the teammate's live reservation" % level)
	print("OCCUPIED CLUE level=", level, " first_search=", first_search, " longest_idle=", longest_idle, " movement=", actors[0].global_position.distance_to(origin))
	scene.queue_free()
	await physics_frame
