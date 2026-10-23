extends RefCounted

## Bounded route proposals from the squad ledger. Never issues assignments or
## invokes personal search/Utility. Forecast area is not an observation report.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Visual = preload("res://scripts/enemy/services/enemy_visual_observation.gd")
const Walk = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")

func sites(coverage, position: Vector3, center: Vector3, radius: float, now: float, member_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var watches: Array[Dictionary] = []
	for key in coverage.cells:
		var cell: Dictionary = coverage.cells[key]
		if cell.retry_at > now or absf(cell.position.y - position.y) > 1.0: continue
		if cell.responsibility != 0 and cell.responsibility != member_id: continue
		var samples: PackedVector3Array = coverage.unfinished(key, now)
		var watch := samples.is_empty()
		if watch:
			var last := INF
			for sample in cell.samples: last = minf(last, float(sample.observed_at))
			# Once the remaining blind patches have no feasible route, keep
			# observing older, separated posts instead of parking every member.
			if now - last < 8.0 or Contract.horizontal(position, cell.observer_position) < 3.0: continue
			for sample in cell.samples: samples.append(sample.position)
		var known: bool = coverage.state(cell, now) == &"revisit"
		var distance := Contract.horizontal(position, cell.observer_position)
		var clue_distance := Contract.horizontal(center, cell.position)
		var cost := distance + minf(clue_distance, radius) * 0.35 + (12.0 if known else 0.0)
		var site := {"position": cell.observer_position, "look_position": samples[0],
			"site_key": "map:" + key, "coverage_key": key, "coverage_version": coverage.map_version,
			"observation_samples": samples, "expected_area": 0.0 if watch else samples.size() * coverage.SAMPLE_AREA,
			"sync_key": "", "observation_mode": &"inspect" if watch else &"sweep", "priority_cost": cost,
			"geometry_version": cell.geometry_version, "clue_distance": clue_distance, "revisit": known or watch}
		if watch: watches.append(site)
		else: result.append(site)
	result.sort_custom(func(a, b): return a.priority_cost < b.priority_cost)
	result = result.slice(0, 24)
	if result.size() < 12:
		watches.sort_custom(func(a, b): return a.priority_cost < b.priority_cost)
		result.append_array(watches.slice(0, 4))
	return result

func extend(ctx, candidate: Dictionary, coverage, options: Array, deadline: int) -> void:
	if not candidate.has("coverage_key"): return
	var future: Array[Dictionary] = []
	var from: Vector3 = candidate.position
	var used := {candidate.coverage_key: true}
	for option in options:
		if future.size() >= 2 or Time.get_ticks_usec() >= deadline: break
		if not option.has("coverage_key"): continue
		if float(option.get("expected_area", 0.0)) <= 0.0: continue
		if used.has(option.coverage_key): continue
		if Contract.horizontal(from, option.position) < 1.0: continue
		var path: PackedVector3Array = ctx.cover_selection._path_to(from, option.position)
		if path.is_empty() or not Walk._walkable_path(ctx, path, ctx.coordination_motion_state().radius): continue
		if not Visual.clear_from(ctx, option.position + Vector3.UP * ctx.actor.get_body_height() * 0.85, option.look_position): continue
		var step: Dictionary = option.duplicate(true)
		step.route = path
		step.clue_version = candidate.get("search_revision", 0)
		step.completion = &"verified_samples"
		step.resume = &"coordinator_revalidate"
		future.append(step)
		used[option.coverage_key] = true
		from = option.position
	candidate.future_steps = future
	candidate.route_id = "%s:%s:%s" % [coverage.map_version, candidate.get("search_revision", 0), candidate.coverage_key]
