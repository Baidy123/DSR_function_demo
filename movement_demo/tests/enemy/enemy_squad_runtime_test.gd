extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

class CountedPlanner extends "res://scripts/enemy/services/enemy_team_planner.gd":
	var calls := 0
	var bounded := true
	func propose(snapshot: Dictionary, limits: Dictionary = {}) -> Dictionary:
		calls += 1
		var result := super.propose(snapshot, limits)
		var work: Dictionary = result.get("counters", {})
		bounded = bounded and work.get("pair_trials", 0) <= 36 and work.get("conflict_checks", 0) <= 2048
		return result

func _run() -> void:
	var legacy := OS.get_cmdline_user_args().has("--legacy")
	var layouts := [[1], [2], [3], [6]] if legacy else [[1], [2], [3], [6], [3, 3], [2, 2, 2]]
	for layout in layouts: await _sample(layout, legacy)
	print("SQUAD RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"p99_ms": 0.0, "max_ms": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	return {"p99_ms": sorted[floori(sorted.size() * 0.99)] / 1000.0, "max_ms": sorted[-1] / 1000.0}

func _sample(layout: Array, legacy: bool) -> void:
	var count := 0
	for size: int in layout: count += size
	var f: Dictionary = await _fixture(count, false)
	var board = f.arena.cooperation
	var owners: Array = []
	var groups: Array = []
	var planners: Array = []
	if legacy:
		var binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd").new()
		binding.profile.level = 2
		f.arena.team_cooperation_bindings.assign([binding])
		f.arena.enemy_environment()
		owners.append(board.coordinator_for(f.actors[0].get_node("AI").context) if board.has_method("coordinator_for") else board)
		groups.append(f.actors)
	else:
		var offset := 0
		for size: int in layout:
			var squad = load("res://scenes/world/squad.tscn").instantiate()
			squad.profile.level = 2
			f.arena.add_child(squad)
			var members: Array = f.actors.slice(offset, offset + size)
			for actor in members: actor.reparent(squad)
			owners.append(squad.coordinator)
			groups.append(members)
			offset += size
	await physics_frame
	for owner in owners:
		var planner := CountedPlanner.new()
		owner._team_planner = planner
		planners.append(planner)
	for actor in f.actors: actor.get_node("AI").refresh_configuration(true)
	check(board.registered_member_count() == count, "%s contains exactly the measured members" % [layout])
	# Drive the normal area update once, before the normal personal AI loops.
	# Disabling its automatic callback avoids measuring a second/no-op update.
	f.arena.set_physics_process(false)
	var totals: Array = []
	var individual: Array = []
	var area_times: Array = []
	var regional_times: Array = []
	var owner_times: Array = []
	for owner in owners: owner_times.append([])
	var isolated := true
	var points := 0
	for frame in 600:
		await physics_frame
		var start := Time.get_ticks_usec()
		var area_start := Time.get_ticks_usec()
		board.advance(STEP)
		area_times.append(Time.get_ticks_usec() - area_start)
		if board.get("last_region_usec") != null: regional_times.append(board.last_region_usec)
		for index in owners.size():
			if owners[index].get("last_advance_usec") != null: owner_times[index].append(owners[index].last_advance_usec)
		for actor in f.actors:
			var ai = actor.get_node("AI")
			var before := Time.get_ticks_usec()
			ai._physics_process(STEP)
			individual.append(Time.get_ticks_usec() - before)
			points += ai.context.spatial.last_evaluated_count
		totals.append(Time.get_ticks_usec() - start)
		# Validation is outside the measured AI work; it never selects actions.
		for index in groups.size():
			var ids: Array = groups[index].map(func(actor): return actor.get_instance_id())
			for actor in groups[index]:
				var context = actor.get_node("AI").context
				var assignment: Dictionary = context.coordination_assignment()
				for partner in assignment.get("partner_ids", []): isolated = isolated and ids.has(partner)
				isolated = isolated and context.tactical_map == f.arena.tactical_map
	var shots := 0
	var position_queries := 0
	for actor in f.actors:
		shots += actor.shot_count
		position_queries += actor.get_node("AI").context.position_free_queries
	var personal := _distribution(individual)
	check(shots > 0 and isolated, "%s fires through real AI while preserving squad tasks and one shared map" % [layout])
	check(personal.p99_ms < 16.0 and personal.max_ms < 50.0, "%s preserves the original personal P99 16 ms / maximum 50 ms limits" % [layout])
	check(planners.all(func(planner): return planner.bounded), "%s preserves shared 36-combination / 2048-conflict planner budgets" % [layout])
	var squad_metrics: Array = []
	for index in owners.size(): squad_metrics.append({"timing": _distribution(owner_times[index]), "plans": planners[index].calls})
	print("SQUAD_SAMPLE ", JSON.stringify({"legacy": legacy, "layout": layout, "frames": 600,
		"total": _distribution(totals), "individual": personal, "area_including_squads": _distribution(area_times),
		"region_only": _distribution(regional_times), "squads": squad_metrics, "shots": shots,
		"spatial_points": points, "position_queries": position_queries, "map": f.arena.tactical_map.statistics()}))
	await _dispose(f)
